import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared furniture for the Kelola Data pages: the title block, the panel
/// surface, the counter tile and the neutral empty/error state. Kept in one
/// place so the three pages stay visually identical without copy-paste — they
/// differ in data, not in chrome.

BoxDecoration consolePanel({bool subtle = false}) => BoxDecoration(
      color: subtle
          ? AppTheme.panel.withValues(alpha: 0.35)
          : AppTheme.panel.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: subtle
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.10),
      ),
      boxShadow: subtle ? null : AppTheme.softShadow(0.12),
    );

/// Page title + one line of context, with optional icon, badge, and right-aligned controls.
class ConsoleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final String? badgeText;
  final List<Widget> actions;

  const ConsoleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.badgeText,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.brandGold.withValues(alpha: 0.20),
                    AppTheme.brandGold.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.brandGold.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(icon, color: AppTheme.brandGold, size: 22),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (badgeText != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.brandGold.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          badgeText!,
                          style: const TextStyle(
                            color: AppTheme.brandGold,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One counter from a board summary. [tone] carries the meaning: gold for a
/// neutral total, green for finished, amber for still-open.
class StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color tone;
  final IconData? icon;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tone),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: tone,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.mutedStrong,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Centred icon + message. Used for "nothing here", "still loading" and
/// "it failed" alike, so those three never render as three different shapes.
class ConsoleMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? tone;
  final Widget? action;

  const ConsoleMessage({
    super.key,
    required this.icon,
    required this.text,
    this.tone,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppTheme.muted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 34, color: color),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Small status word (plan status, guest type) as a tinted pill.
class ConsolePill extends StatelessWidget {
  final String text;
  final Color tone;

  const ConsolePill({super.key, required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tone,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Refresh control shared by all three boards.
class ConsoleRefreshButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  final String label;

  const ConsoleRefreshButton({
    super.key,
    required this.busy,
    required this.onPressed,
    this.label = 'Muat Ulang',
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.muted,
              ),
            )
          : const Icon(Icons.refresh, size: 18),
      label: Text(busy ? 'Memuat…' : label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.fg,
        side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

/// Visit-plan status in the operator's language. Unknown values are shown raw
/// rather than mapped to a guess — a status this build doesn't know about is
/// worth seeing verbatim, not hidden behind a wrong label.
String planStatusLabel(String status) => switch (status) {
      'planned' => 'Rencana',
      'checked_in' => 'Di area',
      'signed' => 'Sudah tanda tangan',
      'checked_out' => 'Sudah keluar',
      'expired' => 'Dibatalkan',
      _ => status,
    };

/// 'bongkar' | 'muat' | 'bongkar_muat' dalam bahasa operator. Nilai tak
/// dikenal (mis. sebelum kolomnya ada) tampil apa adanya, sama seperti
/// [planStatusLabel].
String loadTypeLabel(String loadType) => switch (loadType) {
      'bongkar' => 'Bongkar',
      'muat' => 'Muat',
      'bongkar_muat' => 'Bongkar & Muat',
      _ => loadType,
    };

Color planStatusTone(String status) => switch (status) {
      'planned' => AppTheme.accent,
      'checked_in' => AppTheme.brandGold,
      'signed' => AppTheme.brandGold,
      'checked_out' => AppTheme.okGreen,
      'expired' => AppTheme.muted,
      _ => AppTheme.muted,
    };

/// `HH:mm` for a board cell, or an em dash when the event has not happened.
String hhmm(DateTime? dt) => dt == null
    ? '—'
    : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// `dd/MM/yyyy HH:mm`, for detail panes where the day matters too.
String dateTimeLabel(DateTime? dt) => dt == null
    ? '—'
    : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${hhmm(dt)}';
