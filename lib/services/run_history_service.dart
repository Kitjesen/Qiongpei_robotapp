import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// A single run history entry.
class RunEntry {
  final DateTime connectedAt;
  DateTime? disconnectedAt;
  final String host;
  final int port;
  String? presetName;

  RunEntry({required this.connectedAt, this.disconnectedAt, required this.host, required this.port, this.presetName});

  Duration get duration => (disconnectedAt ?? DateTime.now()).difference(connectedAt);

  String get durationLabel {
    final d = duration;
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  Map<String, dynamic> toJson() => {
    'connectedAt': connectedAt.toIso8601String(),
    'disconnectedAt': disconnectedAt?.toIso8601String(),
    'host': host,
    'port': port,
    'presetName': presetName,
  };

  factory RunEntry.fromJson(Map<String, dynamic> json) => RunEntry(
    connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ?? DateTime.now(),
    disconnectedAt: json['disconnectedAt'] != null ? DateTime.tryParse(json['disconnectedAt'] as String) : null,
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    presetName: json['presetName'] as String?,
  );
}

/// Manages robot run history (connection sessions).
class RunHistoryService {
  late final File _file;
  final List<RunEntry> entries = [];
  RunEntry? _current;

  Future<void> init() async {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.';
    final dir = Directory(p.join(appData, 'qiongpei_app'));
    await dir.create(recursive: true);
    _file = File(p.join(dir.path, 'run_history.json'));
    await _load();
  }

  Future<void> _load() async {
    entries.clear();
    if (await _file.exists()) {
      try {
        final list = jsonDecode(await _file.readAsString()) as List;
        entries.addAll(list.map((e) => RunEntry.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    // Keep max 100
    while (entries.length > 100) entries.removeLast();
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(entries.map((e) => e.toJson()).toList()));
  }

  /// Call when robot connects.
  void onConnect(String host, int port, {String? presetName}) {
    _current = RunEntry(connectedAt: DateTime.now(), host: host, port: port, presetName: presetName);
    entries.insert(0, _current!);
    _save();
  }

  /// Call when robot disconnects.
  void onDisconnect() {
    if (_current != null) {
      _current!.disconnectedAt = DateTime.now();
      _current = null;
      _save();
    }
  }

  /// Clear all history.
  Future<void> clear() async {
    entries.clear();
    await _save();
  }
}
