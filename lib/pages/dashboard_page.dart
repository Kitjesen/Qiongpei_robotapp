import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class DashboardPage extends StatefulWidget {
  final GrpcService grpc;
  const DashboardPage({super.key, required this.grpc});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _hC = TextEditingController(text: '192.168.66.192');
  final _pC = TextEditingController(text: '13145');
  bool _busy = false;

  @override void initState() { super.initState(); _hC.text = widget.grpc.host; _pC.text = widget.grpc.port.toString(); }
  @override void dispose() { _hC.dispose(); _pC.dispose(); super.dispose(); }
  Future<void> _connect() async {
    setState(() => _busy = true);
    await widget.grpc.connect(_hC.text.trim(), int.tryParse(_pC.text.trim()) ?? 13145);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.grpc.connected) {
      AppToast.showSuccess(context, '已连接 ${widget.grpc.host}:${widget.grpc.port}');
    } else if (widget.grpc.error != null) {
      AppToast.showError(context, '连接失败: ${widget.grpc.error}');
    }
  }
  String _t(int s) => '${(s ~/ 3600).toString().padLeft(2, "0")}:${((s % 3600) ~/ 60).toString().padLeft(2, "0")}:${(s % 60).toString().padLeft(2, "0")}';

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;
    const gap = SizedBox(height: 14);
    const hg = SizedBox(width: 14);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Text('Dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: -0.5)),
          const Spacer(),
          _connBar(context, g),
        ]),
        gap,
        Expanded(child: SingleChildScrollView(child: Column(children: [
          // 4 stat cards
          Row(children: [
            Expanded(child: _StatCard(icon: Icons.memory_rounded, label: '状态', value: g.cmsState, accent: const Color(0xFF7C3AED))),
            hg, Expanded(child: _StatCard(icon: Icons.speed_rounded, label: '推理频率', value: g.historyHz.toStringAsFixed(1), unit: 'Hz', accent: const Color(0xFF059669))),
            hg, Expanded(child: _StatCard(icon: Icons.explore_rounded, label: 'IMU 频率', value: g.imuHz.toStringAsFixed(1), unit: 'Hz', accent: const Color(0xFF2563EB))),
            hg, Expanded(child: _StatCard(icon: Icons.precision_manufacturing_rounded, label: '关节频率', value: g.jointHz.toStringAsFixed(1), unit: 'Hz', accent: const Color(0xFFEA580C))),
          ]),
          gap,
          // State bar + Actions + System badge (single compact row)
          _controlRow(context, g),
          gap,
          // 4 leg cards
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _LegCard(grpc: g, leg: 'FR', indices: const [0, 1, 2, 12], accent: const Color(0xFF3B82F6))),
            hg, Expanded(child: _LegCard(grpc: g, leg: 'FL', indices: const [3, 4, 5, 13], accent: const Color(0xFF10B981))),
          ]),
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _LegCard(grpc: g, leg: 'RR', indices: const [6, 7, 8, 14], accent: const Color(0xFFF59E0B))),
            hg, Expanded(child: _LegCard(grpc: g, leg: 'RL', indices: const [9, 10, 11, 15], accent: const Color(0xFF8B5CF6))),
          ]),
          gap,
          // Camera + 3D
          SizedBox(height: 260, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 240, child: _HoverCard(child: _camera(context))),
            hg, Expanded(flex: 2, child: _HoverCard(child: _pose3d(context, g))),
          ])),
          const SizedBox(height: 20),
        ]))),
      ]),
    );
  }

  // ── Connection bar ──
  Widget _connBar(BuildContext c, GrpcService g) {
    final cs = Theme.of(c).colorScheme;
    // Determine connection indicator color based on health
    Color dotColor;
    if (g.isReconnecting) {
      dotColor = AppTheme.orange;
    } else if (g.connected && g.isStale) {
      dotColor = AppTheme.orange;
    } else if (g.connected) {
      dotColor = AppTheme.green;
    } else {
      dotColor = cs.onSurface.withValues(alpha: 0.12);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 8),
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
        const SizedBox(width: 4),
        // Health status label
        if (g.isReconnecting || (g.connected && g.isStale))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              g.healthStatus,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.orange),
            ),
          ),
        const SizedBox(width: 4),
        SizedBox(width: 120, child: _inp(c, _hC, 'IP', !g.connected && !g.isReconnecting)),
        const SizedBox(width: 5),
        SizedBox(width: 56, child: _inp(c, _pC, 'Port', !g.connected && !g.isReconnecting)),
        const SizedBox(width: 5),
        _ConnBtn(
          label: g.connected ? 'Disconnect' : (g.isReconnecting ? 'Cancel' : 'Connect'),
          filled: !g.connected && !g.isReconnecting,
          onTap: g.connected
              ? () { widget.grpc.disconnect(); AppToast.showSuccess(context, '已断开'); }
              : g.isReconnecting
                  ? () { widget.grpc.disconnect(); AppToast.showSuccess(context, '已取消重连'); }
                  : (_busy ? null : _connect),
        ),
      ]),
    );
  }

  Widget _inp(BuildContext c, TextEditingController ctrl, String h, bool on) {
    final cs = Theme.of(c).colorScheme;
    return TextField(controller: ctrl, enabled: on, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface), decoration: InputDecoration(hintText: h, hintStyle: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.2)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), filled: true, fillColor: cs.onSurface.withValues(alpha: 0.03), border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: AppTheme.brand.withValues(alpha: 0.3)))));
  }

  // ── Control Row: State pills + Action buttons + System badge ──
  Widget _controlRow(BuildContext c, GrpcService g) {
    final cs = Theme.of(c).colorScheme;
    final state = g.cmsState;
    // 5 CMS states matching han_dog_brain S class: Zero->Grounded, StandUp(transitioning), Standing, Walking, SitDown(transitioning)
    const states = ['Idle', 'StandUp', 'Standing', 'Walking', 'SitDown'];
    const stateIcons = [Icons.pause_circle_outlined, Icons.publish_rounded, Icons.accessibility_new_rounded, Icons.directions_walk_rounded, Icons.get_app_rounded];
    Color sc(String s) { switch (s) { case 'Walking': return AppTheme.brand; case 'StandUp': return AppTheme.green; case 'Standing': return const Color(0xFF059669); case 'SitDown': return AppTheme.orange; case 'Idle': return const Color(0xFF64748B); default: return AppTheme.red; } }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(children: [
        // State pills
        ...List.generate(states.length, (i) {
          final active = states[i] == state;
          return Padding(padding: const EdgeInsets.only(right: 6), child: Container(
            padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? sc(states[i]) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(stateIcons[i], size: 14, color: active ? Colors.white : cs.onSurface.withValues(alpha: 0.2)),
              const SizedBox(width: 5),
              Text(states[i], style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : cs.onSurface.withValues(alpha: 0.25))),
            ]),
          ));
        }),

        const Spacer(),

        // Action buttons
        _ActBtn(label: 'Enable', icon: Icons.power_settings_new_rounded, color: AppTheme.green, onTap: g.connected ? g.enable : null),
        const SizedBox(width: 6),
        _ActBtn(label: 'Disable', icon: Icons.block_rounded, color: AppTheme.red, onTap: g.connected ? g.disable : null),
        const SizedBox(width: 6),
        _ActBtn(label: 'Stand Up', icon: Icons.arrow_upward_rounded, color: AppTheme.teal, onTap: g.connected ? g.standUp : null),
        const SizedBox(width: 6),
        _ActBtn(label: 'Sit Down', icon: Icons.arrow_downward_rounded, color: AppTheme.orange, onTap: g.connected ? g.sitDown : null),

        const SizedBox(width: 14),

        // System badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('SYSTEM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.5)),
            const SizedBox(width: 8),
            Text(g.params != null && g.params!.hasRobot() ? g.params!.robot.type.name : '--', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(width: 8),
            Icon(Icons.smart_toy_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.3)),
          ]),
        ),
      ]),
    );
  }

  // ── Camera ──
  Widget _camera(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Container(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 0), child: Row(children: [Text('Camera', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)), const Spacer(), Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.red)), const SizedBox(width: 4), Text('LIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5))])),
      Expanded(child: Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(10)), child: Center(child: Icon(Icons.videocam_off_outlined, size: 28, color: Colors.white.withValues(alpha: 0.1))))),
    ]));
  }

  // ── 3D Pose ──
  Widget _pose3d(BuildContext c, GrpcService g) {
    final cs = Theme.of(c).colorScheme;
    final q = g.latestImu?.quaternion;
    double pitch = 0, roll = 0, yaw = 0;
    if (q != null) { roll = math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) * 180 / math.pi; final sp = 2 * (q.w * q.y - q.z * q.x); pitch = (sp.abs() >= 1 ? (math.pi / 2) * sp.sign : math.asin(sp)) * 180 / math.pi; yaw = math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) * 180 / math.pi; }
    Widget tag(String l, String v) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outline.withValues(alpha: 0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [Text('$l ', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4))), Text('$v\u00B0', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.brand, fontFeatures: const [FontFeature.tabularFigures()]))]));
    return Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _GridP(cs: cs))),
      Positioned(top: 14, left: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('3D Pose', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)), Text('Kinematic visualization', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.35)))])),
      Positioned(top: 14, right: 14, child: Row(children: [tag('P', pitch.toStringAsFixed(1)), const SizedBox(width: 4), tag('R', roll.toStringAsFixed(1)), const SizedBox(width: 4), tag('Y', yaw.toStringAsFixed(1))])),
      Center(child: CustomPaint(size: const Size(180, 100), painter: _RobotP(cs: cs, roll: roll))),
    ]);
  }
}

