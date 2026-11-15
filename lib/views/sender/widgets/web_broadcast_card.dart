import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/session_provider.dart';
import '../../shared/error_banner.dart';
import '../../shared/video_stage_widget.dart';
import 'active_sender_controls.dart';

/// Lobby screen while Sender hosts an HTTP web page so any browser on Wi-Fi
/// can open or scan the QR URL and watch this device's camera/screen stream.
class const WebBroadcastLobbyView({super.key, required final SessionState session})
    extends ConsumerWidget {
  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied browser link')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = session.activeEndpoint?.browserUrl ?? '';
    final stagePanel = _PreviewStage(stream: session.localStream);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: Padding(
          padding: .all(context.isCompact ? 14 : 20),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 14,
            children: [
              if (session.errorMessage != null)
                ErrorBanner(
                  message: session.errorMessage!,
                  onDismiss: () => ref.read(sessionProvider.notifier).clearError(),
                ),
              Expanded(
                child: context.isExpanded
                    ? Row(
                        crossAxisAlignment: .stretch,
                        spacing: 20,
                        children: [
                          Expanded(flex: 5, child: _buildInfoCard(context, url)),
                          Expanded(flex: 6, child: stagePanel),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final infoCard = _buildInfoCard(context, url);
                          if (constraints.maxHeight < 560) {
                            return SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: .stretch,
                                spacing: 12,
                                children: [infoCard, SizedBox(height: 220, child: stagePanel)],
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: .stretch,
                            spacing: 12,
                            children: [
                              ConstrainedBox(constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.62), child: infoCard),
                              Expanded(child: stagePanel),
                            ],
                          );
                        },
                      ),
              ),
              const ActiveSenderControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String url) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final qrSize = context.isCompact ? 138.0 : 180.0;

    return Card(
      child: SingleChildScrollView(
        padding: .all(context.isCompact ? 14 : 20),
        child: Column(
          crossAxisAlignment: .center,
          spacing: 12,
          children: [
            Container(
              padding: const .symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.14),
                borderRadius: .circular(999),
                border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Icon(Icons.public_rounded, size: 15, color: AppColors.accentGreen),
                  Text('Ready for Browser Viewer', style: TextStyle(color: AppColors.accentGreen, fontSize: 12, fontWeight: .w700)),
                ],
              ),
            ),
            if (url.isNotEmpty)
              Container(
                padding: const .all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: .circular(16),
                  boxShadow: [BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.12), blurRadius: 16)],
                ),
                child: QrImageView(data: url, size: qrSize, backgroundColor: Colors.white),
              ),
            Container(
              width: double.infinity,
              padding: const .all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: .circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: const Column(
                crossAxisAlignment: .start,
                spacing: 7,
                children: [
                  _GuideStepRow(icon: Icons.wifi_rounded, text: '1. Open any browser on the same Wi-Fi'),
                  _GuideStepRow(icon: Icons.qr_code_scanner_rounded, text: '2. Scan the QR code or visit this link:'),
                ],
              ),
            ),
            Material(
              color: colors.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: .circular(12),
                side: BorderSide(color: url.isNotEmpty ? colors.primary.withValues(alpha: 0.35) : colors.outlineVariant),
              ),
              clipBehavior: .antiAlias,
              child: InkWell(
                onTap: url.isEmpty ? null : () => _copyUrl(context, url),
                child: Padding(
                  padding: const .symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Text(
                          url.isEmpty ? '--' : url,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.primary, fontWeight: .w700),
                        ),
                      ),
                      Icon(Icons.copy_rounded, size: 17, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _PreviewStage({required final MediaStream? stream}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: VideoStageWidget(stream: stream, waitingLabel: 'Starting camera or screen...')),
      Positioned(
        top: 12,
        left: 12,
        child: Container(
          padding: const .symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark.withValues(alpha: 0.72),
            borderRadius: .circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.cyanAccent, shape: .circle)),
              const Text('Live Preview', style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 12, fontWeight: .w600)),
            ],
          ),
        ),
      ),
    ],
  );
}

class const _GuideStepRow({required final IconData icon, required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      spacing: 9,
      children: [
        Icon(icon, size: 16, color: colors.primary),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface, fontWeight: .w600))),
      ],
    );
  }
}
