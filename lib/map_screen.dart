// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
// import 'color_module.dart';
// import 'photo_color_select_screen.dart';

// import 'current_location_marker.dart';
// import 'fog_clearing_service.dart';
// import 'fog_overlay.dart';
// import 'ghost_track.dart';
// import 'location_service.dart';
// import 'map_mode.dart';
// import 'mode_switcher.dart';
// import 'photo_detail_sheet.dart';
// import 'photo_list_screen.dart';
// import 'photo_pin.dart';
// import 'photo_pin_marker.dart';
// import 'photo_service.dart';
// import 'recording_controls.dart';
// import 'track_picker_sheet.dart';
// import 'track_storage_service.dart';
// import 'walk_track.dart';
// import 'ghost_marker.dart';

// class MapScreen extends StatefulWidget {
//   const MapScreen({super.key});

//   @override
//   State<MapScreen> createState() => _MapScreenState();
// }

// class _MapScreenState extends State<MapScreen> {
//   final MapController _mapController = MapController();
//   LatLng _currentPosition = const LatLng(35.1815, 136.9066);
//   bool _hasLocation = false;

//   // モード状態
//   MapMode _mode = MapMode.normal;

//   // 霧モードの晴れ範囲(メートル)
//   static const double _fogClearRadius = 30;

//   // 再生モードの速度倍率
//   static const double _ghostSpeed = 4.0;

//   // 記録状態
//   WalkTrack? _currentTrack;
//   StreamSubscription<LatLng>? _positionSub;
//   Timer? _elapsedTimer;
//   Duration _elapsed = Duration.zero;

//   // 過去の散歩記録(起動時に永続ストレージから読み込む)
//   final List<WalkTrack> _savedTracks = [];

//   // 再生モード関連
//   GhostTrack? _ghost;
//   Timer? _ghostTimer;
//   DateTime? _ghostStartedAt;
//   LatLng? _ghostPosition;

//   // 写真ピン(撮影した位置に表示)
//   final List<PhotoPin> _photoPins = [];

//   bool get _isRecording => _currentTrack != null && _currentTrack!.isActive;

//   @override
//   void initState() {
//     super.initState();
//     _loadCurrentLocation();
//     _loadSavedTracks();
//     _loadSavedPhotoPins();
//   }

//   Future<void> _loadSavedPhotoPins() async {
//     try {
//       final pins = await PhotoService.loadAllPhotoPins();
//       if (!mounted) return;
//       setState(() {
//         _photoPins
//           ..clear()
//           ..addAll(pins);
//       });
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('写真の読み込みに失敗: $e')));
//     }
//   }

//   @override
//   void dispose() {
//     _positionSub?.cancel();
//     _elapsedTimer?.cancel();
//     _ghostTimer?.cancel();
//     super.dispose();
//   }

//   Future<void> _loadCurrentLocation() async {
//     try {
//       final pos = await LocationService.getCurrentPosition();
//       if (!mounted) return;
//       setState(() {
//         _currentPosition = pos;
//         _hasLocation = true;
//       });
//       _mapController.move(_currentPosition, 15.0);
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('位置情報取得失敗: $e')));
//     }
//   }

//   Future<void> _loadSavedTracks() async {
//     try {
//       final tracks = await TrackStorageService.loadAll();
//       if (!mounted) return;
//       setState(() {
//         _savedTracks
//           ..clear()
//           ..addAll(tracks);
//       });
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('過去の記録の読み込みに失敗: $e')));
//     }
//   }

//   // ─── 記録開始 ───
//   void _startRecording() {
//     final now = DateTime.now();
//     setState(() {
//       _currentTrack = WalkTrack(
//         id: now.millisecondsSinceEpoch.toString(),
//         startedAt: now,
//         points: _hasLocation
//             ? [TrackPoint(position: _currentPosition, timestamp: now)]
//             : [],
//       );
//       _elapsed = Duration.zero;
//     });

//     // 位置情報の継続取得
//     _positionSub = LocationService.watchPosition().listen((pos) {
//       if (!mounted || !_isRecording) return;
//       setState(() {
//         _currentPosition = pos;
//         _hasLocation = true;
//         _currentTrack = _currentTrack!.copyWith(
//           points: [
//             ..._currentTrack!.points,
//             TrackPoint(position: pos, timestamp: DateTime.now()),
//           ],
//         );
//       });
//     });

