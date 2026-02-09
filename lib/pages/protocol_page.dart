import 'package:flutter/material.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';

class ProtocolPage extends StatefulWidget {
  final GrpcService grpc;
  const ProtocolPage({super.key, required this.grpc});

  @override
  State<ProtocolPage> createState() => _ProtocolPageState();
}

class _ProtocolPageState extends State<ProtocolPage> {
  bool _autoScroll = true;
  final _scrollController = ScrollController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    widget.grpc.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.grpc.removeListener(_onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  List<ProtocolLogEntry> get _filteredLog {
    if (_filter.isEmpty) return widget.grpc.protocolLog;
    return widget.grpc.protocolLog
        .where((e) => e.method.toLowerCase().contains(_filter.toLowerCase()) || e.summary.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final grpc = widget.grpc;
    final log = _filteredLog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('协议日志', style: tt.headlineLarge),
              const SizedBox(height: 4),
              Text('gRPC 通信记录与 CMS 状态机可视化', style: tt.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // State machine visualization
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildStateMachine(tt, cs, grpc),
        ),
        const SizedBox(height: 16),

        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: tt.bodyMedium,
                  decoration: InputDecoration(
                    hintText: '筛选方法名或内容...',
                    hintStyle: tt.bodySmall,
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outline, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outline, width: 0.5),
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 12),
              Text('${log.length} 条', style: tt.bodySmall),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  grpc.protocolLog.clear();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline, width: 0.5),
                  ),
                  child: Text('清空', style: tt.labelMedium),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Log list
        Expanded(
          child: log.isEmpty
              ? Center(
                  child: Text('暂无日志', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: log.length,
                  itemBuilder: (_, i) => _LogRow(entry: log[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildStateMachine(TextTheme tt, ColorScheme cs, GrpcService grpc) {
    final states = ['Idle', 'StandUp', 'SitDown', 'Walking'];
    final colors = {
      'Idle': AppTheme.yellow,
      'StandUp': AppTheme.teal,
      'SitDown': AppTheme.orange,
      'Walking': AppTheme.green,
      'Unknown': AppTheme.red,
    };

    return StatusCard(
      title: 'CMS 状态机',
      trailing: Text(
        '当前: ${grpc.cmsState}',
        style: tt.labelMedium?.copyWith(
          color: colors[grpc.cmsState] ?? AppTheme.red,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: states.map((state) {
          final isActive = grpc.cmsState == state;
          final color = colors[state] ?? cs.outline;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border.all(
                    color: isActive ? color : cs.outline.withValues(alpha: 0.3),
                    width: isActive ? 2.5 : 1,
                  ),
                  boxShadow: isActive
                      ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12)]
                      : [],
                ),
                child: Center(
                  child: Icon(
                    _stateIcon(state),
                    size: 24,
                    color: isActive ? color : cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state,
                style: tt.labelSmall?.copyWith(
                  color: isActive ? color : cs.onSurface.withValues(alpha: 0.4),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'Idle':
        return Icons.pause_circle_outline_rounded;
      case 'StandUp':
        return Icons.arrow_upward_rounded;
      case 'SitDown':
        return Icons.arrow_downward_rounded;
      case 'Walking':
        return Icons.directions_walk_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

class _LogRow extends StatelessWidget {
  final ProtocolLogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Color dirColor;
    switch (entry.direction) {
      case '→':
        dirColor = AppTheme.teal;
        break;
      case '←':
        dirColor = AppTheme.green;
        break;
      default:
        dirColor = AppTheme.red;
    }

    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}.'
        '${entry.time.millisecond.toString().padLeft(3, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 85,
              child: Text(
                timeStr,
                style: tt.bodySmall?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(
              width: 20,
              child: Text(entry.direction, style: TextStyle(color: dirColor, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 120,
              child: Text(
                entry.method,
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(
                entry.summary,
                style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
