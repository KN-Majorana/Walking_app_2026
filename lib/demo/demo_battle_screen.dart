import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../battle/current_location_marker.dart';
import '../battle/opponent_location_marker.dart';
import '../battle/versus/widgets/versus_polygons_overlay.dart';
import 'demo_camera_overlay.dart';
import 'demo_config.dart';
import 'demo_engine.dart';
import 'demo_photo_marker.dart';
import 'demo_result_screen.dart';

/// 対戦（active）画面のデモ版。
///
/// challenger（青・自分）と opponent（赤）の両方を [DemoEngine] に沿って
/// 自動再生する。各プレイヤーが各座標へ到達すると「カメラ起動」オーバーレイで
/// 写真を表示し、その地点に写真ピンを刺す。3 枚刺すと三角形が確定し、
/// 後から確定した青が重なりを塗り返す（VersusPolygonsOverlay の視覚的減算）。
///
/// 本物と違い、デモでは説明のために相手（赤）のピンと移動も表示する。
class DemoBattleScreen extends StatefulWidget {
  const DemoBattleScreen({super.key});

  @override
  State<DemoBattleScreen> createState() => _DemoBattleScreenState();
}

class _DemoBattleScreenState extends State<DemoBattleScreen> {
  final MapController _mapController = MapController();

  /// 対戦開始からの経過（デモ秒）。再生速度を掛けて進める。
  double _elapsed = 0;

  /// 再生速度の倍率。
  double _speed = 4;
  static const List<double> _speedChoices = [1, 4, 16, 60];

  Timer? _ticker;
  static const Duration _tickInterval = Duration(milliseconds: 50);

  final List<DemoEvent> _events = DemoEngine.buildEvents();
  final Set<int> _fired = {};

  /// 現在表示中のカメラ起動オーバーレイ（null なら非表示）。
  DemoEvent? _capture;
  Timer? _captureTimer;

  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tickInterval, _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _captureTimer?.cancel();
    super.dispose();
  }

  void _onTick(Timer _) {
    if (_ended) return;
    _elapsed += _tickInterval.inMilliseconds / 1000.0 * _speed;

    // まだ発火していないイベントを跨いだら、カメラ起動演出を出す。
    for (int i = 0; i < _events.length; i++) {
      if (_fired.contains(i)) continue;
      if (_elapsed >= _events[i].timeSec) {
        _fired.add(i);
        _showCapture(_events[i]);
      }
    }

    // 終了判定：challenger の 3 枚目 + 待ち時間。
    if (_elapsed >= DemoEngine.endSec) {
      _elapsed = DemoEngine.endSec;
      _ended = true;
      _ticker?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DemoResultScreen()),
        );
      });
    }

    if (mounted) setState(() {});
  }

  void _showCapture(DemoEvent e) {
    _captureTimer?.cancel();
    setState(() => _capture = e);
    // 高速再生でも見えるよう最低表示時間を確保しつつ、次の演出で置き換える。
    _captureTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _capture = null);
    });
  }

  Color _ownerColor(String uid) => uid == DemoConfig.challengerUid
      ? DemoConfig.challengerColor
      : DemoConfig.opponentColor;

  String _mmss(double sec) {
    final s = sec.clamp(0, DemoConfig.battleLimitSec).round();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  /// 進行状況の見出し（何枚目まで刺したか）。
  String get _progressText {
    final done = _fired.length;
    if (done >= _events.length) {
      return 'まもなく対決終了 → リザルトへ';
    }
    final next = _events[done];
    return '刺したピン: $done/6　次: ${next.label}';
  }

  @override
  Widget build(BuildContext context) {
    final t = _elapsed;
    final remaining = DemoConfig.battleLimitSec - t;

    final pins = DemoEngine.pinsAt(t);
    final polygons = DemoEngine.polygonsAt(t);
    final challengerPos = DemoEngine.challengerPosition(t);
    final opponentPos = DemoEngine.opponentPosition(t);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: DemoConfig.mapCenter,
              initialZoom: DemoConfig.mapZoom,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.demo',
                maxZoom: 19,
              ),
              // 対戦ポリゴン（本物と同じ描画：新しい方の色で重なりを塗る）
              VersusPolygonsOverlay(
                polygons: polygons,
                myUid: DemoConfig.challengerUid,
              ),
              // 写真ピン（デモでは青・赤の両方を表示）
              MarkerLayer(
                markers: [
                  for (final pin in pins)
                    Marker(
                      point: pin.position,
                      width: 54,
                      height: 54,
                      child: GestureDetector(
                        onTap: () => _openPhoto(pin.asset),
                        child: DemoPhotoMarker(
                          asset: pin.asset,
                          ringColor: _ownerColor(pin.ownerUid),
                        ),
                      ),
                    ),
                ],
              ),
              // 相手（赤）の現在位置
              MarkerLayer(
                markers: [
                  Marker(
                    point: opponentPos,
                    width: 32,
                    height: 32,
                    child: const OpponentLocationMarker(
                        color: DemoConfig.opponentColor),
                  ),
                ],
              ),
              // 自分（青）の現在位置
              MarkerLayer(
                markers: [
                  Marker(
                    point: challengerPos,
                    width: 22,
                    height: 22,
                    child: const CurrentLocationMarker(),
                  ),
                ],
              ),
            ],
          ),

          // 上部中央：カウントダウン
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _mmss(remaining),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 左上：色バッジ（あなた＝青）
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _Badge(
                  color: DemoConfig.challengerColor,
                  label: 'あなた: Blue',
                ),
              ),
            ),
          ),

          // 右上：再生速度
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _SpeedControl(
                  speed: _speed,
                  choices: _speedChoices,
                  onChanged: (v) => setState(() => _speed = v),
                ),
              ),
            ),
          ),

          // 下部：進行状況
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_kabaddi, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _progressText,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // カメラ起動オーバーレイ
          if (_capture != null)
            DemoCameraOverlay(
              asset: _capture!.asset,
              color: _ownerColor(_capture!.ownerUid),
              title: _capture!.label,
            ),
        ],
      ),
    );
  }

  void _openPhoto(String asset) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(asset),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;
  const _Badge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SpeedControl extends StatelessWidget {
  final double speed;
  final List<double> choices;
  final ValueChanged<double> onChanged;

  const _SpeedControl({
    required this.speed,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, right: 2),
            child: Icon(Icons.speed, size: 18),
          ),
          for (final c in choices)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () => onChanged(c),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: speed == c
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '×${c.toInt()}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: speed == c ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
