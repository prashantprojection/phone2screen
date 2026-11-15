import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/signaling_data.dart';

/// Receiver pairing card with status pills, encrypted QR code, and 3-step guide.
class const QrPairingCard({super.key, required final SignalingData endpoint})
    extends StatefulWidget {
  @override
  State<QrPairingCard> createState() => _QrPairingCardState();
}

class _QrPairingCardState extends State<QrPairingCard> {
  // Cache the encrypted token because a random 12-byte nonce would otherwise
  // regenerate the QR matrix and flicker on unrelated parent rebuilds.
  late String _qrData = widget.endpoint.toQrString();

  @override
  void didUpdateWidget(covariant QrPairingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _qrData = widget.endpoint.toQrString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final endpoint = widget.endpoint;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const .all(20),
        child: Column(
          crossAxisAlignment: .center,
          spacing: 16,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: .spaceBetween,
                crossAxisAlignment: .center,
                children: [
                  const _ReadyWifiPill(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: .center,
                    children: [
                      _SubtlePill(
                        icon: Icons.wifi_rounded,
                        label: endpoint.ip,
                        color: colors.onSurfaceVariant,
                        bgColor: colors.surfaceContainer,
                        borderColor: colors.outlineVariant,
                      ),
                      if (endpoint.requiresPin)
                        _SubtlePill(
                          icon: Icons.lock_rounded,
                          label: 'PIN',
                          color: AppColors.accentOrange,
                          bgColor: AppColors.accentOrange.withValues(alpha: 0.14),
                          borderColor: AppColors.accentOrange.withValues(alpha: 0.35),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: .min,
              spacing: 10,
              children: [
                Container(
                  padding: const .all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: .circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.20),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: AppColors.cyanAccent.withValues(alpha: 0.12),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    key: ValueKey(_qrData),
                    data: _qrData,
                    size: 196,
                    backgroundColor: Colors.white,
                  ),
                ),
                _SubtlePill(
                  icon: Icons.enhanced_encryption_rounded,
                  label: 'Encrypted • App-Only QR',
                  color: AppColors.primaryBlue,
                  bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderColor: AppColors.primaryBlue.withValues(alpha: 0.35),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const .symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainer.withValues(alpha: 0.65),
                borderRadius: .circular(12),
              ),
              child: const Column(
                crossAxisAlignment: .start,
                spacing: 8,
                children: [
                  _ConnectStepRow(
                    icon: Icons.wifi_rounded,
                    text: '1. Connect both to same Wi-Fi',
                  ),
                  _ConnectStepRow(
                    icon: Icons.smartphone_rounded,
                    text: '2. Open Send tab on phone',
                  ),
                  _ConnectStepRow(
                    icon: Icons.qr_code_scanner_rounded,
                    text: '3. Tap this screen or scan in Phone2Screen',
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

class const _ReadyWifiPill() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.14),
        borderRadius: .circular(999),
        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 7,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accentGreen,
              shape: .circle,
            ),
          ),
          const Text(
            'Ready • Same Wi-Fi',
            style: TextStyle(
              color: AppColors.accentGreen,
              fontSize: 12,
              fontWeight: .w600,
            ),
          ),
        ],
      ),
    );
  }
}

class const _SubtlePill({
  required final IconData icon,
  required final String label,
  required final Color color,
  required final Color bgColor,
  required final Color borderColor,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const .symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: .circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 5,
        children: [
          Icon(icon, size: 13, color: color),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: .w600),
            ),
          ),
        ],
      ),
    );
  }
}

class const _ConnectStepRow({
  required final IconData icon,
  required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      spacing: 10,
      children: [
        Icon(icon, size: 16, color: colors.primary),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface,
              fontWeight: .w600,
            ),
          ),
        ),
      ],
    );
  }
}
