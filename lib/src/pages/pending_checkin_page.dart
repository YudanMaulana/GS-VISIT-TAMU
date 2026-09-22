import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';
import '../widgets/guest_avatar.dart';

/// Belum Check-in — rencana kunjungan berstatus `planned`: tamu yang sudah
/// mengisi rencana di aplikasi tapi belum melewati gerbang POS.
///
/// Ini kebalikan dari Tamu di Area: yang ditunggu, bukan yang sudah datang.
/// Berguna untuk petugas gerbang ("siapa yang seharusnya datang hari ini")
/// sekaligus menjelaskan kenapa auto check-in menolak seseorang — wajah
/// dikenali saja tidak cukup, rencananya harus ada di daftar ini.
class PendingCheckinPage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  const PendingCheckinPage({
    super.key,
    required this.client,
    required this.config,
  });

  @override
  State<PendingCheckinPage> createState() => _PendingCheckinPageState();
}

class _PendingCheckinPageState extends State<PendingCheckinPage> {
  List<PlanRow> _plans = [];
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  bool _thisBranchOnly = true;
  bool _todayOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await client.visitPlans(
        status: 'planned',
        branchId: _thisBranchOnly ? widget.config.branchId : null,
      );
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool _isToday(DateTime? d) {
    if (d == null) return false;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  List<PlanRow> get _rows =>
      _todayOnly ? [for (final p in _plans) if (_isToday(p.visitDate)) p] : _plans;

  @override
  Widget build(BuildContext context) {
    final hasBranch = widget.config.branchId != null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Belum Check-in',
            subtitle: 'Rencana kunjungan yang sudah dibuat tamu tapi belum '
                'melewati gerbang POS',
            icon: Icons.pending_actions_outlined,
            actions: [ConsoleRefreshButton(busy: _loading, onPressed: _load)],
          ),
          if (_loaded) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                StatTile(
                  label: _thisBranchOnly && hasBranch
                      ? 'Menunggu di cabang ini'
                      : 'Total menunggu check-in',
                  value: _rows.length,
                  tone: AppTheme.accent,
                  icon: Icons.hourglass_empty,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _filterBar(),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              decoration: consolePanel(subtle: true),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final hasBranch = widget.config.branchId != null;
    final branchName = widget.config.branchName;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasBranch)
          FilterChip(
            label: Text(
              branchName.isEmpty ? 'Cabang POS ini' : branchName,
              style: const TextStyle(fontSize: 12),
            ),
            selected: _thisBranchOnly,
            onSelected: _loading
                ? null
                : (v) {
                    setState(() => _thisBranchOnly = v);
                    _load();
                  },
            selectedColor: AppTheme.brandGold.withValues(alpha: 0.22),
            checkmarkColor: AppTheme.brandGold,
            backgroundColor: AppTheme.panelAlt.withValues(alpha: 0.5),
            labelStyle: const TextStyle(color: AppTheme.fg),
            side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.3)),
          ),
        FilterChip(
          label: const Text(
            'Dijadwalkan hari ini',
            style: TextStyle(fontSize: 12),
          ),
          selected: _todayOnly,
          onSelected: (v) => setState(() => _todayOnly = v),
          selectedColor: AppTheme.brandGold.withValues(alpha: 0.22),
          checkmarkColor: AppTheme.brandGold,
          backgroundColor: AppTheme.panelAlt.withValues(alpha: 0.5),
          labelStyle: const TextStyle(color: AppTheme.fg),
          side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.3)),
        ),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return ConsoleMessage(
        icon: Icons.cloud_off,
        text: _error!,
        tone: AppTheme.badRed,
        action: ConsoleRefreshButton(
          busy: _loading,
          onPressed: _load,
          label: 'Coba Lagi',
        ),
      );
    }
    if (!_loaded) {
      return const ConsoleMessage(
        icon: Icons.hourglass_top,
        text: 'Memuat rencana kunjungan…',
      );
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return ConsoleMessage(
        icon: Icons.done_all,
        text: _todayOnly
            ? 'Tidak ada rencana kunjungan untuk hari ini yang masih menunggu.'
            : 'Tidak ada tamu yang menunggu check-in.',
        tone: AppTheme.okGreen,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AppTheme.panelAlt, height: 1),
      itemBuilder: (_, i) => _planRow(rows[i]),
    );
  }

  Widget _planRow(PlanRow p) {
    final today = _isToday(p.visitDate);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuestAvatar(
            client: widget.client,
            photoUrl: p.photoUrl,
            name: p.visitorName,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.visitorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (today) ...[
                      const SizedBox(width: 8),
                      const ConsolePill(
                        text: 'Hari ini',
                        tone: AppTheme.brandGold,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (p.company.isNotEmpty) p.company,
                    if (p.picTarget.isNotEmpty) 'PIC: ${p.picTarget}',
                    if (p.purpose.isNotEmpty) p.purpose,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              p.branchName.isEmpty ? '—' : p.branchName,
              style: const TextStyle(color: AppTheme.fg, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  p.visitDate == null
                      ? 'Tanggal tidak diisi'
                      : 'Rencana ${_dmy(p.visitDate!)}',
                  style: TextStyle(
                    color: today ? AppTheme.brandGold : AppTheme.fg,
                    fontSize: 11.5,
                    fontWeight: today ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                Text(
                  'Dibuat ${dateTimeLabel(p.createdAt)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
