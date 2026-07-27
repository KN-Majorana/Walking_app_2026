import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

/// 加速度センサーを使って歩数をカウントするサービス。
///
/// 実機のみ動作。エミュレーターでは常に0を返す。
class StepCounterService {
  StreamSubscription? _subscription;
  int _stepCount = 0;
  double _lastMagnitude = 0;
  bool _stepPending = false;
  DateTime? _lastStepTime;

  // 歩数を外部に通知するStreamController
  final _controller = StreamController<int>.broadcast();
  Stream<int> get stepStream => _controller.stream;
  int get stepCount => _stepCount;

  /// カウントを開始する
  void start() {
    _stepCount = 0;
    _lastMagnitude = 0;
    _stepPending = false;
    _lastStepTime = null;

    _subscription = accelerometerEventStream().listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      // 重力加速度（約9.8）を基準にした差分で歩行を検知
      final delta = magnitude - 9.8;

      // 閾値を超えたら「歩行の山」として検知
      if (delta > 2.5 && !_stepPending) {
        _stepPending = true;
      }

      // 山を過ぎて下がったら1歩カウント（連続カウントを防ぐため300ms制限）
      if (_stepPending && delta < 0.5) {
        final now = DateTime.now();
        if (_lastStepTime == null ||
            now.difference(_lastStepTime!) > const Duration(milliseconds: 300)) {
          _stepCount++;
          _lastStepTime = now;
          _controller.add(_stepCount);
        }
        _stepPending = false;
      }

      _lastMagnitude = magnitude;
    });
  }

  /// カウントを停止する
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// リセット
  void reset() {
    _stepCount = 0;
    _controller.add(0);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