//     // 経過時間タイマー(1秒ごと)
//     _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//       if (!mounted || !_isRecording) return;
//       setState(() {
//         _elapsed = DateTime.now().difference(_currentTrack!.startedAt);
//       });
//     });
//   }

//   // ─── 記録停止 ───
//   Future<void> _stopRecording() async {
//     _positionSub?.cancel();
//     _positionSub = null;
//     _elapsedTimer?.cancel();
//     _elapsedTimer = null;

//     final count = _currentTrack?.points.length ?? 0;
//     final finished = _currentTrack?.copyWith(endedAt: DateTime.now());
//     setState(() {
//       _currentTrack = finished;
//       if (finished != null && finished.points.isNotEmpty) {
//         _savedTracks.add(finished);
//       }
//     });

//     if (mounted) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text('記録を停止しました($count点)')));
//     }

//     // 永続化
//     if (finished != null && finished.points.isNotEmpty) {
//       try {
//         await TrackStorageService.save(finished);
//       } catch (e) {
//         if (!mounted) return;
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text('記録の保存に失敗: $e')));
//       }
//     }
//   }

//   /// 霧を晴らすために使う、全軌跡の座標リストを作る。
//   List<LatLng> _clearedPointsForFog() {
//     final tracks = <WalkTrack>[
//       ..._savedTracks,
//       if (_currentTrack != null && _currentTrack!.points.isNotEmpty)
//         _currentTrack!,
//     ];
//     return FogClearingService.clearedPointsFromTracks(tracks);
//   }

//   // ─── モード切替時のフック ───
//   void _onModeChanged(MapMode mode) {
//     setState(() => _mode = mode);
//     if (mode == MapMode.animation) {
//       _startGhostPlayback();
//     } else {
//       _stopGhostPlayback();
//     }
//   }

//   // ─── 再生開始 ───
//   // [target] を省略すると最新の保存済み軌跡を使う。
//   void _startGhostPlayback({WalkTrack? target}) {
//     _stopGhostPlayback();

//     final selected =
//         target ?? (_savedTracks.isNotEmpty ? _savedTracks.last : null);

//     if (selected == null || selected.points.length < 2) {
//       if (mounted) {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(const SnackBar(content: Text('再生できる記録がありません')));
//       }
//       return;
//     }

//     final ghost = GhostTrack(selected, speed: _ghostSpeed);
//     setState(() {
//       _ghost = ghost;
//       _ghostStartedAt = DateTime.now();
//       _ghostPosition = selected.points.first.position;
//     });

//     // 軌跡の先頭にカメラを寄せる
//     _mapController.move(selected.points.first.position, 16.0);

//     _ghostTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
//       if (!mounted || _ghost == null || _ghostStartedAt == null) return;
//       var elapsed = DateTime.now().difference(_ghostStartedAt!);

//       // 終端まで行ったらループ再生する
//       if (_ghost!.isFinished(elapsed)) {
//         _ghostStartedAt = DateTime.now();
//         elapsed = Duration.zero;
//       }

//       final pos = _ghost!.positionAt(elapsed);
//       if (pos != null) {
//         setState(() => _ghostPosition = pos);
//       }
//     });
//   }

//   // ─── 再生停止 ───
//   void _stopGhostPlayback() {
//     _ghostTimer?.cancel();
//     _ghostTimer = null;
//     setState(() {
//       _ghost = null;
//       _ghostStartedAt = null;
//       _ghostPosition = null;
//     });
//   }

//   // ─── 軌跡選択シートを開く ───
//   Future<void> _openTrackPicker() async {
//     final selected = await TrackPickerSheet.show(
//       context,
//       tracks: _savedTracks,
//       selectedId: _ghost?.track.id,
//     );
//     if (selected != null && mounted) {
//       _startGhostPlayback(target: selected);
//     }
//   }

//   // ─── 写真撮影 ───
//   Future<void> _takePhoto() async {
//     try {
//       // 撮影直前に最新の現在地を取りに行く
//       LatLng photoPosition = _currentPosition;

//       try {
//         photoPosition = await LocationService.getCurrentPosition();
//       } catch (_) {
//         // 取得できなければ最後に分かっている現在地を使う
//       }

//       // 1. カメラ起動 → Use Photo後に画像バイト列だけ取得
//       final imageBytes = await PhotoService.takePhotoBytes();
//       if (imageBytes == null) return; // キャンセル
//       if (!mounted) return;