// ══════════════════════════════════════
// Hover Card wrapper (lift + shadow on hover)
// ══════════════════════════════════════
class _HoverCard extends StatefulWidget {
  final Widget child;
  const _HoverCard({required this.child});
  @override State<_HoverCard> createState() => _HoverCardState();
}
class _HoverCardState extends State<_HoverCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _hov ? (Matrix4.identity()..translate(0.0, -2.0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? AppTheme.brand.withValues(alpha: 0.2) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      ),
    );
  }
}

// ══════════════════════════════════════
// Stat Card with hover
// ══════════════════════════════════════
class _StatCard extends StatefulWidget {
  final IconData icon; final String label; final String value; final String? unit; final Color accent;
  const _StatCard({required this.icon, required this.label, required this.value, this.unit, required this.accent});
  @override State<_StatCard> createState() => _StatCardState();
}
class _StatCardState extends State<_StatCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hov ? (Matrix4.identity()..translate(0.0, -2.0)) : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? widget.accent.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)), child: Icon(widget.icon, size: 20, color: widget.accent)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Flexible(child: Text(widget.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _hov ? widget.accent : cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), overflow: TextOverflow.ellipsis)),
              if (widget.unit != null) Text(' ${widget.unit}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25))),
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Leg Card with hover
// ══════════════════════════════════════
class _LegCard extends StatefulWidget {
  final GrpcService grpc; final String leg; final List<int> indices; final Color accent;
  const _LegCard({required this.grpc, required this.leg, required this.indices, required this.accent});
  @override State<_LegCard> createState() => _LegCardState();
}
class _LegCardState extends State<_LegCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final j = widget.grpc.latestJoints;
    const joints = ['Hip', 'Thigh', 'Calf', 'Foot'];
    final legNames = {'FR': 'Front Right', 'FL': 'Front Left', 'RR': 'Rear Right', 'RL': 'Rear Left'};

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hov ? (Matrix4.identity()..translate(0.0, -2.0)) : Matrix4.identity(),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? widget.accent.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        child: Row(children: [
          Container(width: 4, color: widget.accent),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${widget.leg} Leg', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: widget.accent)),
            const SizedBox(width: 6),
            Text(legNames[widget.leg] ?? '', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3))),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4)), child: Text(widget.grpc.connected ? 'Active' : 'Idle', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: widget.accent))),
          ]),
          const SizedBox(height: 4),
          Divider(color: cs.onSurface.withValues(alpha: 0.04), height: 8),
          Row(children: [
            SizedBox(width: 50, child: Text('JOINT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5))),
            Expanded(child: Text('POS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            Expanded(child: Text('VEL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            Expanded(child: Text('TRQ', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            const SizedBox(width: 40),
          ]),
          const SizedBox(height: 4),
          ...List.generate(4, (ji) {
            final idx = widget.indices[ji];
            final pos = j != null && j.position.values.length > idx ? j.position.values[idx] : 0.0;
            final vel = j != null && j.velocity.values.length > idx ? j.velocity.values[idx] : 0.0;
            final trq = j != null && j.torque.values.length > idx ? j.torque.values[idx] : 0.0;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              SizedBox(width: 50, child: Text(joints[ji], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface))),
              Expanded(child: Text(pos.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              Expanded(child: Text('${vel.toStringAsFixed(1)}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              Expanded(child: Text('${trq.toStringAsFixed(1)}', style: TextStyle(fontSize: 10, color: trq.abs() > 5 ? AppTheme.red : cs.onSurface.withValues(alpha: 0.5), fontWeight: trq.abs() > 5 ? FontWeight.w600 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              SizedBox(width: 40, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: (trq.abs() / 10.0).clamp(0.0, 1.0), minHeight: 6, backgroundColor: cs.onSurface.withValues(alpha: 0.04), valueColor: AlwaysStoppedAnimation(trq.abs() > 5 ? AppTheme.red : widget.accent.withValues(alpha: 0.5))))),
            ]));
          }),
        ]),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Action Button with hover + press
// ══════════════════════════════════════
class _ActBtn extends StatefulWidget {
  final String label; final IconData icon; final Color color; final VoidCallback? onTap;
  const _ActBtn({required this.label, required this.icon, required this.color, this.onTap});
  @override State<_ActBtn> createState() => _ActBtnState();
}
class _ActBtnState extends State<_ActBtn> {
  bool _hov = false; bool _press = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = widget.onTap != null;
    return MouseRegion(
      onEnter: on ? (_) => setState(() => _hov = true) : null,
      onExit: on ? (_) => setState(() => _hov = false) : null,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _press = true) : null,
        onTapUp: on ? (_) => setState(() => _press = false) : null,
        onTapCancel: on ? () => setState(() => _press = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          transform: _press ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hov ? widget.color.withValues(alpha: 0.08) : cs.onSurface.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: _hov ? Border.all(color: widget.color.withValues(alpha: 0.2)) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: on ? (_hov ? widget.color : cs.onSurface.withValues(alpha: 0.4)) : cs.onSurface.withValues(alpha: 0.1)),
            const SizedBox(width: 5),
            Text(widget.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: on ? (_hov ? widget.color : cs.onSurface.withValues(alpha: 0.5)) : cs.onSurface.withValues(alpha: 0.15))),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════
// Connect Button with hover + press
// ══════════════════════════════════════
class _ConnBtn extends StatefulWidget {
  final String label; final bool filled; final VoidCallback? onTap;
  const _ConnBtn({required this.label, this.filled = true, this.onTap});
  @override State<_ConnBtn> createState() => _ConnBtnState();
}
class _ConnBtnState extends State<_ConnBtn> {
  bool _hov = false; bool _press = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = widget.onTap != null;
    return MouseRegion(
      onEnter: on ? (_) => setState(() => _hov = true) : null,
      onExit: on ? (_) => setState(() => _hov = false) : null,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _press = true) : null,
        onTapUp: on ? (_) => setState(() => _press = false) : null,
        onTapCancel: on ? () => setState(() => _press = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          transform: _press ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.filled ? (_hov ? AppTheme.brand.withValues(alpha: 0.85) : AppTheme.brand) : (_hov ? cs.onSurface.withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.filled ? [BoxShadow(color: AppTheme.brand.withValues(alpha: _hov ? 0.35 : 0.2), blurRadius: _hov ? 10 : 6, offset: const Offset(0, 2))] : [],
          ),
          child: Text(widget.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.filled ? Colors.white : cs.onSurface.withValues(alpha: 0.5))),
        ),
      ),
    );
  }
}

