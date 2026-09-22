import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'top_bar.dart';

/// The POS-facing side panel: who is in front of the camera, and where they are
/// in the visit flow (check-in -> signature -> check-out).
class VisitPanel extends StatelessWidget {
  final DetectionState state;
  final RecognitionResult? lastVisit; // result of the last check-in/out
  final bool signed;
  final bool busy;
  final VoidCallback? onCheckin;
  final VoidCallback? onRefresh;
  final VoidCallback? onCheckout;

  /// Fase 2: server rejects check-in without a branch_id. Kept false-by-default
  /// so a caller that forgets to pass it fails safe (button stays disabled)
  /// rather than silently allowing a check-in the server will reject anyway.
  final bool branchConfigured;

  const VisitPanel({
    super.key,
    required this.state,
    required this.lastVisit,
    required this.signed,
    required this.busy,
    this.onCheckin,
    this.onRefresh,
    this.onCheckout,
    this.branchConfigured = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.panelGradient,
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.brandGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.brandGold.withValues(alpha: 0.30),
                  ),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: AppTheme.brandGold,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KUNJUNGAN',
                      style: TextStyle(
                        color: AppTheme.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Face check-in, form, dan check-out',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _identityCard(),
          const SizedBox(height: 16),
          _steps(),
          const Spacer(),
          _actions(),
        ],
      ),
    );
  }

  Widget _identityCard() {
    final id = state.identity;
    final recognized = id?.recognized == true;
    final color = recognized ? AppTheme.okGreen : AppTheme.muted;
    final name = recognized ? (id!.name ?? '-') : 'Menunggu wajah…';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        boxShadow: AppTheme.softShadow(0.12),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.panelAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: lastVisit?.photo != null
                ? Image.memory(
                    lastVisit!.photo!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                : Icon(
                    recognized ? Icons.person : Icons.person_search,
                    color: AppTheme.muted,
                    size: 26,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (recognized && id!.similarity != null)
                  Text(
                    'Kecocokan ${(id.similarity! * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                if (!recognized && id != null)
                  Text(
                    id.message,
                    maxLines: 2,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatePill(
            label: recognized ? 'VALID' : 'STANDBY',
            color: color,
            icon: recognized ? Icons.check_circle : Icons.radar,
          ),
        ],
      ),
    );
  }

  Widget _steps() {
    final checkedIn =
        lastVisit?.success == true && lastVisit?.mode == 'checkin';
    return Column(
      children: [
        _step(
          1,
          'Check-in wajah (POS)',
          checkedIn,
          checkedIn
              ? (lastVisit?.message ?? '')
              : 'Arahkan wajah lalu tekan Check-in',
        ),
        // Signing/form completion happens on the guest-facing screen; this
        // operator panel only watches for the server-side result.
        _step(
          2,
          'Tanda tangan Tamu + PIC',
          signed,
          signed
              ? 'Sudah ditandatangani dan data tamu lengkap'
              : (checkedIn
                    ? 'Menunggu tamu menyelesaikan data dan tanda tangan...'
                    : 'Dilakukan setelah check-in'),
          waiting: checkedIn && !signed,
        ),
        _step(
          3,
          'Check-out (POS)',
          checkedIn && signed,
          signed ? 'Siap check-out' : 'Terkunci sampai tanda tangan selesai',
        ),
      ],
    );
  }

  Widget _step(
    int n,
    String title,
    bool done,
    String sub, {
    bool waiting = false,
  }) {
    final color = done
        ? AppTheme.okGreen
        : (waiting ? AppTheme.brandGold : AppTheme.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? AppTheme.okGreen.withValues(alpha: 0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: done
                ? const Icon(Icons.check, size: 13, color: AppTheme.okGreen)
                : (waiting
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            valueColor: AlwaysStoppedAnimation(
                              AppTheme.brandGold,
                            ),
                          ),
                        )
                      : Text(
                          '$n',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: done ? AppTheme.fg : AppTheme.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Apa yang baru saja dilakukan (atau tidak dilakukan) auto check-in.
  ///
  /// "Tidak dilakukan" sama pentingnya untuk ditampilkan: kalau gerbang diam
  /// karena tamu belum punya rencana kunjungan, operator harus tahu itu —
  /// kalau tidak, satu-satunya petunjuk adalah tidak terjadi apa-apa.
  Widget _autoCheckinBanner() {
    final r = state.autoCheckinResult;
    if (!state.autoCheckin || r == null) return const SizedBox.shrink();

    final (color, icon) = switch (r.state) {
      'checked_in' || 'checked_out' => (AppTheme.okGreen, Icons.check_circle),
      'no_plan' || 'not_planned' => (AppTheme.muted, Icons.info_outline),
      'too_early' => (AppTheme.brandGold, Icons.schedule),
      _ => (AppTheme.badRed, Icons.error_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StatePill(
        label: r.message.toUpperCase(),
        color: color,
        icon: icon,
        expand: true,
      ),
    );
  }

  Widget _actions() {
    final recognized = state.identity?.recognized == true;
    final checkedIn =
        lastVisit?.success == true && lastVisit?.mode == 'checkin';
    return Column(
      children: [
        _autoCheckinBanner(),
        if (lastVisit != null && !(lastVisit!.success))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StatePill(
              label: lastVisit!.message.toUpperCase(),
              color: AppTheme.badRed,
              icon: Icons.error_outline,
              expand: true,
            ),
          ),
        if (!branchConfigured)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: StatePill(
              label: 'CABANG BELUM DIATUR — BUKA PENGATURAN',
              color: AppTheme.badRed,
              icon: Icons.storefront,
              expand: true,
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (busy || !recognized || !branchConfigured)
                ? null
                : onCheckin,
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Check-in (F1)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandGold,
              foregroundColor: AppTheme.brandBlueDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // No signing button here: the guest-facing screen handles form/signature.
        // This re-reads the visit from the server in case auto-poll is behind.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (busy || !checkedIn) ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(signed ? 'Status: sudah TTD' : 'Cek status TTD (F2)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: signed ? AppTheme.okGreen : AppTheme.fg,
              side: BorderSide(
                color: (signed ? AppTheme.okGreen : AppTheme.muted).withValues(
                  alpha: 0.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            // Checkout is allowed after this POS has a valid check-in visit
            // and the required guest signature/form is complete. We do not
            // require the live "recognized" label here because it can drop for
            // a frame while the guest is still present; the checkout submit
            // still captures a fresh photo and the server remains the face
            // matching authority.
            onPressed: (busy || !checkedIn || !signed) ? null : onCheckout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Check-out (F3)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandBlueBright,
              foregroundColor: AppTheme.fg,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
