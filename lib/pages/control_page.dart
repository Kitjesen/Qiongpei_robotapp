import 'dart:async';
import 'package:flutter/material.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';

class ControlPage extends StatefulWidget {
  final GrpcService grpc;
  const ControlPage({super.key, required this.grpc});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  double _joyX = 0;
  double _joyY = 0;
  double _rotZ = 0;
  Timer? _walkTimer;
  bool _isEnabled = false;

  @override
  void dispose() {
    _walkTimer?.cancel();
    super.dispose();
  }

  void _startWalking() {
    _walkTimer?.cancel();
    _walkTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_joyX != 0 || _joyY != 0 || _rotZ != 0) {
        widget.grpc.walk(_joyY, _joyX, _rotZ); // x=forward, y=lateral, z=rotation
      }
    });
  }

  void _stopWalking() {
    _walkTimer?.cancel();
    _walkTimer = null;
    _joyX = 0;
    _joyY = 0;
    widget.grpc.walk(0, 0, 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final grpc = widget.grpc;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('遥控操作', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('虚拟摇杆和按钮控制', style: tt.bodySmall),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Joystick
              Expanded(
                flex: 2,
                child: StatusCard(
                  title: '方向控制',
                  trailing: Text(
                    'X: ${_joyY.toStringAsFixed(2)}  Y: ${_joyX.toStringAsFixed(2)}',
                    style: tt.bodySmall?.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
                  ),
                  child: Center(
                    child: _VirtualJoystick(
                      size: 240,
                      onChanged: (x, y) {
                        setState(() {
                          _joyX = x;
                          _joyY = y;
                        });
                        _startWalking();
                      },
                      onEnd: _stopWalking,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Controls panel
              Expanded(
                child: Column(
                  children: [
                    // Enable / Disable
                    StatusCard(
                      title: '硬件控制',
                      child: Column(
                        children: [
                          _ControlToggle(
                            label: '电机使能',
                            value: _isEnabled,
                            activeColor: AppTheme.green,
                            onChanged: grpc.connected
                                ? (v) async {
                                    if (v) {
                                      await grpc.enable();
                                    } else {
                                      await grpc.disable();
                                    }
                                    setState(() => _isEnabled = v);
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Behavior buttons
                    StatusCard(
                      title: '行为控制',
                      child: Column(
                        children: [
                          _BehaviorButton(
                            label: '站立',
                            icon: Icons.arrow_upward_rounded,
                            color: AppTheme.teal,
                            isActive: grpc.cmsState == 'StandUp',
                            onTap: grpc.connected ? grpc.standUp : null,
                          ),
                          const SizedBox(height: 8),
                          _BehaviorButton(
                            label: '坐下',
                            icon: Icons.arrow_downward_rounded,
                            color: AppTheme.orange,
                            isActive: grpc.cmsState == 'SitDown',
                            onTap: grpc.connected ? grpc.sitDown : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Rotation control
                    StatusCard(
                      title: '旋转控制',
                      trailing: Text(
                        'Z: ${_rotZ.toStringAsFixed(2)}',
                        style: tt.bodySmall?.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
                      ),
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: cs.primary,
                          inactiveTrackColor: cs.outline.withValues(alpha: 0.3),
                          thumbColor: cs.primary,
                          overlayShape: SliderComponentShape.noOverlay,
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _rotZ,
                          min: -1,
                          max: 1,
                          onChanged: grpc.connected
                              ? (v) {
                                  setState(() => _rotZ = v);
                                  _startWalking();
                                }
                              : null,
                          onChangeEnd: (_) {
                            setState(() => _rotZ = 0);
                            _stopWalking();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Current state
          StatusCard(
            title: '当前状态',
            child: Row(
              children: [
                MetricTile(label: 'CMS 状态', value: grpc.cmsState),
                const SizedBox(width: 32),
                MetricTile(label: '推理频率', value: '${grpc.historyHz.toStringAsFixed(1)}', unit: 'Hz'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Virtual Joystick ---

class _VirtualJoystick extends StatefulWidget {
  final double size;
  final void Function(double x, double y) onChanged;
  final VoidCallback onEnd;
  const _VirtualJoystick({required this.size, required this.onChanged, required this.onEnd});

  @override
  State<_VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<_VirtualJoystick> {
  Offset _pos = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.size / 2;
    final knobRadius = 28.0;

    return GestureDetector(
      onPanStart: (d) {
        _dragging = true;
        _updatePosition(d.localPosition, radius);
      },
      onPanUpdate: (d) => _updatePosition(d.localPosition, radius),
      onPanEnd: (_) {
        _dragging = false;
        setState(() => _pos = Offset.zero);
        widget.onEnd();
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(
            cs: cs,
            pos: _pos,
            radius: radius,
            knobRadius: knobRadius,
            dragging: _dragging,
          ),
        ),
      ),
    );
  }

  void _updatePosition(Offset local, double radius) {
    final center = Offset(radius, radius);
    var delta = local - center;
    final maxR = radius - 28;
    if (delta.distance > maxR) {
      delta = delta / delta.distance * maxR;
    }
    setState(() => _pos = delta);
    widget.onChanged(
      (delta.dx / maxR).clamp(-1.0, 1.0),
      -(delta.dy / maxR).clamp(-1.0, 1.0), // Invert Y for forward
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final ColorScheme cs;
  final Offset pos;
  final double radius;
  final double knobRadius;
  final bool dragging;

  _JoystickPainter({
    required this.cs,
    required this.pos,
    required this.radius,
    required this.knobRadius,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(radius, radius);

    // Background circle
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = cs.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = cs.outline.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Cross lines
    final linePaint = Paint()
      ..color = cs.outline.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(radius, 4), Offset(radius, size.height - 4), linePaint);
    canvas.drawLine(Offset(4, radius), Offset(size.width - 4, radius), linePaint);

    // Knob
    final knobCenter = center + pos;
    if (dragging) {
      canvas.drawCircle(
        knobCenter,
        knobRadius + 4,
        Paint()..color = cs.primary.withValues(alpha: 0.1),
      );
    }
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..color = dragging ? cs.primary : cs.onSurface.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..color = cs.outline.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.pos != pos || old.dragging != dragging;
}

// --- Control widgets ---

class _ControlToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool>? onChanged;
  const _ControlToggle({required this.label, required this.value, required this.activeColor, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: tt.titleMedium),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
        ),
      ],
    );
  }
}

class _BehaviorButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;
  const _BehaviorButton({required this.label, required this.icon, required this.color, required this.isActive, this.onTap});

  @override
  State<_BehaviorButton> createState() => _BehaviorButtonState();
}

class _BehaviorButtonState extends State<_BehaviorButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.color.withValues(alpha: 0.15)
                : _hovered
                    ? cs.onSurface.withValues(alpha: 0.05)
                    : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isActive ? widget.color : cs.outline,
              width: widget.isActive ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: enabled ? widget.color : cs.onSurface.withValues(alpha: 0.2), size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