// ── Painters ──
class _GridP extends CustomPainter {
  final ColorScheme cs; _GridP({required this.cs});
  @override void paint(Canvas c, Size s) { final p = Paint()..color = cs.onSurface.withValues(alpha: 0.03)..strokeWidth = 1; for (double x = 0; x < s.width; x += 40) c.drawLine(Offset(x, 0), Offset(x, s.height), p); for (double y = 0; y < s.height; y += 40) c.drawLine(Offset(0, y), Offset(s.width, y), p); }
  @override bool shouldRepaint(covariant CustomPainter o) => false;
}

class _RobotP extends CustomPainter {
  final ColorScheme cs; final double roll; _RobotP({required this.cs, required this.roll});
  @override void paint(Canvas c, Size s) {
    final cx = s.width / 2; final cy = s.height / 2; c.save(); c.translate(cx, cy); c.rotate((roll * math.pi / 180).clamp(-0.3, 0.3));
    final bw = s.width * 0.38; final bh = s.height * 0.35;
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bw, height: bh), const Radius.circular(16));
    c.drawRRect(body, Paint()..color = cs.onSurface.withValues(alpha: 0.06)); c.drawRRect(body, Paint()..color = cs.onSurface.withValues(alpha: 0.1)..style = PaintingStyle.stroke..strokeWidth = 2);
    c.drawCircle(Offset(-bw / 2 - 4, 0), 3, Paint()..color = AppTheme.green);
    final tp = TextPainter(text: TextSpan(text: 'ROBOT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.12), letterSpacing: 2)), textDirection: TextDirection.ltr)..layout(); tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    final lp = Paint()..color = cs.onSurface.withValues(alpha: 0.12)..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    for (final p in [[-1.0, -1.0], [-1.0, 1.0], [1.0, -1.0], [1.0, 1.0]]) { final ox = p[0] * bw * 0.4; final oy = p[1] * bh * 0.6; c.drawLine(Offset(ox, oy), Offset(ox + p[0] * 12, oy + p[1] * 18), lp); c.drawLine(Offset(ox + p[0] * 12, oy + p[1] * 18), Offset(ox + p[0] * 8, oy + p[1] * 36), lp); }
    c.restore();
  }
  @override bool shouldRepaint(covariant _RobotP o) => o.roll != roll;
}
