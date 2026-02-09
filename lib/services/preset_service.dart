import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/robot_config.dart';

/// A named preset with metadata.
class Preset {
  String name;
  DateTime createdAt;
  RobotConfig config;
  String filePath;

  Preset({required this.name, required this.createdAt, required this.config, required this.filePath});

  Map<String, dynamic> toJson() => {
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'config': config.toJson(),
  };

  factory Preset.fromJson(Map<String, dynamic> json, String filePath) => Preset(
    name: json['name'] as String? ?? 'Unnamed',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    config: RobotConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {}),
    filePath: filePath,
  );
}

/// A history entry (snapshot of a save action).
class HistoryEntry {
  final String presetName;
  final DateTime savedAt;
  final String filePath;

  HistoryEntry({required this.presetName, required this.savedAt, required this.filePath});
}

/// Manages presets and parameter history on disk.
class PresetService {
  late final Directory _presetsDir;
  late final Directory _historyDir;
  final List<Preset> presets = [];
  final List<HistoryEntry> history = [];

  /// Initialize directories and load existing presets/history.
  Future<void> init() async {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.';
    final base = Directory(p.join(appData, 'qiongpei_app'));
    _presetsDir = Directory(p.join(base.path, 'presets'));
    _historyDir = Directory(p.join(base.path, 'history'));
    await _presetsDir.create(recursive: true);
    await _historyDir.create(recursive: true);
    await _scanPresets();
    await _scanHistory();
  }

  // ── Presets CRUD ──

  Future<void> _scanPresets() async {
    presets.clear();
    final files = _presetsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    for (final file in files) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        presets.add(Preset.fromJson(json, file.path));
      } catch (_) {}
    }
    presets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Create a new preset from a config.
  Future<Preset> create(String name, RobotConfig config) async {
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(_presetsDir.path, '$safeName.json'));
    final preset = Preset(name: name, createdAt: DateTime.now(), config: config, filePath: file.path);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(preset.toJson()));
    presets.insert(0, preset);
    return preset;
  }

  /// Save (overwrite) an existing preset.
  Future<void> save(Preset preset) async {
    preset.createdAt = DateTime.now();
    final file = File(preset.filePath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(preset.toJson()));
  }

  /// Delete a preset.
  Future<void> delete(Preset preset) async {
    final file = File(preset.filePath);
    if (await file.exists()) await file.delete();
    presets.remove(preset);
  }

  /// Rename a preset.
  Future<void> rename(Preset preset, String newName) async {
    // Delete old file
    final oldFile = File(preset.filePath);
    if (await oldFile.exists()) await oldFile.delete();
    // Write new file
    final safeName = newName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final newFile = File(p.join(_presetsDir.path, '$safeName.json'));
    preset.name = newName;
    preset.filePath = newFile.path;
    await newFile.writeAsString(const JsonEncoder.withIndent('  ').convert(preset.toJson()));
  }

  // ── Parameter History ──

  /// Record a history snapshot.
  Future<void> recordHistory(String presetName, RobotConfig config) async {
    final now = DateTime.now();
    final ts = '${now.year}-${_p(now.month)}-${_p(now.day)}_${_p(now.hour)}-${_p(now.minute)}-${_p(now.second)}';
    final safeName = presetName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final fileName = '${ts}_$safeName.json';
    final file = File(p.join(_historyDir.path, fileName));
    final data = {'name': presetName, 'savedAt': now.toIso8601String(), 'config': config.toJson()};
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    history.insert(0, HistoryEntry(presetName: presetName, savedAt: now, filePath: file.path));
    // Keep max 50 entries
    while (history.length > 50) {
      final old = history.removeLast();
      try { await File(old.filePath).delete(); } catch (_) {}
    }
  }

  Future<void> _scanHistory() async {
    history.clear();
    final files = _historyDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // reverse chrono by filename
    for (final file in files.take(50)) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        history.add(HistoryEntry(
          presetName: json['name'] as String? ?? 'Unknown',
          savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
          filePath: file.path,
        ));
      } catch (_) {}
    }
  }

  /// Load a config from a history entry.
  Future<RobotConfig> loadHistory(HistoryEntry entry) async {
    final file = File(entry.filePath);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return RobotConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {});
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}
