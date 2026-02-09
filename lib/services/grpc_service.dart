import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart';

/// Describes a single logged gRPC message.
class ProtocolLogEntry {
  final DateTime time;
  final String direction; // '→' outgoing, '←' incoming
  final String method;
  final String summary;
  ProtocolLogEntry(this.time, this.direction, this.method, this.summary);
}

/// Central gRPC connection manager for the robot.
class GrpcService extends ChangeNotifier {
  ClientChannel? _channel;
  CmsClient? _client;

  String _host = '192.168.123.15';
  int _port = 13145;
  bool _connected = false;
  String? _error;

  /// Callback for UI-level error notifications.
  void Function(String message)? onErrorNotify;

  // Real-time data
  History? _latestHistory;
  Imu? _latestImu;
  AllJoints? _latestJoints;
  Params? _params;
  String _cmsState = 'Unknown';

  // Streams
  StreamSubscription? _historySub;
  StreamSubscription? _imuSub;
  StreamSubscription? _jointSub;

  // Protocol log
  final List<ProtocolLogEntry> protocolLog = [];
  static const int _maxLogEntries = 500;

  // Torque history (4 legs x 50 points)
  static const int _maxTorqueHist = 50;
  final List<List<double>> torqueHistory = List.generate(4, (_) => []);

  // Frequency tracking
  int _historyCount = 0;
  int _imuCount = 0;
  int _jointCount = 0;
  DateTime? _freqStart;
  double historyHz = 0;
  double imuHz = 0;
  double jointHz = 0;

  // Uptime
  DateTime? _serverStartTime;
  DateTime? _connectTime;

  // Getters
  String get host => _host;
  int get port => _port;
  bool get connected => _connected;
  String? get error => _error;
  History? get latestHistory => _latestHistory;
  Imu? get latestImu => _latestImu;
  AllJoints? get latestJoints => _latestJoints;
  Params? get params => _params;
  String get cmsState => _cmsState;
  CmsClient? get client => _client;
  DateTime? get serverStartTime => _serverStartTime;
  DateTime? get connectTime => _connectTime;
  int get uptimeSeconds => _connectTime != null ? DateTime.now().difference(_connectTime!).inSeconds : 0;

  void _log(String direction, String method, [String summary = '']) {
    protocolLog.insert(0, ProtocolLogEntry(DateTime.now(), direction, method, summary));
    if (protocolLog.length > _maxLogEntries) {
      protocolLog.removeLast();
    }
  }

  void _updateFrequency() {
    final now = DateTime.now();
    if (_freqStart == null) {
      _freqStart = now;
      return;
    }
    final elapsed = now.difference(_freqStart!).inMilliseconds / 1000.0;
    if (elapsed >= 1.0) {
      historyHz = _historyCount / elapsed;
      imuHz = _imuCount / elapsed;
      jointHz = _jointCount / elapsed;
      _historyCount = 0;
      _imuCount = 0;
      _jointCount = 0;
      _freqStart = now;
    }
  }

