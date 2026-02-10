import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
      case 4: return ProtocolPage(grpc: _grpc);
      default: return DashboardPage(grpc: _grpc);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        // Custom title bar with drag area and window controls
        const _CustomTitleBar(),
        // Main content
        Expanded(
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
        ),
      ]),
    );
  }
}

/// Custom title bar with drag-to-move and window control buttons.
class _CustomTitleBar extends StatefulWidget {
  const _CustomTitleBar();

  @override
  State<_CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<_CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onDoubleTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 36,
        color: cs.surface,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // App icon + title
            Icon(Icons.smart_toy_rounded, size: 16, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text(
              '穹佩控制面板',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            // Drag area fills remaining space
            Expanded(
              child: DragToMoveArea(child: Container(height: 36)),
            ),
            // Window control buttons
            _WindowButton(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
              hoverColor: cs.onSurface.withValues(alpha: 0.08),
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              iconSize: _isMaximized ? 13 : 15,
              onTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              hoverColor: cs.onSurface.withValues(alpha: 0.08),
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              onTap: () => windowManager.close(),
              hoverColor: const Color(0xFFE81123),
              hoverIconColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single window control button (minimize / maximize / close).
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color? hoverIconColor;

  const _WindowButton({
    required this.icon,
    this.iconSize = 15,
    required this.onTap,
    required this.hoverColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 36,
          color: _hovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered && widget.hoverIconColor != null
                  ? widget.hoverIconColor
                  : cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