//       // 2. 今の自動色抽出を使って、初期選択色を作る
//       final initialColorIds = extractColorIdsFromImageBytes(imageBytes);

//       // 3. 12色から最大3色選べる画面を開く
//       final selected = await Navigator.push<PhotoColorSelectionResult>(
//         context,
//         MaterialPageRoute(
//           builder: (_) => PhotoColorSelectScreen(
//             imageBytes: imageBytes,
//             initialColorIds: initialColorIds,
//             maxSelectableColors: 3,
//           ),
//         ),
//       );

//       // 色選択画面でキャンセルされた場合
//       if (selected == null) return;
//       if (!mounted) return;

//       // 4. ユーザーが選んだ色でDB保存
//       final pin = await PhotoService.savePhotoWithColorIds(
//         imageBytes: selected.imageBytes,
//         colorIds: selected.colorIds,
//         position: photoPosition,
//       );

//       if (!mounted) return;

//       setState(() {
//         _photoPins.add(pin);
//       });

//       final colorNames = getColorNamesFromIds(pin.colorIds);

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(
//             colorNames.isEmpty
//                 ? '写真を保存しました（分類色: なし）'
//                 : '写真を保存しました（分類色: ${colorNames.join(', ')}）',
//           ),
//           duration: const Duration(seconds: 4),
//         ),
//       );
//     } catch (e) {
//       if (!mounted) return;

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('撮影に失敗: $e')),
//       );
//     }
//   }

//   Future<void> _openPhotoList() async {
//     final deletedIds = await Navigator.push<List<String>>(
//       context,
//       MaterialPageRoute(
//         builder: (_) => PhotoListScreen(photoPins: _photoPins),
//       ),
//     );

//     if (!mounted) return;

//     if (deletedIds != null && deletedIds.isNotEmpty) {
//       setState(() {
//         _photoPins.removeWhere((pin) => deletedIds.contains(pin.id));
//       });

//       imageCache.clear();
//       imageCache.clearLiveImages();
//     }
//   }

//   // ─── 再生モード時の「軌跡選択カード」 ───
//   Widget _buildTrackPickerButton() {
//     final current = _ghost?.track;
//     final label = current == null
//         ? '記録を選ぶ'
//         : '${current.startedAt.month}/${current.startedAt.day} '
//               '${current.startedAt.hour.toString().padLeft(2, '0')}:'
//               '${current.startedAt.minute.toString().padLeft(2, '0')} の散歩';

//     return Material(
//       elevation: 6,
//       borderRadius: BorderRadius.circular(16),
//       child: InkWell(
//         borderRadius: BorderRadius.circular(16),
//         onTap: _openTrackPicker,
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
//           child: Row(
//             children: [
//               const Icon(Icons.history_rounded, color: Color(0xFF2E7D32)),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     const Text(
//                       '再生中の記録',
//                       style: TextStyle(
//                         fontSize: 11,
//                         color: Colors.grey,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       label,
//                       style: const TextStyle(
//                         fontSize: 14,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Icon(Icons.expand_less_rounded, color: Colors.grey.shade600),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final trackPoints =
//         _currentTrack?.points.map((p) => p.position).toList() ?? [];
//     final clearedPoints = _mode == MapMode.fog ? _clearedPointsForFog() : null;

//     // 再生モード時にゴーストが辿っている軌跡の全座標
//     final ghostFullPath = _mode == MapMode.animation && _ghost != null
//         ? _ghost!.track.points.map((p) => p.position).toList()
//         : const <LatLng>[];

