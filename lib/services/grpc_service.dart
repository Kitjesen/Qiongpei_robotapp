import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration;

/// Describes a single logged gRPC message.
class ProtocolLogEntry {
  final DateTime time;
  final String direction; // '→' outgoing, '←' incoming
  final String method;
  final String summary;
  ProtocolLogEntry(this.time, this.direction, this.method, this.summary);
}

/// Central gRPC connection manager for the robot.
///
/// Communicates with the han_dog RealDogServer (or SimDogServer) via gRPC.
/// The real server sends individual [SingleJoint] updates per motor;
/// this service aggregates them into a complete [AllJoints] snapshot for the UI.
///
/// Features:
/// - gRPC keepalive for LAN reliability
/// - Auto-reconnect with exponential backoff on stream failures
/// - Connection health monitoring (stale detection, reconnect state)
/// - Proper gRPC error code handling
class GrpcService extends ChangeNotifier {
  ClientChannel? _channel;
  CmsClient? _client;

  String _host = '192.168.66.192';
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

  // Joint aggregation from SingleJoint messages
  // The real server sends individual motor reports; we accumulate them here.
  final List<double> _jointPositions = List.filled(16, 0.0);
  final List<double> _jointVelocities = List.filled(16, 0.0);
  final List<double> _jointTorques = List.filled(16, 0.0);
  final List<int> _jointStatuses = List.filled(16, 0);
  DateTime? _lastJointNotify;
  static const _jointThrottleMs = 20; // 50Hz max UI update rate for joints

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

  // ── Connection health monitoring ──
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  DateTime? _lastDataTime;
  Timer? _healthTimer;
  bool _stale = false;
  static const _staleThresholdMs = 5000; // 5 seconds without data → stale

  // ── Auto-reconnect ──
  static const _maxBackoffMs = 30000; // 30 seconds max backoff
  static const _initialBackoffMs = 1000; // 1 second initial backoff
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;

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

  // Health getters
  bool get isReconnecting => _reconnecting;
  int get reconnectAttempts => _reconnectAttempts;
  DateTime? get lastDataTime => _lastDataTime;
  bool get isStale => _stale;

  /// Overall health status string for the UI.
  String get healthStatus {
    if (!_connected && !_reconnecting) return 'Disconnected';
    if (_reconnecting) return 'Reconnecting (#$_reconnectAttempts)...';
    if (_stale) return 'No Data';
    return 'Healthy';
  }

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

  /// Mark that data was received — used by health monitoring.
  void _touchData() {
    _lastDataTime = DateTime.now();
    if (_stale) {
      _stale = false;
      // Stale flag cleared — will notify via the next data callback
    }
  }

