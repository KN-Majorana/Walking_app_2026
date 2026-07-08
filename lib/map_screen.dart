import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'battle/battle_root_screen.dart';
import 'collage_gallery_screen.dart';
import 'color_collage_screen.dart';
import 'color_extraction.dart';
import 'fog_settings_service.dart';
import 'current_location_marker.dart';
import 'fog_overlay.dart';
import 'ghost_track.dart';
import 'location_service.dart';
import 'map_mode.dart';
import 'mode_switcher.dart';
import 'photo_detail_sheet.dart';
import 'photo_list_screen.dart';
import 'photo_pin.dart';
import 'photo_pin_marker.dart';
import 'photo_service.dart';
import 'recording_controls.dart';
import 'track_picker_sheet.dart';
import 'track_storage_service.dart';
import 'walk_track.dart';
import 'ghost_marker.dart';
import 'services/photo_pin_storage_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(35.1815, 136.9066);
  bool _hasLocation = false;

  // モード状態
  MapMode _mode = MapMode.fog;

  // 再生モードの速度倍率
  static const double _ghostSpeed = 4.0;

  // 記録状態
  WalkTrack? _currentTrack;
  StreamSubscription<LatLng>? _positionSub;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  // 過去の散歩記録(起動時に永続ストレージから読み込む)
  final List<WalkTrack> _savedTracks = [];

  // 再生モード関連
  GhostTrack? _ghost;
  Timer? _ghostTimer;
  DateTime? _ghostStartedAt;
  LatLng? _ghostPosition;

  // 写真ピン(撮影した位置に表示)
  final List<PhotoPin> _photoPins = [];

  // 霧クリア設定: ピン間の最大距離（メートル）
  double _fogMaxDistance = FogSettingsService.defaultMaxDistance;

  bool get _isRecording => _currentTrack != null && _currentTrack!.isActive;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadSavedTracks();
    _loadPhotoPins();
    _loadFogSettings();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _elapsedTimer?.cancel();
    _ghostTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
      });
      _mapController.move(_currentPosition, 15.0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('位置情報取得失敗: $e')));
    }
  }

  Future<void> _loadSavedTracks() async {
    try {
      final tracks = await TrackStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        _savedTracks
          ..clear()
          ..addAll(tracks);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('過去の記録の読み込みに失敗: $e')));
    }
  }

  Future<void> _loadPhotoPins() async {
    try {
      final pins = await PhotoPinStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        _photoPins
          ..clear()
          ..addAll(pins);
      });
    } catch (_) {}
  }

  Future<void> _loadFogSettings() async {
    final dist = await FogSettingsService.loadMaxDistance();
    if (!mounted) return;
    setState(() => _fogMaxDistance = dist);
  }

  /// 「散歩の範囲は？」ダイアログを表示する。
  /// ここで選んだ距離が、同じ色の写真同士を同じ領域として
  /// コラージュ作成の対象にする範囲（霧クリア距離）として使われる。
  /// 確定した場合は true、キャンセルした場合は false を返す。
  Future<bool> _showWalkRangeDialog() async {
    double tempDistance = _fogMaxDistance;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final km = (tempDistance / 1000).toStringAsFixed(1);
          return AlertDialog(
            title: const Text('散歩の範囲は？'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '同じ色の写真同士がこの距離以内にある場合、同じ領域としてまとめてコラージュを作れるようになります。',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '$km km（${tempDistance.round()} m）',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Slider(
                  value: tempDistance,
                  min: 100,
                  max: 5000,
                  divisions: 49,
                  label: '${tempDistance.round()} m',
                  onChanged: (v) =>
                      setDialogState(() => tempDistance = v.roundToDouble()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('100 m', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    Text('5 km', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _fogMaxDistance = tempDistance);
                  FogSettingsService.saveMaxDistance(tempDistance);
                  Navigator.pop(ctx, true);
                },
                child: const Text('この範囲で記録を始める'),
              ),
            ],
          );
        },
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _savePhotoPins() async {
    try {
      await PhotoPinStorageService.saveAll(_photoPins);
    } catch (_) {}
  }

  void _deletePhotoPin(PhotoPin pin) {
    setState(() {
      _photoPins.removeWhere((p) => p.id == pin.id);
    });
    _savePhotoPins();
  }

  // ─── 記録開始フロー: 散歩の範囲を確認してから記録を始める ───
  Future<void> _startRecordingFlow() async {
    final confirmed = await _showWalkRangeDialog();
    if (!mounted || !confirmed) return;
    _startRecording();
  }

  // ─── 記録開始 ───
  void _startRecording() {
    final now = DateTime.now();
    setState(() {
      _currentTrack = WalkTrack(
        id: now.millisecondsSinceEpoch.toString(),
        startedAt: now,
        points: _hasLocation
            ? [TrackPoint(position: _currentPosition, timestamp: now)]
            : [],
      );
      _elapsed = Duration.zero;
    });

    // 位置情報の継続取得
    _positionSub = LocationService.watchPosition().listen((pos) {
      if (!mounted || !_isRecording) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
        _currentTrack = _currentTrack!.copyWith(
          points: [
            ..._currentTrack!.points,
            TrackPoint(position: pos, timestamp: DateTime.now()),
          ],
        );
      });
    });

    // 経過時間タイマー(1秒ごと)
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() {
        _elapsed = DateTime.now().difference(_currentTrack!.startedAt);
      });
    });
  }

  // ─── 記録停止 ───
  Future<void> _stopRecording() async {
    _positionSub?.cancel();
    _positionSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    final count = _currentTrack?.points.length ?? 0;
    final finished = _currentTrack?.copyWith(endedAt: DateTime.now());
    setState(() {
      _currentTrack = finished;
      if (finished != null && finished.points.isNotEmpty) {
        _savedTracks.add(finished);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('記録を停止しました($count点)')));
    }

    // 永続化
    if (finished != null && finished.points.isNotEmpty) {
      try {
        await TrackStorageService.save(finished);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('記録の保存に失敗: $e')));
      }
    }
  }

  // ─── モード切替時のフック ───
  void _onModeChanged(MapMode mode) {
    setState(() => _mode = mode);
    if (mode == MapMode.animation) {
      _startGhostPlayback();
    } else {
      _stopGhostPlayback();
    }
  }

  // ─── 再生開始 ───
  // [target] を省略すると最新の保存済み軌跡を使う。
  void _startGhostPlayback({WalkTrack? target}) {
    _stopGhostPlayback();

    final selected =
        target ?? (_savedTracks.isNotEmpty ? _savedTracks.last : null);

    if (selected == null || selected.points.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('再生できる記録がありません')));
      }
      return;
    }

    final ghost = GhostTrack(selected, speed: _ghostSpeed);
    setState(() {
      _ghost = ghost;
      _ghostStartedAt = DateTime.now();
      _ghostPosition = selected.points.first.position;
    });

    // 軌跡の先頭にカメラを寄せる
    _mapController.move(selected.points.first.position, 16.0);

    _ghostTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _ghost == null || _ghostStartedAt == null) return;
      final elapsed = DateTime.now().difference(_ghostStartedAt!);

      // 最後まで再生し終えたら、ループせずそこで終了する
      if (_ghost!.isFinished(elapsed)) {
        setState(() => _ghostPosition = selected.points.last.position);
        _ghostTimer?.cancel();
        _ghostTimer = null;
        return;
      }

      final pos = _ghost!.positionAt(elapsed);
      if (pos != null) {
        setState(() => _ghostPosition = pos);
      }
    });
  }

  // ─── 再生停止 ───
  void _stopGhostPlayback() {
    _ghostTimer?.cancel();
    _ghostTimer = null;
    setState(() {
      _ghost = null;
      _ghostStartedAt = null;
      _ghostPosition = null;
    });
  }

  // ─── 軌跡選択シートを開く ───
  Future<void> _openTrackPicker() async {
    final selected = await TrackPickerSheet.show(
      context,
      tracks: _savedTracks,
      selectedId: _ghost?.track.id,
      onDelete: _deleteSavedTrack,
    );
    if (selected != null && mounted) {
      _startGhostPlayback(target: selected);
    }
  }

  // ─── 保存済みの散歩記録を削除する ───
  Future<void> _deleteSavedTrack(WalkTrack track) async {
    // 削除する記録が再生中なら、先に再生を止める
    if (_ghost?.track.id == track.id) {
      _stopGhostPlayback();
    }
    setState(() {
      _savedTracks.removeWhere((t) => t.id == track.id);
    });
    try {
      await TrackStorageService.delete(track.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }

  // ─── 写真撮影 ───
  Future<void> _takePhoto() async {
    try {
      // 撮影直前に最新の現在地を取りに行く(記録中でなくても位置情報を付けたいため)
      LatLng photoPosition = _currentPosition;
      try {
        photoPosition = await LocationService.getCurrentPosition();
      } catch (_) {
        // 取得できなければ最後に分かっている現在地を使う
      }

      final path = await PhotoService.takeAndSavePhoto();
      if (path == null) return; // キャンセル
      if (!mounted) return;

      // 写真の主要色を抽出（24色パレットのインデックス）
      final colorIds = await extractColorIdsFromPath(path);

      if (!mounted) return;
      setState(() {
        _photoPins.add(
          PhotoPin(
            imagePath: path,
            position: photoPosition,
            takenAt: DateTime.now(),
            colorIds: colorIds,
            // 散歩を記録中に撮った写真だけが、領域（色クラスタ）作成の対象になる
            capturedDuringWalk: _isRecording,
          ),
        );
      });

      _savePhotoPins();

      final colorLabel = colorIds.isEmpty
          ? '色を検出できませんでした'
          : colorIds.map((id) => colorNames24[id]).join(' / ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を保存しました　[$colorLabel]')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撮影に失敗: $e')));
    }
  }

  void _openPhotoList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoListScreen(
          photoPins: _photoPins,
          onDeletePins: (ids) {
            setState(() {
              _photoPins.removeWhere((p) => ids.contains(p.id));
            });
            _savePhotoPins();
          },
        ),
      ),
    );
  }

  void _openCollageGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CollageGalleryScreen()),
    );
  }

  // ─── タップした領域(色クラスタ)専用のコラージュ作成画面を開く ───
  void _openRegionCollage(int colorId, List<PhotoPin> pins) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ColorCollageScreen(colorId: colorId, pins: pins),
      ),
    );
  }

  // ─── 再生モード時の「軌跡選択カード」 ───
  Widget _buildTrackPickerButton() {
    final current = _ghost?.track;
    final label = current == null
        ? '記録を選ぶ'
        : '${current.startedAt.month}/${current.startedAt.day} '
              '${current.startedAt.hour.toString().padLeft(2, '0')}:'
              '${current.startedAt.minute.toString().padLeft(2, '0')} の散歩';

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openTrackPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: Color(0xFF2E7D32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '再生中の記録',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_less_rounded, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackPoints =
        _currentTrack?.points.map((p) => p.position).toList() ?? [];

    // 再生モード時にゴーストが辿っている軌跡の全座標
    final ghostFullPath = _mode == MapMode.animation && _ghost != null
        ? _ghost!.track.points.map((p) => p.position).toList()
        : const <LatLng>[];

    // ── 対戦モード:地図とは別画面(Battle_Function_Ver2統合)を表示 ──
    if (_mode == MapMode.battle) {
      return Scaffold(
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ModeSwitcher(
                    currentMode: _mode,
                    onModeChanged: _onModeChanged,
                  ),
                ),
              ),
            ),
            const Expanded(child: BattleRootScreen()),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── 地図本体 ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13.0,
              minZoom: 3.0,
              maxZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.RunnerTests',
                maxZoom: 19,
              ),
              // 再生モード: 再生対象の軌跡全体を緑で薄く表示
              if (_mode == MapMode.animation && ghostFullPath.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: ghostFullPath,
                      strokeWidth: 4,
                      color: Colors.green.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              // 霧オーバーレイ（同色ピン群の凸包ポリゴンで霧を晴らす）
              if (_mode == MapMode.fog)
                FogOverlay(
                  photoPins: _photoPins,
                  maxDistanceMeters: _fogMaxDistance,
                  onRegionTap: _openRegionCollage,
                ),
              // コラージュモード: 記録中の軌跡を青線で表示
              // （霧オーバーレイより上に重ねることで、霧の中でも常に見えるようにする）
              if (_mode == MapMode.fog && trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints,
                      strokeWidth: 5,
                      color: Colors.blue,
                    ),
                  ],
                ),
              // 写真ピン(全モードで表示)
              if (_photoPins.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final pin in _photoPins)
                      Marker(
                        point: pin.position,
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          onTap: () => PhotoDetailSheet.show(
                            context,
                            pin,
                            onDelete: () => _deletePhotoPin(pin),
                          ),
                          child: PhotoPinMarker(imagePath: pin.imagePath),
                        ),
                      ),
                  ],
                ),
              // 現在地マーカー(再生モード以外)
              if (_hasLocation && _mode != MapMode.animation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 13,
                      height: 13,
                      child: const CurrentLocationMarker(),
                    ),
                  ],
                ),
              // ゴーストマーカー(再生モード時)
              if (_mode == MapMode.animation && _ghostPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _ghostPosition!,
                      width: 13,
                      height: 13,
                      child: const GhostMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // ── 上部:モード切替 ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ModeSwitcher(
                    currentMode: _mode,
                    onModeChanged: _onModeChanged,
                  ),
                ),
              ),
            ),
          ),

          // ── 下部:記録コントロール(コラージュタブ時のみ) ──
          if (_mode == MapMode.fog)
            Positioned(
              left: 76,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: RecordingControls(
                    isRecording: _isRecording,
                    pointCount: _currentTrack?.points.length ?? 0,
                    elapsed: _elapsed,
                    onStart: _startRecordingFlow,
                    onStop: _stopRecording,
                  ),
                ),
              ),
            ),

          // ── 下部:軌跡選択カード(再生モード時のみ) ──
          if (_mode == MapMode.animation)
            Positioned(
              left: 76,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildTrackPickerButton(),
                ),
              ),
            ),

          // ── 左下のタブ:完成済みコラージュ一覧 ──
          Positioned(
            left: 16,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FloatingActionButton.small(
                  onPressed: _openCollageGallery,
                  heroTag: 'collage_gallery',
                  tooltip: '完成したコラージュ',
                  child: const Icon(Icons.collections_outlined),
                ),
              ),
            ),
          ),
        ],
      ),

      // 右下のFAB群(縦並び)
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 写真一覧
          FloatingActionButton.small(
            onPressed: _openPhotoList,
            heroTag: 'photo_list',
            child: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(height: 8),
          // 写真撮影(再生モード中は隠す)
          if (_mode != MapMode.animation)
            FloatingActionButton.small(
              onPressed: _takePhoto,
              heroTag: 'photo_take',
              child: const Icon(Icons.camera_alt),
            ),
          if (_mode != MapMode.animation) const SizedBox(height: 8),
          // 現在地に戻る
          FloatingActionButton.small(
            onPressed: _hasLocation
                ? () => _mapController.move(_currentPosition, 16.0)
                : null,
            heroTag: 'recenter',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