//     return Scaffold(
//       body: Stack(
//         children: [
//           // ── 地図本体 ──
//           FlutterMap(
//             mapController: _mapController,
//             options: MapOptions(
//               initialCenter: _currentPosition,
//               initialZoom: 13.0,
//               minZoom: 3.0,
//               maxZoom: 19.0,
//             ),
//             children: [
//               TileLayer(
//                 urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
//                 userAgentPackageName: 'com.example.RunnerTests',
//                 maxZoom: 19,
//               ),
//               // 通常モード: 記録中の軌跡を青線で表示
//               if (_mode == MapMode.normal && trackPoints.length >= 2)
//                 PolylineLayer(
//                   polylines: [
//                     Polyline(
//                       points: trackPoints,
//                       strokeWidth: 5,
//                       color: Colors.blue,
//                     ),
//                   ],
//                 ),
//               // 再生モード: 再生対象の軌跡全体を緑で薄く表示
//               if (_mode == MapMode.animation && ghostFullPath.length >= 2)
//                 PolylineLayer(
//                   polylines: [
//                     Polyline(
//                       points: ghostFullPath,
//                       strokeWidth: 4,
//                       color: Colors.green.withValues(alpha: 0.6),
//                     ),
//                   ],
//                 ),
//               // 霧オーバーレイ
//               if (clearedPoints != null)
//                 FogOverlay(
//                   clearedPoints: clearedPoints,
//                   clearRadius: _fogClearRadius,
//                 ),
//               // 写真ピン(全モードで表示)
//               if (_photoPins.isNotEmpty)
//                 MarkerLayer(
//                   markers: [
//                     for (final pin in _photoPins)
//                       Marker(
//                         point: pin.position,
//                         width: 56,
//                         height: 56,
//                         child: GestureDetector(
//                           onTap: () => PhotoDetailSheet.show(context, pin),
//                           child: PhotoPinMarker(imagePath: pin.imagePath),
//                         ),
//                       ),
//                   ],
//                 ),
//               // 現在地マーカー(再生モード以外)
//               if (_hasLocation && _mode != MapMode.animation)
//                 MarkerLayer(
//                   markers: [
//                     Marker(
//                       point: _currentPosition,
//                       width: 13,
//                       height: 13,
//                       child: const CurrentLocationMarker(),
//                     ),
//                   ],
//                 ),
//               // ゴーストマーカー(再生モード時)
//               if (_mode == MapMode.animation && _ghostPosition != null)
//                 MarkerLayer(
//                   markers: [
//                     Marker(
//                       point: _ghostPosition!,
//                       width: 13,
//                       height: 13,
//                       child: const GhostMarker(),
//                     ),
//                   ],
//                 ),
//             ],
//           ),

