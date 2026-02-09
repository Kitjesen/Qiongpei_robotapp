import 'dart:convert';
import 'dart:io';

/// Names for the 16 joints.
const List<String> jointNames = [
  'FR_hip', 'FR_thigh', 'FR_calf',
  'FL_hip', 'FL_thigh', 'FL_calf',
  'RR_hip', 'RR_thigh', 'RR_calf',
  'RL_hip', 'RL_thigh', 'RL_calf',
  'FR_foot', 'FL_foot', 'RR_foot', 'RL_foot',
];

/// Short leg group names.
const List<String> legGroups = ['FR', 'FL', 'RR', 'RL'];

/// Configurable robot parameters (local config file).
class RobotConfig {
  // KP / KD gains
  List<double> inferKp;
  List<double> inferKd;
  List<double> standUpKp;
  List<double> standUpKd;
  List<double> sitDownKp;
  List<double> sitDownKd;

  // Poses (16 joints each)
  List<double> standingPose;
  List<double> sittingPose;

  // Brain params
  int historySize;
  int standUpCounts;
  int sitDownCounts;
  double imuGyroscopeScale;
  List<double> jointVelocityScale;
  List<double> actionScale;

  // Custom poses (user-defined, name -> 16 joint values)
  Map<String, List<double>> customPoses;

  RobotConfig({
    List<double>? inferKp,
    List<double>? inferKd,
    List<double>? standUpKp,
    List<double>? standUpKd,
    List<double>? sitDownKp,
    List<double>? sitDownKd,
    List<double>? standingPose,
    List<double>? sittingPose,
    this.historySize = 1,
    this.standUpCounts = 150,
    this.sitDownCounts = 150,
    this.imuGyroscopeScale = 0.25,
    List<double>? jointVelocityScale,
    List<double>? actionScale,
    Map<String, List<double>>? customPoses,
  })  : customPoses = customPoses ?? {},
        inferKp = inferKp ?? _defaultInferKp(),
        inferKd = inferKd ?? _defaultInferKd(),
        standUpKp = standUpKp ?? List.filled(16, 200.0),
        standUpKd = standUpKd ?? List.filled(16, 8.0),
        sitDownKp = sitDownKp ?? List.filled(16, 200.0),
        sitDownKd = sitDownKd ?? List.filled(16, 8.0),
        standingPose = standingPose ?? _defaultStandingPose(),
        sittingPose = sittingPose ?? List.filled(16, 0.0),
        jointVelocityScale =
            jointVelocityScale ?? [0.05, 0.05, 0.05, 0.05],
        actionScale = actionScale ?? [0.125, 0.25, 0.25, 5.0];

  static List<double> _defaultInferKp() {
    // 12 leg joints = 180, 4 foot joints = 0
    return [
      180, 180, 180, 180, 180, 180,
      180, 180, 180, 180, 180, 180,
      0, 0, 0, 0,
    ];
  }

  static List<double> _defaultInferKd() {
    return [
      15, 15, 15, 15, 15, 15,
      15, 15, 15, 15, 15, 15,
      1, 1, 1, 1,
    ];
  }

  static List<double> _defaultStandingPose() {
    return [
      0, -0.64, 1.6,
      0,  0.64, -1.6,
      0,  0.64, -1.6,
      0, -0.64, 1.6,
      0, 0, 0, 0,
    ];
  }

  Map<String, dynamic> toJson() => {
        'inferKp': inferKp,
        'inferKd': inferKd,
        'standUpKp': standUpKp,
        'standUpKd': standUpKd,
        'sitDownKp': sitDownKp,
        'sitDownKd': sitDownKd,
        'standingPose': standingPose,
        'sittingPose': sittingPose,
        'historySize': historySize,
        'standUpCounts': standUpCounts,
        'sitDownCounts': sitDownCounts,
        'imuGyroscopeScale': imuGyroscopeScale,
        'jointVelocityScale': jointVelocityScale,
        'actionScale': actionScale,
        'customPoses': customPoses.map((k, v) => MapEntry(k, v)),
      };

  factory RobotConfig.fromJson(Map<String, dynamic> json) => RobotConfig(
        inferKp: (json['inferKp'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        inferKd: (json['inferKd'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        standUpKp: (json['standUpKp'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        standUpKd: (json['standUpKd'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        sitDownKp: (json['sitDownKp'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        sitDownKd: (json['sitDownKd'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        standingPose: (json['standingPose'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        sittingPose: (json['sittingPose'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        historySize: (json['historySize'] as num?)?.toInt() ?? 1,
        standUpCounts: (json['standUpCounts'] as num?)?.toInt() ?? 150,
        sitDownCounts: (json['sitDownCounts'] as num?)?.toInt() ?? 150,
        imuGyroscopeScale: (json['imuGyroscopeScale'] as num?)?.toDouble() ?? 0.25,
        jointVelocityScale: (json['jointVelocityScale'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        actionScale: (json['actionScale'] as List?)?.cast<num>().map((e) => e.toDouble()).toList(),
        customPoses: (json['customPoses'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as List).cast<num>().map((e) => e.toDouble()).toList())),
      );

  Future<void> saveToFile(String path) async {
    final file = File(path);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  static Future<RobotConfig> loadFromFile(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    return RobotConfig.fromJson(jsonDecode(content) as Map<String, dynamic>);
  }
}