  /// Start periodic health check timer.
  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_connected) return;
      final now = DateTime.now();
      if (_lastDataTime != null &&
          now.difference(_lastDataTime!).inMilliseconds > _staleThresholdMs) {
        if (!_stale) {
          _stale = true;
          _log('⚠', 'Health', 'No data received for >5s — connection may be stale');
          notifyListeners();
        }
      }
    });
  }

  Future<void> connect(String host, int port) async {
    _intentionalDisconnect = false;
    disconnect();
    _intentionalDisconnect = false; // reset after disconnect sets it
    _host = host;
    _port = port;
    _error = null;

    try {
      _channel = ClientChannel(
        host,
        port: port,
        options: ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          connectTimeout: const Duration(seconds: 10),
          idleTimeout: const Duration(minutes: 5),
          // gRPC keepalive for LAN reliability
          keepAlive: const ClientKeepAliveOptions(
            pingInterval: Duration(seconds: 10),
            timeout: Duration(seconds: 5),
            permitWithoutCalls: true,
          ),
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
      _reconnecting = false;
      _reconnectAttempts = 0;
      _touchData();
      notifyListeners();

      // Start health monitoring
      _startHealthMonitor();

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
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
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
    _reconnecting = false;
    _reconnectAttempts = 0;
    _stale = false;
    _latestHistory = null;
    _latestImu = null;
    _latestJoints = null;
    _freqStart = null;
    _serverStartTime = null;
    _connectTime = null;
    _lastJointNotify = null;
    _lastDataTime = null;
    historyHz = 0;
    imuHz = 0;
    jointHz = 0;
    // Reset joint aggregation
    _jointPositions.fillRange(0, 16, 0.0);
    _jointVelocities.fillRange(0, 16, 0.0);
    _jointTorques.fillRange(0, 16, 0.0);
    _jointStatuses.fillRange(0, 16, 0);
    notifyListeners();
  }

  // ── Auto-Reconnect ──

  /// Attempt to reconnect after a stream failure.
  /// Uses exponential backoff: 1s, 2s, 4s, 8s, ... up to 30s.
  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnecting) return; // already scheduled

    _reconnecting = true;
    _reconnectAttempts++;

    // Exponential backoff with jitter
    final backoffMs = math.min(
      _initialBackoffMs * math.pow(2, _reconnectAttempts - 1).toInt(),
      _maxBackoffMs,
    );
    // Add ±20% jitter to avoid thundering herd
    final jitter = (backoffMs * 0.2 * (math.Random().nextDouble() * 2 - 1)).toInt();
    final delayMs = backoffMs + jitter;

    _log('⟳', 'Reconnect', 'attempt #$_reconnectAttempts in ${delayMs}ms');
    notifyListeners();

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _performReconnect();
    });
  }

  Future<void> _performReconnect() async {
    if (_intentionalDisconnect) return;

    _log('⟳', 'Reconnect', 'attempting reconnection...');

    // Clean up old resources without resetting reconnect state
    _historySub?.cancel();
    _imuSub?.cancel();
    _jointSub?.cancel();
    _historySub = null;
    _imuSub = null;
    _jointSub = null;
    _channel?.shutdown();
    _channel = null;
    _client = null;

    try {
      _channel = ClientChannel(
        _host,
        port: _port,
        options: ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          connectTimeout: const Duration(seconds: 10),
          idleTimeout: const Duration(minutes: 5),
          keepAlive: const ClientKeepAliveOptions(
            pingInterval: Duration(seconds: 10),
            timeout: Duration(seconds: 5),
            permitWithoutCalls: true,
          ),
        ),
      );
      _client = CmsClient(_channel!);

      // Verify connection
      final ts = await _client!.getStartTime(Empty());
      _serverStartTime = DateTime.fromMillisecondsSinceEpoch(ts.seconds.toInt() * 1000);

      _connected = true;
      _reconnecting = false;
      _reconnectAttempts = 0;
      _stale = false;
      _touchData();
      _log('✓', 'Reconnect', 'success');
      notifyListeners();

      // Restart streams
      _startStreams();
      _fetchParams();
    } catch (e) {
      _log('✕', 'Reconnect', 'failed: $e');
      _connected = false;
      // Schedule another attempt
      _reconnecting = false; // allow _scheduleReconnect to fire
      _scheduleReconnect();
    }
  }

  Future<void> _fetchParams() async {
    if (_client == null) return;
    try {
      _log('→', 'GetParams');
      _params = await _client!.getParams(Empty());
      final robotInfo = _params != null && _params!.hasRobot()
          ? 'robot: ${_params!.robot.type.name}'
          : 'robot: (empty)';
      _log('←', 'GetParams', robotInfo);
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
        _touchData();
        notifyListeners();
      },
      onError: (e) {
        _log('✕', 'ListenHistory', e.toString());
        _handleStreamError('History', e);
      },
      onDone: () {
        _log('⚠', 'ListenHistory', 'stream closed by server');
        _handleStreamDone('History');
      },
    );

    // IMU stream
    _imuSub = _client!.listenImu(Empty()).listen(
      (imu) {
        _latestImu = imu;
        _imuCount++;
        _updateFrequency();
        _touchData();
        notifyListeners();
      },
      onError: (e) {
        _log('✕', 'ListenImu', e.toString());
        _handleStreamError('IMU', e);
      },
      onDone: () {
        _log('⚠', 'ListenImu', 'stream closed by server');
        _handleStreamDone('IMU');
      },
    );

    // Joint stream — handles both SingleJoint and AllJoints
    // The real server (RealDogServer) sends individual SingleJoint per motor report.
    // The sim server (SimDogServer) may send AllJoints batches.
    _jointSub = _client!.listenJoint(Empty()).listen(
      (joint) {
        _jointCount++;
        _updateFrequency();
        _touchData();

        if (joint.hasSingleJoint()) {
          _handleSingleJoint(joint.singleJoint);
        } else if (joint.hasAllJoints()) {
          _handleAllJoints(joint.allJoints);
        }
      },
      onError: (e) {
        _log('✕', 'ListenJoint', e.toString());
        _handleStreamError('Joint', e);
      },
      onDone: () {
        _log('⚠', 'ListenJoint', 'stream closed by server');
        _handleStreamDone('Joint');
      },
    );
  }

  /// Handle stream error — trigger auto-reconnect if still supposed to be connected.
  void _handleStreamError(String streamName, dynamic error) {
    if (_intentionalDisconnect) return;
    onErrorNotify?.call('$streamName 流异常: $error');
    if (_connected) {
      _connected = false;
      _scheduleReconnect();
    }
  }

  /// Handle stream done (server closed) — trigger auto-reconnect.
  void _handleStreamDone(String streamName) {
    if (_intentionalDisconnect) return;
    if (_connected) {
      _connected = false;
      _scheduleReconnect();
    }
  }

  /// Handle individual motor report from real hardware.
  /// Aggregates into local arrays and periodically builds AllJoints for UI.
  void _handleSingleJoint(SingleJoint sj) {
    final id = sj.id;
    if (id >= 0 && id < 16) {
      _jointPositions[id] = sj.position;
      _jointVelocities[id] = sj.velocity;
      _jointTorques[id] = sj.torque;
      _jointStatuses[id] = sj.status;
    }

    // Throttle UI updates: build AllJoints and notify at most every _jointThrottleMs
    final now = DateTime.now();
    if (_lastJointNotify == null ||
        now.difference(_lastJointNotify!).inMilliseconds >= _jointThrottleMs) {
      _lastJointNotify = now;
      _rebuildAllJoints();
      _updateTorqueHistory(_latestJoints!);
      notifyListeners();
    }
  }

  /// Handle batched AllJoints from simulation server.
  void _handleAllJoints(AllJoints allJoints) {
    _latestJoints = allJoints;

    // Also sync local arrays for consistency
    for (int i = 0; i < 16 && i < allJoints.position.values.length; i++) {
      _jointPositions[i] = allJoints.position.values[i];
    }
    for (int i = 0; i < 16 && i < allJoints.velocity.values.length; i++) {
      _jointVelocities[i] = allJoints.velocity.values[i];
    }
    for (int i = 0; i < 16 && i < allJoints.torque.values.length; i++) {
      _jointTorques[i] = allJoints.torque.values[i];
    }

    _updateTorqueHistory(allJoints);
    notifyListeners();
  }

  /// Build an AllJoints protobuf message from the aggregated local arrays.
  void _rebuildAllJoints() {
    _latestJoints = AllJoints(
      position: Matrix4(values: List<double>.from(_jointPositions)),
      velocity: Matrix4(values: List<double>.from(_jointVelocities)),
      torque: Matrix4(values: List<double>.from(_jointTorques)),
      status: Matrix4Int32(values: List<int>.from(_jointStatuses)),
    );
  }

  void _updateTorqueHistory(AllJoints joints) {
    if (joints.torque.values.length < 12) return;
    for (int leg = 0; leg < 4; leg++) {
      final base = leg * 3;
      final avg = (joints.torque.values[base].abs() +
              joints.torque.values[base + 1].abs() +
              joints.torque.values[base + 2].abs()) /
          3;
      torqueHistory[leg].add(avg);
      if (torqueHistory[leg].length > _maxTorqueHist) {
        torqueHistory[leg].removeAt(0);
      }
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
  // All motion commands use proper GrpcError.code checks instead of string matching.

  Future<void> enable() async {
    if (_client == null) return;
    try {
      _log('→', 'Enable');
      await _client!.enable(Empty());
      _log('←', 'Enable', 'OK');
    } catch (e) {
      _log('✕', 'Enable', e.toString());
      onErrorNotify?.call('Enable 失败: ${_formatGrpcError(e)}');
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
      onErrorNotify?.call('Disable 失败: ${_formatGrpcError(e)}');
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
      if (_isFailedPrecondition(e)) {
        onErrorNotify?.call('StandUp 被拒绝: 遥控器优先');
      } else {
        onErrorNotify?.call('StandUp 失败: ${_formatGrpcError(e)}');
      }
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
      if (_isFailedPrecondition(e)) {
        onErrorNotify?.call('SitDown 被拒绝: 遥控器优先');
      } else {
        onErrorNotify?.call('SitDown 失败: ${_formatGrpcError(e)}');
      }
    }
  }

  Future<void> walk(double x, double y, double z) async {
    if (_client == null) return;
    try {
      final v = Vector3(x: x, y: y, z: z);
      await _client!.walk(v);
    } catch (e) {
      // Walk commands are sent at high frequency; only log FAILED_PRECONDITION once
      if (_isFailedPrecondition(e)) {
        _log('✕', 'Walk', '被拒绝: 遥控器优先');
      }
    }
  }

  // ── gRPC error helpers ──

  /// Check if error is a gRPC FAILED_PRECONDITION (ControlArbiter rejection).
  bool _isFailedPrecondition(dynamic e) {
    if (e is GrpcError) {
      return e.code == StatusCode.failedPrecondition;
    }
    return false;
  }

  /// Format a gRPC error for display.
  String _formatGrpcError(dynamic e) {
    if (e is GrpcError) {
      return e.message ?? 'gRPC error (code ${e.code})';
    }
    return e.toString();
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _healthTimer?.cancel();
    disconnect();
    super.dispose();
  }
}