//           // ── 上部:モード切替 ──
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             child: SafeArea(
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Center(
//                   child: ModeSwitcher(
//                     currentMode: _mode,
//                     onModeChanged: _onModeChanged,
//                   ),
//                 ),
//               ),
//             ),
//           ),

//           // ── 下部:記録コントロール(通常モード時のみ) ──
//           if (_mode == MapMode.normal)
//             Positioned(
//               left: 16,
//               right: 76,
//               bottom: 0,
//               child: SafeArea(
//                 child: Padding(
//                   padding: const EdgeInsets.only(bottom: 16),
//                   child: RecordingControls(
//                     isRecording: _isRecording,
//                     pointCount: _currentTrack?.points.length ?? 0,
//                     elapsed: _elapsed,
//                     onStart: _startRecording,
//                     onStop: _stopRecording,
//                   ),
//                 ),
//               ),
//             ),

//           // ── 下部:軌跡選択カード(再生モード時のみ) ──
//           if (_mode == MapMode.animation)
//             Positioned(
//               left: 16,
//               right: 76,
//               bottom: 0,
//               child: SafeArea(
//                 child: Padding(
//                   padding: const EdgeInsets.only(bottom: 16),
//                   child: _buildTrackPickerButton(),
//                 ),
//               ),
//             ),
//         ],
//       ),

//       // 右下のFAB群(縦並び)
//       floatingActionButton: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           // 写真一覧
//           FloatingActionButton.small(
//             onPressed: _openPhotoList,
//             heroTag: 'photo_list',
//             child: const Icon(Icons.photo_library_outlined),
//           ),
//           const SizedBox(height: 8),
//           // 写真撮影(再生モード中は隠す)
//           if (_mode != MapMode.animation)
//             FloatingActionButton.small(
//               onPressed: _takePhoto,
//               heroTag: 'photo_take',
//               child: const Icon(Icons.camera_alt),
//             ),
//           if (_mode != MapMode.animation) const SizedBox(height: 8),
//           // 現在地に戻る
//           FloatingActionButton.small(
//             onPressed: _hasLocation
//                 ? () => _mapController.move(_currentPosition, 16.0)
//                 : null,
//             heroTag: 'recenter',
//             child: const Icon(Icons.my_location),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'color_module.dart';
import 'photo_color_select_screen.dart';

import 'current_location_marker.dart';
import 'fog_clearing_service.dart';
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
import 'step_counter_service.dart';
import 'track_picker_sheet.dart';
import 'track_storage_service.dart';
import 'walk_track.dart';
import 'ghost_marker.dart';

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
  MapMode _mode = MapMode.normal;

  // 霧モードの晴れ範囲(メートル)
  static const double _fogClearRadius = 30;

  // 再生モードの速度倍率
  static const double _ghostSpeed = 4.0;

  // 記録状態
  WalkTrack? _currentTrack;
  StreamSubscription<Position>? _positionSub;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  // 距離・速度・歩数
  double _distanceMeters = 0;
  double _speedKmh = 0;
  int _stepCount = 0;
  final StepCounterService _stepCounter = StepCounterService();
  StreamSubscription<int>? _stepSub;

  // 過去の散歩記録(起動時に永続ストレージから読み込む)
  final List<WalkTrack> _savedTracks = [];

  // 再生モード関連
  GhostTrack? _ghost;
  Timer? _ghostTimer;
  DateTime? _ghostStartedAt;
  LatLng? _ghostPosition;

  // 写真ピン(撮影した位置に表示)
  final List<PhotoPin> _photoPins = [];

  bool get _isRecording => _currentTrack != null && _currentTrack!.isActive;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadSavedTracks();
    _loadSavedPhotoPins();
  }

  Future<void> _loadSavedPhotoPins() async {
    try {
      final pins = await PhotoService.loadAllPhotoPins();
      if (!mounted) return;
      setState(() {
        _photoPins
          ..clear()
          ..addAll(pins);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写真の読み込みに失敗: $e')));
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _elapsedTimer?.cancel();
    _ghostTimer?.cancel();

    _stepSub?.cancel();
    _stepCounter.dispose();

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

  /// 記録開始前に「常に許可」を確認・要求する。
  ///
  /// 「常に許可」が得られなくても記録自体は開始する
  /// アプリを開いている間はGPSが取れるため。
  Future<void> _ensureBackgroundPermission() async {
    final already = await LocationService.hasBackgroundPermission();
    if (already) return;

    final granted = await LocationService.requestBackgroundPermission();
    if (!mounted) return;

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'バックグラウンドでの記録には「常に許可」が必要です。'
            '画面ロック中などは記録が止まる場合があります。',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // ─── 記録開始 ───
  Future<void> _startRecording() async {
    await _ensureBackgroundPermission();
    if (!mounted) return;

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
      _distanceMeters = 0;
      _speedKmh = 0;
      _stepCount = 0;
    });

    // 歩数カウント開始
    _stepSub?.cancel();
    _stepCounter.reset();
    _stepCounter.start();
    _stepSub = _stepCounter.stepStream.listen((steps) {
      if (!mounted) return;
      setState(() {
        _stepCount = steps;
      });
    });

    // 位置情報の継続取得
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: '散歩を記録中です',
          notificationTitle: '位置情報を取得しています',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      ),
    ).listen((position) {
      if (!mounted || !_isRecording) return;

      final newPos = LatLng(position.latitude, position.longitude);
      const dist = Distance(roundResult: false);

      setState(() {
        // 距離を加算
        if (_currentTrack!.points.isNotEmpty) {
          _distanceMeters += dist(
            _currentTrack!.points.last.position,
            newPos,
          );
        }

        // 速度 m/s → km/h
        _speedKmh = position.speed > 0 ? position.speed * 3.6 : 0;

        _currentPosition = newPos;
        _hasLocation = true;
        _currentTrack = _currentTrack!.copyWith(
          points: [
            ..._currentTrack!.points,
            TrackPoint(position: newPos, timestamp: DateTime.now()),
          ],
        );
      });
    });

    // 経過時間タイマー
    _elapsedTimer?.cancel();
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

    _stepSub?.cancel();
    _stepSub = null;
    _stepCounter.stop();

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

  /// 霧を晴らすために使う、全軌跡の座標リストを作る。
  List<LatLng> _clearedPointsForFog() {
    final tracks = <WalkTrack>[
      ..._savedTracks,
      if (_currentTrack != null && _currentTrack!.points.isNotEmpty)
        _currentTrack!,
    ];
    return FogClearingService.clearedPointsFromTracks(tracks);
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

    _mapController.move(selected.points.first.position, 16.0);

    _ghostTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _ghost == null || _ghostStartedAt == null) return;

      var elapsed = DateTime.now().difference(_ghostStartedAt!);

      if (_ghost!.isFinished(elapsed)) {
        _ghostStartedAt = DateTime.now();
        elapsed = Duration.zero;
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
    );

    if (selected != null && mounted) {
      _startGhostPlayback(target: selected);
    }
  }

  // ─── 写真撮影 ───
  Future<void> _takePhoto() async {
    try {
      // 撮影直前に最新の現在地を取りに行く
      LatLng photoPosition = _currentPosition;

      try {
        photoPosition = await LocationService.getCurrentPosition();
      } catch (_) {
        // 取得できなければ最後に分かっている現在地を使う
      }

      // 1. カメラ起動 → Use Photo後に画像バイト列だけ取得
      final imageBytes = await PhotoService.takePhotoBytes();
      if (imageBytes == null) return;
      if (!mounted) return;

      // 2. 自動色抽出で初期選択色を作る
      final initialColorIds = extractColorIdsFromImageBytes(imageBytes);

      // 3. 12色から最大3色選べる画面を開く
      final selected = await Navigator.push<PhotoColorSelectionResult>(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoColorSelectScreen(
            imageBytes: imageBytes,
            initialColorIds: initialColorIds,
            maxSelectableColors: 3,
          ),
        ),
      );

      if (selected == null) return;
      if (!mounted) return;

      // 4. ユーザーが選んだ色でDB保存
      final pin = await PhotoService.savePhotoWithColorIds(
        imageBytes: selected.imageBytes,
        colorIds: selected.colorIds,
        position: photoPosition,
      );

      if (!mounted) return;

      setState(() {
        _photoPins.add(pin);
      });

      final colorNames = getColorNamesFromIds(pin.colorIds);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            colorNames.isEmpty
                ? '写真を保存しました（分類色: なし）'
                : '写真を保存しました（分類色: ${colorNames.join(', ')}）',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撮影に失敗: $e')));
    }
  }

  Future<void> _openPhotoList() async {
    final deletedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoListScreen(photoPins: _photoPins),
      ),
    );

    if (!mounted) return;

    if (deletedIds != null && deletedIds.isNotEmpty) {
      setState(() {
        _photoPins.removeWhere((pin) => deletedIds.contains(pin.id));
      });

      imageCache.clear();
      imageCache.clearLiveImages();
    }
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
    final clearedPoints = _mode == MapMode.fog ? _clearedPointsForFog() : null;

    final ghostFullPath = _mode == MapMode.animation && _ghost != null
        ? _ghost!.track.points.map((p) => p.position).toList()
        : const <LatLng>[];

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

              // 通常モード: 記録中の軌跡を青線で表示
              if (_mode == MapMode.normal && trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints,
                      strokeWidth: 5,
                      color: Colors.blue,
                    ),
                  ],
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

              // 霧オーバーレイ
              if (clearedPoints != null)
                FogOverlay(
                  clearedPoints: clearedPoints,
                  clearRadius: _fogClearRadius,
                ),

              // 写真ピン
              if (_photoPins.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final pin in _photoPins)
                      Marker(
                        point: pin.position,
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          onTap: () => PhotoDetailSheet.show(context, pin),
                          child: PhotoPinMarker(imagePath: pin.imagePath),
                        ),
                      ),
                  ],
                ),

              // 現在地マーカー
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

              // ゴーストマーカー
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

          // ── 上部: モード切替 ──
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

          // ── 下部: 記録コントロール ──
          if (_mode == MapMode.normal)
            Positioned(
              left: 16,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: RecordingControls(
                    isRecording: _isRecording,
                    pointCount: _currentTrack?.points.length ?? 0,
                    elapsed: _elapsed,
                    distanceMeters: _distanceMeters,
                    speedKmh: _speedKmh,
                    stepCount: _stepCount,
                    onStart: _startRecording,
                    onStop: _stopRecording,
                  ),
                ),
              ),
            ),

          // ── 下部: 軌跡選択カード ──
          if (_mode == MapMode.animation)
            Positioned(
              left: 16,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildTrackPickerButton(),
                ),
              ),
            ),
        ],
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            onPressed: _openPhotoList,
            heroTag: 'photo_list',
            child: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(height: 8),

          if (_mode != MapMode.animation)
            FloatingActionButton.small(
              onPressed: _takePhoto,
              heroTag: 'photo_take',
              child: const Icon(Icons.camera_alt),
            ),

          if (_mode != MapMode.animation) const SizedBox(height: 8),

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