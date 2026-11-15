import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class const WebBroadcastLobbyView({
  super.key,
  required final SessionState session,
}) extends ConsumerWidget {
  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied browser link')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpoint = session.activeEndpoint;
    final url = endpoint?.browserUrl ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: Padding(
          padding: const .all(16),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
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
                        spacing: 16,
                        children: [
                          Expanded(flex: 5, child: _buildInfoCard(context, url)),
                          Expanded(
                            flex: 6,
                            child: VideoStageWidget(
                              stream: session.localStream,
                              waitingLabel: 'Starting camera or screen...',
                            ),
                          ),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final infoCard = _buildInfoCard(context, url);
                          final stage = VideoStageWidget(
                            stream: session.localStream,
                            waitingLabel: 'Starting camera or screen...',
                          );
                          if (constraints.maxHeight < 520) {
                            return SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: .stretch,
                                spacing: 12,
                                children: [
                                  infoCard,
                                  SizedBox(height: 200, child: stage),
                                ],
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: .stretch,
                            spacing: 12,
                            children: [
                              infoCard,
                              Expanded(child: stage),
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
    final qrSize = context.isCompact ? 136.0 : 168.0;

    return Card(
      child: Padding(
        padding: .all(context.isCompact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .center,
            spacing: 10,
            children: [
              Container(
                padding: const .symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.14),
                  borderRadius: .circular(999),
                  border: Border.all(
                    color: AppColors.accentGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    Icon(Icons.public_rounded, size: 15, color: AppColors.accentGreen),
                    Text(
                      'Ready for Browser Viewer',
                      style: TextStyle(
                        color: AppColors.accentGreen,
                        fontSize: 12,
                        fontWeight: .w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (url.isNotEmpty)
                Container(
                  padding: const .all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: .circular(14),
                  ),
                  child: QrImageView(
                    data: url,
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
              Column(
                spacing: 4,
                children: [
                  Text(
                    '1. Open any browser on the same Wi-Fi',
                    textAlign: .center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: .w600,
                    ),
                  ),
                  Text(
                    '2. Scan the QR code or visit:',
                    textAlign: .center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: url.isEmpty ? null : () => _copyUrl(context, url),
                borderRadius: .circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const .symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: .circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Text(
                          url.isEmpty ? '--' : url,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: .w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.copy_rounded, size: 17),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
