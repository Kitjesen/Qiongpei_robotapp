import 'dart:io';
import 'package:path/path.dart' as p;

/// Info about a local .onnx model file.
class ModelInfo {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modified;

  ModelInfo({required this.name, required this.path, required this.sizeBytes, required this.modified});

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Manages local .onnx model repository and SCP upload to robot.
class ModelService {
  late final Directory _modelsDir;
  final List<ModelInfo> models = [];

  // SSH config (persisted in memory for session)
  String sshUser = 'pi';
  String sshRemotePath = '~/model/';

  Future<void> init() async {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.';
    _modelsDir = Directory(p.join(appData, 'qiongpei_app', 'models'));
    await _modelsDir.create(recursive: true);
    await scan();
  }

  /// Scan the local models directory.
  Future<void> scan() async {
    models.clear();
    final files = _modelsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.onnx'));
    for (final f in files) {
      final stat = await f.stat();
      models.add(ModelInfo(
        name: p.basename(f.path),
        path: f.path,
        sizeBytes: stat.size,
        modified: stat.modified,
      ));
    }
    models.sort((a, b) => b.modified.compareTo(a.modified));
  }

  /// Import a .onnx file from an external path into the local repository.
  Future<ModelInfo> importModel(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('源文件不存在: $sourcePath');
    final name = p.basename(sourcePath);
    final dest = File(p.join(_modelsDir.path, name));
    await src.copy(dest.path);
    await scan();
    return models.firstWhere((m) => m.name == name);
  }

  /// Delete a model from local repository.
  Future<void> delete(ModelInfo model) async {
    final f = File(model.path);
    if (await f.exists()) await f.delete();
    models.remove(model);
  }

  /// Upload a model to the robot via SCP.
  /// Returns the process result (stdout/stderr).
  Future<ProcessResult> uploadToRobot({
    required String modelPath,
    required String host,
    required String user,
    required String remotePath,
    String? password,
  }) async {
    final remoteTarget = '$user@$host:$remotePath';
    
    if (password != null && password.isNotEmpty) {
      // Use sshpass if available for password auth
      return Process.run('sshpass', ['-p', password, 'scp', '-o', 'StrictHostKeyChecking=no', modelPath, remoteTarget]);
    } else {
      // Key-based auth
      return Process.run('scp', ['-o', 'StrictHostKeyChecking=no', modelPath, remoteTarget]);
    }
  }

  String get modelsPath => _modelsDir.path;

  /// Open the models folder in the system file explorer.
  Future<void> openModelsFolder() async {
    if (Platform.isWindows) {
      await Process.run('explorer', [_modelsDir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [_modelsDir.path]);
    } else {
      await Process.run('xdg-open', [_modelsDir.path]);
    }
  }

  /// Upload firmware to robot via SCP.
  Future<ProcessResult> uploadFirmware({
    required String firmwarePath,
    required String host,
    required String user,
    required String remotePath,
    String? password,
  }) async {
    final remoteTarget = '$user@$host:$remotePath';
    if (password != null && password.isNotEmpty) {
      return Process.run('sshpass', ['-p', password, 'scp', '-o', 'StrictHostKeyChecking=no', firmwarePath, remoteTarget]);
    } else {
      return Process.run('scp', ['-o', 'StrictHostKeyChecking=no', firmwarePath, remoteTarget]);
    }
  }

  /// Run a remote SSH command (e.g. restart service).
  Future<ProcessResult> sshCommand({
    required String host,
    required String user,
    required String command,
    String? password,
  }) async {
    if (password != null && password.isNotEmpty) {
      return Process.run('sshpass', ['-p', password, 'ssh', '-o', 'StrictHostKeyChecking=no', '$user@$host', command]);
    } else {
      return Process.run('ssh', ['-o', 'StrictHostKeyChecking=no', '$user@$host', command]);
    }
  }
}
