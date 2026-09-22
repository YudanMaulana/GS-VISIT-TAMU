import 'package:flutter/material.dart';

import '../theme.dart';

/// Desktop top bar: compact brand block, operational status, session pill, and icon tools.
class PosTopBar extends StatelessWidget {
  final String stateLabel;
  final Color stateColor;
  final bool online;
  final bool showDiagnostics;
  final String branchName;
  final String? adminEmail;
  final VoidCallback? onToggleDiagnostics;
  final VoidCallback? onPreview;
  final VoidCallback? onSettings;
  final VoidCallback? onManage;
  final VoidCallback? onLock;

  const PosTopBar({
    super.key,
    required this.stateLabel,
    required this.stateColor,
    required this.online,
    this.showDiagnostics = false,
    this.branchName = '',
    this.adminEmail,
    this.onToggleDiagnostics,
    this.onPreview,
    this.onSettings,
    this.onManage,
    this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 980;
        final veryCompact = width < 760;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppTheme.panelGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: AppTheme.softShadow(0.18),
          ),
          child: Row(
            children: [
              _logoBox(compact),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'GARUDASHIELD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.fg,
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'VISIT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.brandGold,
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.8,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    if (!veryCompact) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Konsol Pengawasan & Akses Tamu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.muted.withValues(alpha: 0.9),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                StatePill(
                  label: online ? 'ONLINE' : 'OFFLINE',
                  color: online ? AppTheme.okGreen : AppTheme.muted,
                  icon: online ? Icons.cloud_done : Icons.cloud_off,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: StatePill(
                    label: branchName.isEmpty
                        ? 'CABANG BELUM DIATUR'
                        : branchName.toUpperCase(),
                    color: branchName.isEmpty
                        ? AppTheme.badRed
                        : AppTheme.accent,
                    icon: Icons.storefront,
                  ),
                ),
                const SizedBox(width: 8),
                StatePill(label: stateLabel, color: stateColor),
                if (adminEmail != null && adminEmail!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _adminPill(adminEmail!),
                ],
                const SizedBox(width: 6),
                Container(
                  height: 28,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ],
              if (onToggleDiagnostics != null) ...[
                _iconButton(
                  tooltip: showDiagnostics
                      ? 'Sembunyikan diagnostik'
                      : 'Tampilkan diagnostik',
                  icon: showDiagnostics
                      ? Icons.insights
                      : Icons.insights_outlined,
                  active: showDiagnostics,
                  onPressed: onToggleDiagnostics,
                ),
                const SizedBox(width: 6),
              ],
              if (onManage != null) ...[
                _iconButton(
                  tooltip: 'Kelola Data',
                  icon: Icons.admin_panel_settings_outlined,
                  active: false,
                  onPressed: onManage,
                ),
                const SizedBox(width: 6),
              ],
              if (onPreview != null) ...[
                _iconButton(
                  tooltip: 'Pratinjau Kamera (Jendela Baru)',
                  icon: Icons.open_in_new,
                  active: false,
                  onPressed: onPreview,
                ),
                const SizedBox(width: 6),
              ],
              if (onSettings != null) ...[
                _iconButton(
                  tooltip: 'Pengaturan Sistem',
                  icon: Icons.settings_outlined,
                  active: false,
                  onPressed: onSettings,
                ),
              ],
              if (onLock != null) ...[
                const SizedBox(width: 6),
                _iconButton(
                  tooltip: 'Kunci Sesi Konsol',
                  icon: Icons.lock_outline,
                  active: false,
                  tone: AppTheme.badRed,
                  onPressed: onLock,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _adminPill(String email) {
    final clean = email.trim();
    final at = clean.indexOf('@');
    final name = at <= 0 ? clean : clean.substring(0, at);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.brandGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.brandGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, size: 13, color: AppTheme.brandGold),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.brandGold,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBox(bool compact) {
    final size = compact ? 42.0 : 48.0;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Image.asset(
        'assets/branding/visit_logo_tight.png',
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required bool active,
    Color? tone,
    VoidCallback? onPressed,
  }) {
    final activeColor = tone ?? AppTheme.brandGold;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: active
              ? activeColor.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.06),
          foregroundColor: active ? activeColor : (tone ?? AppTheme.fg),
          side: BorderSide(
            color: tone != null
                ? tone.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.09),
          ),
          padding: const EdgeInsets.all(9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 17),
        onPressed: onPressed,
      ),
    );
  }
}

/// The totem's pill: transparent fill, translucent coloured border, dot +
/// uppercase letter-spaced label.
class StatePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  /// When the pill lives in a full-width slot and its label can be long (e.g.
  /// a server error message in the visit panel), set this so the text wraps/
  /// ellipsizes within the available width instead of overflowing the row.
  /// Requires a bounded-width parent; the compact top-bar pills leave it off.
  final bool expand;

  const StatePill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: expand ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          expand ? Expanded(child: text) : text,
        ],
      ),
    );
  }
}
