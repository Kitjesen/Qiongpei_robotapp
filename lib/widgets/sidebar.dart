import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NavItem {
  final IconData icon; final IconData activeIcon; final String label;
  const NavItem(this.icon, this.activeIcon, this.label);
}

const List<NavItem> navItems = [
  NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Dashboard'),
  NavItem(Icons.monitor_heart_outlined, Icons.monitor_heart_rounded, 'Monitor'),
  NavItem(Icons.gamepad_outlined, Icons.gamepad_rounded, 'Control'),
  NavItem(Icons.tune_outlined, Icons.tune_rounded, 'Params'),
  NavItem(Icons.terminal_outlined, Icons.terminal_rounded, 'Protocol'),
];

class Sidebar extends StatelessWidget {
  final int selectedIndex; final ValueChanged<int> onSelect;
  final bool isDark; final VoidCallback onToggleTheme;
  final bool isConnected; final String connectionInfo;
  final double textScale; final VoidCallback onScaleUp; final VoidCallback onScaleDown;
  final BrandColor brandColor; final ValueChanged<BrandColor> onChangeBrandColor;

  const Sidebar({super.key, required this.selectedIndex, required this.onSelect, required this.isDark, required this.onToggleTheme, required this.isConnected, required this.connectionInfo, required this.textScale, required this.onScaleUp, required this.onScaleDown, required this.brandColor, required this.onChangeBrandColor});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = brandColor.color;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 72,
          decoration: BoxDecoration(
            color: (dark ? Colors.black : Colors.white).withValues(alpha: dark ? 0.25 : 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
          ),
          child: Column(children: [
            const SizedBox(height: 16),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Icon(Icons.smart_toy_rounded, size: 20, color: Colors.white)),
            ),
            const SizedBox(height: 20),
            ...List.generate(navItems.length, (i) => _NavItem(item: navItems[i], sel: i == selectedIndex, onTap: () => onSelect(i), brand: brand)),
            const Spacer(),
            // Color palette
            _ColorPalette(current: brandColor, onSelect: onChangeBrandColor),
            const SizedBox(height: 10),
            // Theme toggle
            _HoverIcon(icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, onTap: onToggleTheme, brand: brand),
            const SizedBox(height: 10),
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? AppTheme.green : AppTheme.red,
                boxShadow: [BoxShadow(color: (isConnected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.4), blurRadius: 6)],
              ),
            ),
            const SizedBox(height: 14),
          ]),
        ),
      ),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  final BrandColor current;
  final ValueChanged<BrandColor> onSelect;
  const _ColorPalette({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: BrandColor.values.map((c) {
        final sel = c == current;
        return GestureDetector(
          onTap: () => onSelect(c),
          child: Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: c.color,
              shape: BoxShape.circle,
              border: sel ? Border.all(color: Colors.white, width: 2) : null,
              boxShadow: sel ? [BoxShadow(color: c.color.withValues(alpha: 0.5), blurRadius: 4)] : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NavItem extends StatefulWidget {
  final NavItem item; final bool sel; final VoidCallback onTap; final Color brand;
  const _NavItem({required this.item, required this.sel, required this.onTap, required this.brand});
  @override State<_NavItem> createState() => _NavItemState();
}
class _NavItemState extends State<_NavItem> {
  bool _hov = false; bool _press = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.sel;
    final b = widget.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() => _hov = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _press = true),
          onTapUp: (_) => setState(() => _press = false),
          onTapCancel: () => setState(() => _press = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56, height: 52,
            transform: _press ? (Matrix4.identity()..scale(0.92)) : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: s ? b.withValues(alpha: 0.12) : _hov ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(s ? widget.item.activeIcon : widget.item.icon, size: 20, color: s ? b : _hov ? cs.onSurface.withValues(alpha: 0.65) : cs.onSurface.withValues(alpha: 0.3)),
                const SizedBox(height: 3),
                Text(widget.item.label, style: TextStyle(fontSize: 9, fontWeight: s ? FontWeight.w700 : FontWeight.w500, color: s ? b : _hov ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface.withValues(alpha: 0.28))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverIcon extends StatefulWidget {
  final IconData icon; final VoidCallback onTap; final Color brand;
  const _HoverIcon({required this.icon, required this.onTap, required this.brand});
  @override State<_HoverIcon> createState() => _HoverIconState();
}
class _HoverIconState extends State<_HoverIcon> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: _hov ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Icon(widget.icon, size: 18, color: _hov ? widget.brand : cs.onSurface.withValues(alpha: 0.25)),
        ),
      ),
    );
  }
}
