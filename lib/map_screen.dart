import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'battle_overlay.dart';
import 'collage_gallery_screen.dart';
import 'compass_service.dart';
import 'map_compass.dart';
import 'color_extraction.dart';
import 'crossed_swords_icon.dart';
import 'current_location_marker.dart';
import 'path_fog_overlay.dart';
import 'ghost_track.dart';
import 'location_service.dart';
import 'map_mode.dart';
import 'map_zoom.dart';
import 'mode_switcher.dart';
import 'photo_collage_screen.dart';
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
import 'services/photo_pin_storage_service.dart';
import 'services/map_fog_storage_service.dart';
import 'services/photo_display_settings_service.dart';
import 'services/battle_photo_history_service.dart';

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
  MapMode _mode = MapMode.map;

  // 再生モードの速度倍率
  static const double _ghostSpeed = 4.0;

  // 記録状態
  WalkTrack? _currentTrack;
  StreamSubscription<Position>? _positionSub;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  // walk_record 由来の計測（距離・速度・歩数）
  double _distanceMeters = 0;
  double _speedKmh = 0;
  int _stepCount = 0;
  final StepCounterService _stepCounter = StepCounterService();
  StreamSubscription<int>? _stepSub;

  // 距離計算用
  static const Distance _distanceCalc = Distance(roundResult: false);

  // 過去の散歩記録(起動時に永続ストレージから読み込む)
  final List<WalkTrack> _savedTracks = [];

  // 再生モード関連
  GhostTrack? _ghost;
  Timer? _ghostTimer;
  DateTime? _ghostStartedAt;
  LatLng? _ghostPosition;

  // 写真ピン(撮影した位置に表示)
  final List<PhotoPin> _photoPins = [];

  // 歴代の対戦で撮った自分の写真（capturedMode = 'battle'）。
  // 「撮影した写真」一覧には常に表示し、地図上のピン表示は
  // _showBattlePhotoPins で切り替える。
  final List<PhotoPin> _battlePhotoPins = [];

  // 対戦写真をマップモードの地図にピン表示するか（永続化される）
  bool _showBattlePhotoPins = true;

  // ── マップモード ──
  // これまで歩いて霧を晴らした地点（再起動後も保持）
  final List<LatLng> _mapClearedPoints = [];
  // マップモードで霧を晴らす半径（メートル）
  // 中心から _mapFullClearRadius までは完全に晴れ、そこから
  // _mapClearRadius にかけてグラデーションで霧に戻る。
  static const double _mapClearRadius = 30.0;
  static const double _mapFullClearRadius = 20.0;

  /// 直近の build 時の画面幅（論理ピクセル）。既定ズームの計算に使う。
  /// build より前に地図を動かす経路があるため、初期値を持たせておく。
  double _viewWidthPx = 400;

  /// 地図の現在のズーム値。写真ピンの表示数・大きさの制御に使う。
  /// 初期値は既定ズーム相当（build 前に参照されても破綻しないように）。
  double _currentZoom = 15.0;

  /// 地図の回転角（度）。コンパスの針と現在地ビームの向きに使う。
  double _mapRotation = 0;

  /// 端末が向いている方位（度・真北が 0）。null は向き不明。
  double? _heading;
  StreamSubscription<double?>? _headingSub;

  /// 画面の端から端までが約 1.5km になるズームレベル。
  double get _defaultZoom => MapZoom.forSpan(
    widthPx: _viewWidthPx,
    latitude: _currentPosition.latitude,
    spanMeters: kDefaultMapSpanMeters,
  );

  /// 写真の場所へ飛ぶときのズーム。既定の縮尺と揃えてあるので、
  /// 縮尺は変わらず位置だけが動いたように見える。
  double get _closeUpZoom => _defaultZoom;

  // 歴代の対戦で通った点（軌跡＋写真位置）。
  // ON/OFF 設定は廃止し、常に霧晴らしへ反映する。
  final List<LatLng> _battleFogPoints = [];

  bool get _isRecording => _currentTrack != null && _currentTrack!.isActive;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadSavedTracks();
    _loadPhotoPins();
    _loadMapFog();
    _loadBattleFogPoints();
    _loadBattlePinSetting();
    // マップモードでは起動直後から現在地をリアルタイム更新する。
    _ensureLocationStream();
    // 端末の向き（磁気コンパス）。センサーが無い端末では何も流れない。
    _headingSub = CompassService.heading().listen((h) {
      if (!mounted || h == null) return;
      setState(() => _heading = h);
    });
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _positionSub?.cancel();
    _elapsedTimer?.cancel();
    _ghostTimer?.cancel();
    _stepSub?.cancel();
    _stepCounter.dispose();
    super.dispose();
  }

  /// 位置情報の継続ストリームを、必要なとき（コラージュ表示中 or 記録中）だけ動かす。
  /// これによりコラージュモード中は記録していなくても現在地マーカーが
  /// リアルタイムに更新される（対戦画面と同じ挙動）。
  void _ensureLocationStream() {
    final shouldRun = _mode == MapMode.map || _isRecording;
    if (shouldRun && _positionSub == null) {
      _positionSub = LocationService.watchPositionRaw().listen(
        _onPositionUpdate,
      );
    } else if (!shouldRun && _positionSub != null) {
      _positionSub!.cancel();
      _positionSub = null;
    }
  }

  /// 位置更新の共通処理。常に現在地を更新し、記録中は軌跡・距離・速度も更新する。
  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    final newPos = LatLng(position.latitude, position.longitude);
    setState(() {
      if (_isRecording) {
        final track = _currentTrack!;
        if (track.points.isNotEmpty) {
          _distanceMeters += _distanceCalc(track.points.last.position, newPos);
        }
        _speedKmh = position.speed > 0 ? position.speed * 3.6 : 0;
        _currentTrack = track.copyWith(
          points: [
            ...track.points,
            TrackPoint(position: newPos, timestamp: DateTime.now()),
          ],
        );
      }
      // マップモードで散歩中なら、通過した地点の霧を晴らす。
      if (_mode == MapMode.map && _isRecording) {
        _mapClearedPoints.add(newPos);
      }
      _currentPosition = newPos;
      _hasLocation = true;
    });
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
      });
      _mapController.move(_currentPosition, _defaultZoom);
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
    await _loadBattlePhotoPins();
  }

  /// 歴代の対戦写真を読み込む（写真一覧に表示するため）。
  /// 実ファイルが存在しないものは除外する。
  Future<void> _loadBattlePhotoPins() async {
    try {
      final pins = await BattlePhotoHistoryService.loadAll();
      final alive = <PhotoPin>[];
      for (final p in pins) {
        if (p.imagePath.isEmpty) continue;
        if (await File(p.imagePath).exists()) alive.add(p);
      }
      if (!mounted) return;
      setState(() {
        _battlePhotoPins
          ..clear()
          ..addAll(alive);
      });
      await _ensureBattlePhotoColors();
    } catch (_) {}
  }

  /// 対戦写真に 24 色パレットの主要色を持たせる。
  ///
  /// 対戦モードは専用パレットで色判定するため、フォトモードの色グループには
  /// そのままでは載らない。色が未設定のものだけ抽出し、履歴へ書き戻して
  /// 次回以降は再計算しないようにする。
  Future<void> _ensureBattlePhotoColors() async {
    final targets = _battlePhotoPins.where((p) => p.colorIds.isEmpty).toList();
    if (targets.isEmpty) return;

    final computed = <String, List<int>>{};
    for (final pin in targets) {
      try {
        final ids = await extractColorIdsFromPath(pin.imagePath);
        if (ids.isNotEmpty) computed[pin.id] = ids;
      } catch (_) {}
    }
    if (computed.isEmpty) return;

    await BattlePhotoHistoryService.saveColorIds(computed);
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _battlePhotoPins.length; i++) {
        final ids = computed[_battlePhotoPins[i].id];
        if (ids == null) continue;
        final p = _battlePhotoPins[i];
        _battlePhotoPins[i] = PhotoPin(
          id: p.id,
          imagePath: p.imagePath,
          position: p.position,
          takenAt: p.takenAt,
          colorIds: ids,
          capturedMode: 'battle',
        );
      }
    });
  }

  /// 対戦写真のピン表示設定を読み込む。
  Future<void> _loadBattlePinSetting() async {
    final show = await PhotoDisplaySettingsService.loadShowBattlePhotoPins();
    if (!mounted) return;
    setState(() => _showBattlePhotoPins = show);
  }

  /// 対戦写真のピン表示を切り替えて永続化する。
  Future<void> _toggleBattlePhotoPins() async {
    final next = !_showBattlePhotoPins;
    setState(() => _showBattlePhotoPins = next);
    await PhotoDisplaySettingsService.saveShowBattlePhotoPins(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(next ? '対戦の写真を地図に表示します' : '対戦の写真を地図から隠しました'),
      ),
    );
  }

  /// 地図にピン表示する写真（マップ／コラージュ ＋ 設定 ON なら対戦写真）。
  List<PhotoPin> get _pinsOnMap => [
    ..._photoPins,
    if (_showBattlePhotoPins) ..._battlePhotoPins,
  ];

  /// 現在のズームでの写真ピンの上限枚数。
  /// 縮小するほど枚数を絞り、地図がサムネイルで埋まらないようにする。
  int get _photoPinLimit {
    if (_currentZoom < 14.0) return 0; // 広域（約 3km 超）: 非表示
    if (_currentZoom < 15.0) return 12;
    if (_currentZoom < 16.0) return 40;
    return _pinsOnMap.length; // 既定〜拡大: 全件
  }

  /// 現在のズームでの写真ピンの直径。
  double get _photoPinSize {
    if (_currentZoom < 14.0) return 24;
    if (_currentZoom < 15.0) return 28;
    if (_currentZoom < 16.0) return 34;
    return 44;
  }

  /// 実際に地図へ描くピン。上限に達している場合は新しい写真を優先する。
  List<PhotoPin> get _visiblePhotoPins {
    final limit = _photoPinLimit;
    if (limit <= 0) return const [];
    final all = _pinsOnMap;
    if (all.length <= limit) return all;
    final sorted = List<PhotoPin>.of(all)
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return sorted.take(limit).toList();
  }

  /// 「撮影した写真」一覧に出すピン（散歩・コラージュ ＋ 歴代の対戦）。
  /// 撮影日時の新しい順に並べる。
  List<PhotoPin> get _allPhotoPinsForList {
    final ids = _photoPins.map((p) => p.id).toSet();
    final merged = <PhotoPin>[
      ..._photoPins,
      ..._battlePhotoPins.where((p) => !ids.contains(p.id)),
    ];
    merged.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return merged;
  }

  /// 一覧からの削除。散歩側と対戦履歴側の両方へ振り分ける。
  /// 画像の実ファイルも削除する（対戦履歴分はサービス側が削除する）。
  void _deletePinsFromList(Set<String> ids) {
    final battleIds = _battlePhotoPins
        .where((p) => ids.contains(p.id))
        .map((p) => p.id)
        .toSet();
    // 散歩／コラージュ側の実ファイルを削除する。
    final filesToDelete = _photoPins
        .where((p) => ids.contains(p.id) && p.imagePath.isNotEmpty)
        .map((p) => p.imagePath)
        .toList();

    setState(() {
      _photoPins.removeWhere((p) => ids.contains(p.id));
      _battlePhotoPins.removeWhere((p) => ids.contains(p.id));
    });
    _savePhotoPins();
    _deleteFiles(filesToDelete);
    if (battleIds.isNotEmpty) {
      BattlePhotoHistoryService.deleteByIds(battleIds);
    }
  }

  Future<void> _deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _loadMapFog() async {
    final pts = await MapFogStorageService.loadAll();
    if (!mounted) return;
    setState(() {
      _mapClearedPoints
        ..clear()
        ..addAll(pts);
    });
  }

  /// 歴代の対戦で通った点（軌跡＋写真位置）を読み込む。
  /// ON/OFF 設定は廃止し、常に霧晴らしへ反映する。
  Future<void> _loadBattleFogPoints() async {
    final points = await BattlePhotoHistoryService.loadFogPoints();
    if (!mounted) return;
    setState(() {
      _battleFogPoints
        ..clear()
        ..addAll(points);
    });
  }

  /// マップモードで霧を晴らす点の一覧。
  /// 自分の散歩軌跡に加え、歴代の対戦の軌跡・写真位置も常に含める。
  List<LatLng> get _mapFogPoints => [..._mapClearedPoints, ..._battleFogPoints];

  /// マップモードの「散歩を記録する」。範囲ダイアログは出さず、すぐに記録
  /// （＝霧晴らし）を開始する。
  void _startMapWalk() {
    _startRecording();
    if (_hasLocation) {
      setState(() => _mapClearedPoints.add(_currentPosition));
    }
  }

  Future<void> _savePhotoPins() async {
    try {
      await PhotoPinStorageService.saveAll(_photoPins);
    } catch (_) {}
  }

  /// 地図上のピンからの削除。対戦写真のピンも消せるよう、
  /// 一覧と同じ振り分け処理（実ファイル削除・履歴更新）へ委譲する。
  void _deletePhotoPin(PhotoPin pin) => _deletePinsFromList({pin.id});

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
      _distanceMeters = 0;
      _speedKmh = 0;
      _stepCount = 0;
    });

    // 歩数カウント開始（加速度センサー）
    _stepCounter.reset();
    _stepCounter.start();
    _stepSub = _stepCounter.stepStream.listen((steps) {
      if (!mounted) return;
      setState(() => _stepCount = steps);
    });

    // 位置情報の継続取得（コラージュ表示中は既に動いているが、念のため保証）
    _ensureLocationStream();

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
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _stepSub?.cancel();
    _stepSub = null;
    _stepCounter.stop();

    final count = _currentTrack?.points.length ?? 0;
    final finished = _currentTrack?.copyWith(
      endedAt: DateTime.now(),
      stepCount: _stepCount,
    );
    setState(() {
      _currentTrack = finished;
      if (finished != null && finished.points.isNotEmpty) {
        _savedTracks.add(finished);
      }
    });

    // 記録停止後もコラージュ／マップモードなら現在地更新は継続させる。
    _ensureLocationStream();

    // マップモードで晴らした地点を永続化する（再起動後も保持）。
    if (_mode == MapMode.map) {
      MapFogStorageService.saveAll(_mapClearedPoints);
    }

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
  /// 左端スワイプで対戦フローを全画面オーバーレイとして開く。
  /// 閉じたあとは、対戦中に晴らした霧・撮った写真をマップへ反映し直す。
  Future<void> _openBattleOverlay() async {
    await BattleOverlay.open(context);
    if (!mounted) return;
    await _loadMapFog();
    await _loadBattleFogPoints();
    await _loadBattlePhotoPins();
  }

  void _onModeChanged(MapMode mode) {
    setState(() => _mode = mode);
    if (mode == MapMode.animation) {
      _startGhostPlayback();
    } else {
      _stopGhostPlayback();
    }
    // マップモードに入るたびに、歴代の対戦データ（軌跡・写真位置）を読み直して
    // 直近の対戦分まで霧晴らしに反映されるようにする。
    if (mode == MapMode.map) {
      _loadBattleFogPoints();
    }
    // 対戦中に撮った写真を一覧へ反映し直す。
    _loadBattlePhotoPins();
    // コラージュモードに入ったら現在地更新を開始、離れたら（記録中でなければ）停止。
    _ensureLocationStream();
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
            capturedDuringWalk: _isRecording,
            capturedMode: 'map',
          ),
        );
      });

      _savePhotoPins();

      final colorLabel = colorIds.isEmpty
          ? '色を検出できませんでした'
          : colorIds.map((id) => colorNames24[id]).join(' / ');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写真を保存しました　[$colorLabel]')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撮影に失敗: $e')));
    }
  }

  /// 現在地ボタン。位置・縮尺に加えて、地図の回転も北向きへ戻す。
  void _backToCurrentLocation() {
    _mapController.moveAndRotate(_currentPosition, _defaultZoom, 0);
    setState(() => _mapRotation = 0);
  }

  /// コンパスのタップ。向きだけ北へ戻す（位置と縮尺はそのまま）。
  void _resetRotation() {
    _mapController.rotate(0);
    setState(() => _mapRotation = 0);
  }

  /// 写真一覧の「この場所に移動」から呼ばれる。
  /// 一覧を閉じ、マップモードに戻してから、その写真の座標へ地図を動かす。
  void _moveToPin(PhotoPin pin) {
    Navigator.of(context).pop(); // 写真一覧を閉じる
    setState(() {
      if (_mode != MapMode.map) _mode = MapMode.map;
    });
    _ensureLocationStream();
    // 画面が地図に切り替わってから動かす（切替前だと MapController が未接続）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(pin.position, _closeUpZoom);
    });
  }

  void _openPhotoList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoListScreen(
          // 対戦中に撮った写真も一覧に含める（対戦終了後も残る）。
          photoPins: _allPhotoPinsForList,
          onDeletePins: _deletePinsFromList,
          onMoveToPin: _moveToPin,
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

  // ─── 再生モード時の「記録の統計」パネル ───
  // 再生中の軌跡の合計距離・所要時間・歩数を表示する。
  Widget _buildPlaybackStats() {
    final track = _ghost?.track;
    if (track == null) return const SizedBox.shrink();

    final distance = track.totalDistanceMeters;
    final distanceText = distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(2)}km'
        : '${distance.toStringAsFixed(0)}m';

    final d = track.duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final durationText = h > 0 ? '$h:$m:$s' : '$m:$s';

    Widget item(IconData icon, String value, String label, Color color) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              item(
                Icons.straighten_rounded,
                distanceText,
                '距離',
                const Color(0xFF185FA5),
              ),
              item(
                Icons.timer_outlined,
                durationText,
                '時間',
                const Color(0xFF2E7D32),
              ),
              item(
                Icons.directions_walk_rounded,
                '${track.stepCount}歩',
                '歩数',
                const Color(0xFF854F0B),
              ),
            ],
          ),
        ),
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
    // 既定ズーム計算のため、現在の画面幅を控えておく。
    _viewWidthPx = MediaQuery.of(context).size.width;

    // 縮小時は写真ピンを減らし、拡大すると段階的に増やす。
    final visiblePhotoPins = _visiblePhotoPins;
    final photoPinSize = _photoPinSize;

    // 再生モード時にゴーストが辿っている軌跡の全座標
    final ghostFullPath = _mode == MapMode.animation && _ghost != null
        ? _ghost!.track.points.map((p) => p.position).toList()
        : const <LatLng>[];

    // ── フォトモード:地図なし。撮影写真を色ごとに並べてコラージュを作る ──
    if (_mode == MapMode.photo) {
      return PhotoModeScreen(
        // 対戦中に撮った写真もコラージュの素材として扱う。
        photoPins: _allPhotoPinsForList,
        onDeletePins: _deletePinsFromList,
        modeBar: ModeSwitcher(
          currentMode: _mode,
          onModeChanged: _onModeChanged,
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
              // 画面の端から端までが実空間で約 3km になる倍率
              initialZoom: _defaultZoom,
              minZoom: 3.0,
              maxZoom: 19.0,
              // ズームが変わったら写真ピンの表示数・大きさを見直す。
              // 微小な変化では再描画しない（0.05 未満は無視）。
              onPositionChanged: (camera, hasGesture) {
                final zoomChanged =
                    (camera.zoom - _currentZoom).abs() >= 0.05;
                final rotationChanged =
                    (camera.rotation - _mapRotation).abs() >= 0.5;
                if (!zoomChanged && !rotationChanged) return;
                setState(() {
                  _currentZoom = camera.zoom;
                  _mapRotation = camera.rotation;
                });
              },
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
              // マップモード: 歩いて通った場所だけ晴れる霧
              // （色クラスタ／領域は作らず、純粋に通過地点の周辺を晴らす）
              if (_mode == MapMode.map)
                PathFogOverlay(
                  clearedPoints: _mapFogPoints,
                  clearRadiusMeters: _mapClearRadius,
                  fullClearRadiusMeters: _mapFullClearRadius,
                ),
              // （コラージュ／マップモードでは、散歩記録中の軌跡は表示しない）
              // 写真ピン（「マップ」「コラージュ」で撮った写真。
              //  対戦で撮った写真は右下のトグルで表示/非表示を切り替える）
              if (visiblePhotoPins.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final pin in visiblePhotoPins)
                      Marker(
                        point: pin.position,
                        width: photoPinSize,
                        height: photoPinSize,
                        child: GestureDetector(
                          onTap: () => PhotoDetailSheet.show(
                            context,
                            pin,
                            onDelete: () => _deletePhotoPin(pin),
                          ),
                          child: PhotoPinMarker(
                            imagePath: pin.imagePath,
                            size: photoPinSize,
                          ),
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
                      // ビームが丸からはみ出すぶん、マーカーを大きめに取る。
                      // （ここを 13x13 にするとビームも 13px に潰れる）
                      width: 46,
                      height: 46,
                      child: CurrentLocationMarker(
                        headingDegrees: _heading,
                        mapRotationDegrees: _mapRotation,
                        dotSize: 13,
                      ),
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

          // ── 左端スワイプ:対戦モードを全画面オーバーレイで開く ──
          //   マップモードのときのみ有効。散歩の記録中は誤操作防止で無効。
          EdgeSwipeDetector(
            fromLeft: true,
            enabled: _mode == MapMode.map && !_isRecording,
            onSwipe: _openBattleOverlay,
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

          // ── 右上:コンパス（タップで北向きに戻す）──
          //   モード切替バーの下に来るよう、上部に余白を取る。
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 72, right: 12),
                child: MapCompass(
                  rotationDegrees: _mapRotation,
                  onTap: _resetRotation,
                ),
              ),
            ),
          ),

          // ── 下部:記録コントロール(マップタブ時) ──
          if (_mode == MapMode.map)
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
                    distanceMeters: _distanceMeters,
                    speedKmh: _speedKmh,
                    stepCount: _stepCount,
                    startLabel: '散歩を記録する',
                    onStart: () async => _startMapWalk(),
                    onStop: _stopRecording,
                  ),
                ),
              ),
            ),

          // ── 下部:再生統計 + 軌跡選択カード(再生モード時のみ) ──
          if (_mode == MapMode.animation)
            Positioned(
              left: 76,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPlaybackStats(),
                      _buildTrackPickerButton(),
                    ],
                  ),
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
          // 対戦写真のピン表示 ON/OFF（マップモード限定）
          if (_mode == MapMode.map)
            FloatingActionButton.small(
              onPressed: _toggleBattlePhotoPins,
              heroTag: 'battle_pin_toggle',
              tooltip: _showBattlePhotoPins ? '対戦の写真を地図から隠す' : '対戦の写真を地図に表示する',
              backgroundColor: _showBattlePhotoPins
                  ? const Color(0xFFC62828)
                  : Colors.white,
              child: CrossedSwordsIcon(
                size: 20,
                color: _showBattlePhotoPins ? Colors.white : Colors.black54,
              ),
            ),
          if (_mode == MapMode.map) const SizedBox(height: 8),
          // 現在地に戻る
          FloatingActionButton.small(
            onPressed: _hasLocation
                ? _backToCurrentLocation
                : null,
            heroTag: 'recenter',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
