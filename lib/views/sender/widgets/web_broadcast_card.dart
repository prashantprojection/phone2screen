import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/stream_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../providers/session_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../shared/error_banner.dart';
import '../../shared/video_stage_widget.dart';
import 'active_sender_controls.dart';

/// Lobby screen while Sender hosts `/obs` Clean Feed and interactive web viewer
/// so OBS Studio or any browser on Wi-Fi can open/scan and watch live.
class const WebBroadcastLobbyView({super.key, required final SessionState session})
    extends ConsumerWidget {
  String _buildObsUrl(String baseUrl, {required bool requiresPin, required String pin}) {
    if (baseUrl.isEmpty) return '';
    final obsBase = '$baseUrl${StreamConstants.obsCleanFeedPath}';
    if (requiresPin && pin.isNotEmpty) {
      return '$obsBase?pin=${Uri.encodeComponent(pin)}';
    }
    return obsBase;
  }

  Future<void> _copyUrl(BuildContext context, String label, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $label')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpoint = session.activeEndpoint;
    final url = endpoint?.browserUrl ?? '';
    final pin = ref.watch(appSettingsProvider).pin.trim();
    final obsUrl = _buildObsUrl(
      url,
      requiresPin: endpoint?.requiresPin ?? false,
      pin: pin,
    );
    final isWide = context.isExpanded;

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
                child: isWide
                    ? Row(
                        crossAxisAlignment: .stretch,
                        spacing: 20,
                        children: [
                          Expanded(flex: 5, child: _buildInfoCard(context, url, obsUrl)),
                          Expanded(
                            flex: 6,
                            child: _PreviewStage(
                              stream: session.localStream,
                              overlayControls: const ActiveSenderControls(),
                            ),
                          ),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final infoCard = _buildInfoCard(context, url, obsUrl);
                          final stage = _PreviewStage(stream: session.localStream);
                          if (constraints.maxHeight < 560) {
                            return SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: .stretch,
                                spacing: 12,
                                children: [infoCard, SizedBox(height: 220, child: stage), const ActiveSenderControls()],
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: .stretch,
                            spacing: 12,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.56),
                                child: infoCard,
                              ),
                              Expanded(child: stage),
                              const ActiveSenderControls(),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String url, String obsUrl) {
    final qrSize = context.isCompact ? 128.0 : 164.0;

    return Card(
      child: SingleChildScrollView(
        padding: .all(context.isCompact ? 14 : 20),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Center(
              child: Container(
                padding: const .symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.12),
                  borderRadius: .circular(999),
                ),
                child: const Row(
                  mainAxisSize: .min,
                  spacing: 6,
                  children: [
                    Icon(Icons.public_rounded, size: 15, color: AppColors.accentGreen),
                    Flexible(
                      child: Text(
                        'Ready for Browser Viewer',
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(color: AppColors.accentGreen, fontSize: 12, fontWeight: .w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (url.isNotEmpty)
              Center(
                child: Container(
                  padding: const .all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: .circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.12), blurRadius: 16)],
                  ),
                  child: QrImageView(data: url, size: qrSize, backgroundColor: Colors.white),
                ),
              ),
            _CopyLinkCard(
              title: 'OBS Browser Source (Clean Feed)',
              badge: 'OBS',
              subtitle: 'Zero-UI full-bleed feed with auto-reconnect',
              url: obsUrl,
              accent: const Color(0xFF8B5CF6),
              secondaryAccent: AppColors.cyanAccent,
              icon: Icons.live_tv_rounded,
              onCopy: obsUrl.isEmpty ? null : () => _copyUrl(context, 'OBS Browser Source link', obsUrl),
            ),
            _CopyLinkCard(
              title: 'Interactive Web Viewer',
              subtitle: 'Open in any browser on Wi-Fi or scan QR above',
              url: url,
              accent: Theme.of(context).colorScheme.primary,
              icon: Icons.open_in_browser_rounded,
              onCopy: url.isEmpty ? null : () => _copyUrl(context, 'browser link', url),
            ),
          ],
        ),
      ),
    );
  }
}

class const _CopyLinkCard({
  required final String title,
  final String? badge,
  required final String subtitle,
  required final String url,
  required final Color accent,
  final Color? secondaryAccent,
  required final IconData icon,
  required final VoidCallback? onCopy,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final badgeAccent = secondaryAccent ?? accent;

    return Material(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: .circular(14),
        side: BorderSide(color: url.isNotEmpty ? accent.withValues(alpha: 0.35) : colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onCopy,
        child: Padding(
          padding: const .symmetric(horizontal: 14, vertical: 11),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Row(
                spacing: 8,
                children: [
                  Container(
                    padding: const .all(5),
                    decoration: BoxDecoration(color: badgeAccent.withValues(alpha: 0.14), borderRadius: .circular(8)),
                    child: Icon(icon, size: 15, color: badgeAccent),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: .w700),
                    ),
                  ),
                  if (badge case final badgeText?)
                    Container(
                      padding: const .symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [accent, badgeAccent]),
                        borderRadius: .circular(999),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: .w800),
                      ),
                    ),
                ],
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, fontSize: 11),
              ),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      url.isEmpty ? '--' : url,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: badgeAccent, fontWeight: .w700),
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 16, color: badgeAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _PreviewStage({
  required final MediaStream? stream,
  final Widget? overlayControls,
}) extends StatelessWidget {
  Widget _stageScrim({required bool top}) => Positioned(
    top: top ? 0 : null,
    bottom: top ? null : 0,
    left: 0,
    right: 0,
    height: top ? 60 : 92,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.50), Colors.transparent],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: .circular(20),
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: .expand,
        children: [
          Positioned.fill(
            child: VideoStageWidget(stream: stream, borderRadius: 0, waitingLabel: 'Starting camera or screen...'),
          ),
          _stageScrim(top: true),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const .symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF14161A).withValues(alpha: 0.80),
                borderRadius: .circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                mainAxisSize: .min,
                spacing: 6,
                children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.cyanAccent, shape: .circle)),
                  const Text('Live Preview', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: .w600)),
                ],
              ),
            ),
          ),
          if (overlayControls case final controls?) ...[
            _stageScrim(top: false),
            Positioned(left: 14, right: 14, bottom: 14, child: controls),
          ],
        ],
      ),
    ),
  );
}