  Future<void> connect(String host, int port) async {
    disconnect();
    _host = host;
    _port = port;
    _error = null;

    try {
      _channel = ClientChannel(
        host,
        port: port,
        options: ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
      _client = CmsClient(_channel!);

      // Test connection by getting start time
      _log('→', 'GetStartTime');
      final ts = await _client!.getStartTime(Empty());
      _serverStartTime = DateTime.fromMillisecondsSinceEpoch(ts.seconds.toInt() * 1000);
      _connectTime = DateTime.now();
      _log('←', 'GetStartTime', 'OK');

      _connected = true;
      notifyListeners();

      // Fetch params
      _fetchParams();

      // Start streaming
      _startStreams();
    } catch (e) {
      _error = e.toString();
      _connected = false;
      _log('✕', 'Connect', _error!);
      onErrorNotify?.call('连接失败: $_error');
      notifyListeners();
    }
  }

  void disconnect() {
    _historySub?.cancel();
    _imuSub?.cancel();
    _jointSub?.cancel();
    _historySub = null;
    _imuSub = null;
    _jointSub = null;
    _channel?.shutdown();
    _channel = null;
    _client = null;
    _connected = false;
    _latestHistory = null;
    _latestImu = null;
    _latestJoints = null;
    _freqStart = null;
    _serverStartTime = null;
    _connectTime = null;
    historyHz = 0;
    imuHz = 0;
    jointHz = 0;
    notifyListeners();
  }

  Future<void> _fetchParams() async {
    if (_client == null) return;
    try {
      _log('→', 'GetParams');
      _params = await _client!.getParams(Empty());
      _log('←', 'GetParams', 'robot: ${_params?.robot.type}');
      notifyListeners();
    } catch (e) {
      _log('✕', 'GetParams', e.toString());
    }
  }

  void _startStreams() {
    if (_client == null) return;

    // History stream
    _historySub = _client!.listenHistory(Empty()).listen(
      (history) {
        _latestHistory = history;
        _historyCount++;
        _updateCmsState(history.command);
        _updateFrequency();
        notifyListeners();
      },
      onError: (e) {
        _log('✕', 'ListenHistory', e.toString());
        onErrorNotify?.call('History 流异常: $e');
      },
    );

    // IMU stream
    _imuSub = _client!.listenImu(Empty()).listen(
      (imu) {
        _latestImu = imu;
        _imuCount++;
        _updateFrequency();
        notifyListeners();
      },
      onError: (e) {
        _log('✕', 'ListenImu', e.toString());
        onErrorNotify?.call('IMU 流异常: $e');
      },
    );

    // Joint stream
    _jointSub = _client!.listenJoint(Empty()).listen(
      (joint) {
        if (joint.hasAllJoints()) {
          _latestJoints = joint.allJoints;
          _updateTorqueHistory(joint.allJoints);
        }
        _jointCount++;
        _updateFrequency();
        notifyListeners();
      },
      onError: (e) {
        _log('✕', 'ListenJoint', e.toString());
        onErrorNotify?.call('Joint 流异常: $e');
      },
    );
  }

  void _updateTorqueHistory(AllJoints joints) {
    if (joints.torque.values.length < 12) return;
    for (int leg = 0; leg < 4; leg++) {
      final base = leg * 3;
      final avg = (joints.torque.values[base].abs() + joints.torque.values[base + 1].abs() + joints.torque.values[base + 2].abs()) / 3;
      torqueHistory[leg].add(avg);
      if (torqueHistory[leg].length > _maxTorqueHist) torqueHistory[leg].removeAt(0);
    }
  }

  void _updateCmsState(Command cmd) {
    switch (cmd.whichData()) {
      case Command_Data.idle:
        _cmsState = 'Idle';
      case Command_Data.standUp:
        _cmsState = 'StandUp';
      case Command_Data.sitDown:
        _cmsState = 'SitDown';
      case Command_Data.walk:
        _cmsState = 'Walking';
      case Command_Data.notSet:
        break;
    }
  }

  // --- Commands ---
  Future<void> enable() async {
    if (_client == null) return;
    try {
      _log('→', 'Enable');
      await _client!.enable(Empty());
      _log('←', 'Enable', 'OK');
    } catch (e) {
      _log('✕', 'Enable', e.toString());
    }
  }

  Future<void> disable() async {
    if (_client == null) return;
    try {
      _log('→', 'Disable');
      await _client!.disable(Empty());
      _log('←', 'Disable', 'OK');
    } catch (e) {
      _log('✕', 'Disable', e.toString());
    }
  }

  Future<void> standUp() async {
    if (_client == null) return;
    try {
      _log('→', 'StandUp');
      await _client!.standUp(Empty());
      _log('←', 'StandUp', 'OK');
    } catch (e) {
      _log('✕', 'StandUp', e.toString());
    }
  }

  Future<void> sitDown() async {
    if (_client == null) return;
    try {
      _log('→', 'SitDown');
      await _client!.sitDown(Empty());
      _log('←', 'SitDown', 'OK');
    } catch (e) {
      _log('✕', 'SitDown', e.toString());
    }
  }

  Future<void> walk(double x, double y, double z) async {
    if (_client == null) return;
    try {
      final v = Vector3(x: x, y: y, z: z);
      await _client!.walk(v);
    } catch (_) {}
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
