import 'package:flutter/material.dart';
import '../services/grpc_service.dart';
import '../services/preset_service.dart';
import '../services/model_service.dart';
import '../services/run_history_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/sidebar.dart';
import 'dashboard_page.dart';
import 'monitor_page.dart';
import 'control_page.dart';
import 'params_page.dart';
import 'protocol_page.dart';

class ShellPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  final double textScale;
  final VoidCallback onScaleUp;
  final VoidCallback onScaleDown;
  final BrandColor brandColor;
  final ValueChanged<BrandColor> onChangeBrandColor;

  const ShellPage({
    super.key,
    required this.onToggleTheme, required this.isDark,
    required this.textScale, required this.onScaleUp, required this.onScaleDown,
    required this.brandColor, required this.onChangeBrandColor,
  });

  @override State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;
  final GrpcService _grpc = GrpcService();
  final PresetService _presetService = PresetService();
  final ModelService _modelService = ModelService();
  final RunHistoryService _runHistory = RunHistoryService();
  bool _wasConnected = false;

  @override void initState() {
    super.initState();
    _grpc.addListener(_onGrpcChanged);
    _grpc.onErrorNotify = (msg) {
      if (mounted) AppToast.showError(context, msg);
    };
    _presetService.init().then((_) { if (mounted) setState(() {}); });
    _modelService.init().then((_) { if (mounted) setState(() {}); });
    _runHistory.init();
  }
  @override void dispose() { _grpc.removeListener(_onGrpcChanged); _grpc.dispose(); super.dispose(); }
  void _onGrpcChanged() {
    if (mounted) setState(() {});
    if (_grpc.connected && !_wasConnected) {
      _runHistory.onConnect(_grpc.host, _grpc.port);
      _wasConnected = true;
    } else if (!_grpc.connected && _wasConnected) {
      _runHistory.onDisconnect();
      _wasConnected = false;
    }
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0: return DashboardPage(grpc: _grpc);
      case 1: return MonitorPage(grpc: _grpc);
      case 2: return ControlPage(grpc: _grpc);
      case 3: return ParamsPage(grpc: _grpc, presetService: _presetService, modelService: _modelService);
      case 4: return ProtocolPage(grpc: _grpc, runHistory: _runHistory);
      default: return DashboardPage(grpc: _grpc);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Sidebar(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
            isDark: widget.isDark,
            onToggleTheme: widget.onToggleTheme,
            isConnected: _grpc.connected,
            connectionInfo: '${_grpc.host}:${_grpc.port}',
            textScale: widget.textScale,
            onScaleUp: widget.onScaleUp,
            onScaleDown: widget.onScaleDown,
            brandColor: widget.brandColor,
            onChangeBrandColor: widget.onChangeBrandColor,
          ),
        ),
        Expanded(child: _buildPage()),
      ]),
    );
  }
}
