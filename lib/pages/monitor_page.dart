import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../models/robot_config.dart';

class MonitorPage extends StatefulWidget {
  final GrpcService grpc;
  const MonitorPage({super.key, required this.grpc});
  @override State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const int _maxPts = 200;
  final List<List<double>> _jHist = List.generate(16, (_) => []);
  int _tick = 0;
  int _selLeg = 0; // 0=FR, 1=FL, 2=RR, 3=RL

  @override
  void initState() { super.initState(); widget.grpc.addListener(_onData); }
  @override
  void dispose() { widget.grpc.removeListener(_onData); super.dispose(); }

  void _onData() {
    _tick++;
    final h = widget.grpc.latestHistory;
    if (h != null && h.hasJointPosition()) {
      for (int i = 0; i < 16 && i < h.jointPosition.values.length; i++) {
        _jHist[i].add(h.jointPosition.values[i]);
        if (_jHist[i].length > _maxPts) _jHist[i].removeAt(0);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Row(children: [
          Text('实时监控', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.2), width: 1)), child: Text(g.connected ? 'Online' : 'Offline', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: g.connected ? AppTheme.green : AppTheme.red))),
          const Spacer(),
          // Power / current overview
          _powerBar(context, g),
        ]),
        const SizedBox(height: 4),
        Text('System Status: ${g.connected ? "Nominal" : "--"} • Latency: ${g.connected ? "12ms" : "--"}', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
        const SizedBox(height: 16),

        // ── Main content: 8:4 ──
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Left column (8/12)
          Expanded(flex: 2, child: Column(children: [
            // Joint angles chart
            Expanded(flex: 4, child: _chartCard(context, g)),
            const SizedBox(height: 12),
            // System logs
            Expanded(flex: 5, child: _logsCard(context, g)),
          ])),
          const SizedBox(width: 12),
          // Right column (4/12) - 4 leg cards
          SizedBox(width: 320, child: SingleChildScrollView(child: Column(children: [
            _legCard(context, g, 'FR Leg', 0, const Color(0xFF3B82F6)),
            const SizedBox(height: 10),
            _legCard(context, g, 'FL Leg', 3, const Color(0xFF10B981)),
            const SizedBox(height: 10),
            _legCard(context, g, 'RR Leg', 6, const Color(0xFFF59E0B)),
            const SizedBox(height: 10),
            _legCard(context, g, 'RL Leg', 9, const Color(0xFF8B5CF6)),
          ]))),
        ])),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Power / Current bar
  // ══════════════════════════════════════════════
  Widget _powerBar(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    const legs = ['FR', 'FL', 'RR', 'RL'];
    const colors = [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF8B5CF6)];
    final j = g.latestJoints;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Power indicator
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.bolt_rounded, size: 18, color: AppTheme.orange)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTAL POWER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.8)),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('24.5', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(' V', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.3))),
          ]),
        ]),
        Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 14), color: cs.onSurface.withValues(alpha: 0.06)),
        // Per-leg current
        ...List.generate(4, (i) {
          final torqueSum = j != null && j.torque.values.length > i * 3 + 2 ? (j.torque.values[i * 3].abs() + j.torque.values[i * 3 + 1].abs() + j.torque.values[i * 3 + 2].abs()) / 3 : 0.0;
          return Padding(padding: const EdgeInsets.only(left: 10), child: Column(children: [
            Text(legs[i], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.35), fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${torqueSum.toStringAsFixed(1)}A', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            SizedBox(width: 40, height: 3, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: (torqueSum / 5).clamp(0.0, 1.0), backgroundColor: cs.onSurface.withValues(alpha: 0.04), valueColor: AlwaysStoppedAnimation(colors[i])))),
          ]));
        }),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Joint Angles Chart
  // ══════════════════════════════════════════════
  Widget _chartCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    const legNames = ['FR', 'FL', 'RR', 'RL'];
    final baseIdx = _selLeg * 3;
    const legColors = [Color(0xFF6366F1), Color(0xFF34D399), Color(0xFFF472B6)];
    const jointSuffix = ['_hip', '_thigh', '_calf'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 6),
          Text('Joint Angles (rad)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          // Leg selector
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
            child: Row(children: List.generate(4, (i) => GestureDetector(
              onTap: () => setState(() => _selLeg = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _selLeg == i ? cs.surface : Colors.transparent, borderRadius: BorderRadius.circular(6), boxShadow: _selLeg == i ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : []),
                child: Text(legNames[i], style: TextStyle(fontSize: 11, fontWeight: _selLeg == i ? FontWeight.w600 : FontWeight.w400, color: _selLeg == i ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.35))),
              ),
            ))),
          ),
        ]),
        const SizedBox(height: 12),
        // Chart
        Expanded(child: _jHist[baseIdx].isEmpty
          ? Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.green)),
              const SizedBox(width: 6),
              Text('Receiving Data Stream', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.3))),
            ]))
          : LineChart(LineChartData(
              lineBarsData: List.generate(3, (ji) {
                final data = _jHist[baseIdx + ji];
                return LineChartBarData(spots: List.generate(data.length, (x) => FlSpot(x.toDouble(), data[x])), isCurved: true, curveSmoothness: 0.2, color: legColors[ji], barWidth: 2, dotData: const FlDotData(show: false));
              }),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5, getDrawingHorizontalLine: (v) => FlLine(color: cs.onSurface.withValues(alpha: 0.04), strokeWidth: 1)),
              titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.25))))), bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
            ), duration: Duration.zero),
        ),
        // Legend
        Row(children: List.generate(3, (ji) => Padding(padding: const EdgeInsets.only(right: 16), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 3, decoration: BoxDecoration(color: legColors[ji], borderRadius: BorderRadius.circular(2))), const SizedBox(width: 4), Text('${legNames[_selLeg]}${jointSuffix[ji]}', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.35)))])))),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // System Logs
  // ══════════════════════════════════════════════
  Widget _logsCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    final log = g.protocolLog;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.receipt_long_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 6),
          Text('System Logs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          Text('buffer: ${log.length} lines', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25), fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 10),
        Expanded(child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.onSurface.withValues(alpha: 0.04), width: 1)),
          child: log.isEmpty
            ? Center(child: Text('No logs yet...', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.15))))
            : ListView.builder(
                itemCount: log.length,
                itemBuilder: (_, i) {
                  final e = log[i];
                  final t = '${e.time.hour.toString().padLeft(2, "0")}:${e.time.minute.toString().padLeft(2, "0")}:${e.time.second.toString().padLeft(2, "0")}';
                  Color levelColor;
                  String level;
                  if (e.direction == '\u2192') { levelColor = AppTheme.teal; level = 'INFO'; }
                  else if (e.direction == '\u2190') { levelColor = AppTheme.green; level = 'STATUS'; }
                  else { levelColor = AppTheme.red; level = 'ERROR'; }
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Text.rich(TextSpan(children: [
                    TextSpan(text: '[$t] ', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25), fontFeatures: const [FontFeature.tabularFigures()])),
                    TextSpan(text: level, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: levelColor)),
                    TextSpan(text: ' ${e.method}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
                    if (e.summary.isNotEmpty) TextSpan(text: ' ${e.summary}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35))),
                  ])));
                },
              ),
        )),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Leg Detail Card
  // ══════════════════════════════════════════════
  Widget _legCard(BuildContext ctx, GrpcService g, String title, int baseIdx, Color accent) {
    final cs = Theme.of(ctx).colorScheme;
    final j = g.latestJoints;
    const joints = ['Hip', 'Thigh', 'Calf'];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(width: 4, color: accent),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4)), child: Text('Active', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: accent))),
        ]),
        Divider(color: cs.onSurface.withValues(alpha: 0.06), height: 16),
        // Table header
        Row(children: [
          SizedBox(width: 48, child: Text('JOINT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5))),
          SizedBox(width: 56, child: Text('RAD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5), textAlign: TextAlign.right)),
          Expanded(child: Text('VEL / TRQ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5), textAlign: TextAlign.center)),
        ]),
        const SizedBox(height: 4),
        // 3 joint rows
        ...List.generate(3, (ji) {
          final idx = baseIdx + ji;
          final pos = j != null && j.position.values.length > idx ? j.position.values[idx] : 0.0;
          final vel = j != null && j.velocity.values.length > idx ? j.velocity.values[idx] : 0.0;
          final torque = j != null && j.torque.values.length > idx ? j.torque.values[idx] : 0.0;

          // Mini sparkline from history
          final hist = _jHist[idx];
          final sparkLen = math.min(hist.length, 20);

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: ji < 2 ? BoxDecoration(border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.04)))) : null,
            child: Row(children: [
              SizedBox(width: 48, child: Text(joints[ji], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.6)))),
              SizedBox(width: 56, child: Text(pos.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.4), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.right)),
              const SizedBox(width: 10),
              // Sparkline
              SizedBox(width: 60, height: 20, child: sparkLen > 1
                ? CustomPaint(painter: _SparkPainter(data: hist.sublist(hist.length - sparkLen), color: accent.withValues(alpha: 0.5)))
                : Container(height: 1, color: cs.onSurface.withValues(alpha: 0.06))),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${vel.toStringAsFixed(1)} r/s', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3), fontFeatures: const [FontFeature.tabularFigures()])),
                Text('${torque.toStringAsFixed(1)} Nm', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3), fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ]),
          );
        }),
      ]),
        )),
      ]),
    );
  }
}

// ── Sparkline painter ──
class _SparkPainter extends CustomPainter {
  final List<double> data; final Color color;
  _SparkPainter({required this.data, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final mn = data.reduce(math.min); final mx = data.reduce(math.max);
    final range = mx - mn == 0 ? 1.0 : mx - mn;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - ((data[i] - mn) / range * size.height);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(covariant _SparkPainter old) => true;
}
