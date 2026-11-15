import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/signaling_data.dart';

/// Studio card showing pairing QR code, pulsing LAN badge, PIN badge, and web URL.
class const QrPairingCard({super.key, required final SignalingData endpoint})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const .all(20),
        child: Column(
          crossAxisAlignment: .center,
          spacing: 14,
          children: [
            Row(
              mainAxisAlignment: .spaceBetween,
              spacing: 8,
              children: [
                const _LanStatusBadge(),
                if (endpoint.requiresPin)
                  Container(
                    padding: const .symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.14),
                      borderRadius: .circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: .min,
                      spacing: 4,
                      children: [
                        Icon(Icons.lock_rounded, size: 13, color: AppColors.accentOrange),
                        Text('PIN', style: TextStyle(color: AppColors.accentOrange, fontSize: 11, fontWeight: .w700)),
                      ],
                    ),
                  ),
              ],
            ),
            Container(
              padding: const .all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: .circular(16),
                boxShadow: [BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.14), blurRadius: 18)],
              ),
              child: QrImageView(data: endpoint.toQrString(), size: 196, backgroundColor: Colors.white),
            ),
            Text('Scan with Phone2Screen', style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w700)),
            Container(
              width: double.infinity,
              padding: const .symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: .circular(10),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text('Browser Web Companion', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  SelectableText(
                    endpoint.browserUrl,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.primary, fontWeight: .w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanStatusBadge extends StatefulWidget {
  const _LanStatusBadge();
  @override
  State<_LanStatusBadge> createState() => _LanStatusBadgeState();
}

class _LanStatusBadgeState extends State<_LanStatusBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const .symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.accentGreen.withValues(alpha: 0.14),
          borderRadius: .circular(999),
          border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
              child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accentGreen, shape: .circle)),
            ),
            const Flexible(
              child: Text(
                'Listening on LAN • UDP 41234',
                overflow: .ellipsis,
                style: TextStyle(color: AppColors.accentGreen, fontSize: 12, fontWeight: .w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
