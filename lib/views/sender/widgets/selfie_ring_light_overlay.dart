import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';

/// Selfie screen-edge ring-light illumination modes for dim rooms.
enum SelfieRingLightMode {
  off,
  warm,
  daylight;

  String get label => switch (this) {
    .off => 'Ring Off',
    .warm => 'Warm Ring',
    .daylight => 'Daylight Ring',
  };

  String get shortLabel => switch (this) {
    .off => 'Ring Light',
    .warm => 'Warm Ring',
    .daylight => 'Daylight',
  };

  SelfieRingLightMode get next => switch (this) {
    .off => .warm,
    .warm => .daylight,
    .daylight => .off,
  };
}

/// Non-interactive glowing bezel frame illuminating the user's face in dim rooms.
class const SelfieRingLightOverlay({
  super.key,
  required final SelfieRingLightMode mode,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (mode == .off) return const SizedBox.shrink();
    final color = mode == .warm ? const Color(0xFFFFE4B5) : const Color(0xFFF4F8FF);
    return IgnorePointer(
      child: Stack(
        fit: .expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.0,
                colors: [Colors.transparent, color.withValues(alpha: 0.14), color.withValues(alpha: 0.36)],
                stops: const [0.58, 0.85, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const .all(4),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: .circular(28),
                border: Border.all(color: color.withValues(alpha: 0.90), width: 24),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.48), blurRadius: 28, blurStyle: .outer)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact live connection/tally indicator pill in the Sender HUD.
class const LiveStatusPill({
  super.key,
  required final String label,
  required final Color color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const .symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF14161A).withValues(alpha: 0.80),
      borderRadius: .circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Row(
      mainAxisSize: .min,
      spacing: 7,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: .circle)),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: .ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: .w600),
          ),
        ),
      ],
    ),
  );
}

/// Compact pill toggling true-black OLED Battery Saver tally mode.
class const BatterySaverPill({
  super.key,
  required final bool active,
  required final VoidCallback onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _HudActionPill(
    icon: Icons.battery_saver_rounded,
    label: 'Battery Saver',
    active: active,
    accent: active ? AppColors.accentGreen : Colors.white,
    onTap: onToggle,
  );
}

/// Compact pill cycling [SelfieRingLightMode] on the live camera Sender HUD.
class const RingLightPill({
  super.key,
  required final SelfieRingLightMode mode,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final active = mode != .off;
    final accent = switch (mode) {
      .off => Colors.white,
      .warm => const Color(0xFFFFE4B5),
      .daylight => const Color(0xFFF4F8FF),
    };
    return Tooltip(
      message: 'Selfie Ring-Light: ${mode.label}',
      child: _HudActionPill(
        icon: active ? Icons.light_mode_rounded : Icons.light_mode_outlined,
        label: mode.shortLabel,
        active: active,
        accent: accent,
        onTap: onTap,
      ),
    );
  }
}

class const _HudActionPill({
  required final IconData icon,
  required final String label,
  required final bool active,
  required final Color accent,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF14161A).withValues(alpha: active ? 0.88 : 0.80),
    shape: StadiumBorder(
      side: BorderSide(color: active ? accent.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.14)),
    ),
    clipBehavior: .antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Icon(icon, size: 15, color: accent),
            Text(label, style: TextStyle(color: accent, fontSize: 12, fontWeight: .w600)),
          ],
        ),
      ),
    ),
  );
}
