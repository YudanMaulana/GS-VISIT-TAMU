import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';
import '../widgets/guest_avatar.dart';

/// Tamu di Area — papan tamu hari ini beserta progres 6 langkahnya.
///
/// Seluruh angka (langkah saat ini, kolom yang belum terisi, counter ringkasan)
/// dihitung di server (`active_guest_service`), bukan di sini. Itu disengaja:
/// aplikasi E-Patrol membaca papan yang sama, jadi keduanya tidak mungkin
/// berbeda pendapat soal "sudah sampai langkah berapa tamu ini".
/// Papan orang yang sedang di area. Melayani dua jenis pengunjung lewat
/// [kind]: tamu dan transporter.
///
/// Satu halaman untuk keduanya, bukan dua salinan: sumber datanya sama
/// (`/api/active-guests/today`), progres enam langkahnya sama, dan penyaringan
/// hari/cabangnya sama. Yang berbeda hanya baris mana yang ditampilkan dan
/// keterangan tambahan di tiap baris — menggandakan halamannya berarti dua
/// papan yang pelan-pelan berbeda perilaku untuk pertanyaan yang sama.
enum BoardKind {
  tamu('tamu', 'Tamu di Area', 'Papan tamu beserta progres 6 langkahnya'),
  transporter('transporter', 'Transporter di Area',
      'Papan sopir bongkar muat: plat, SIM, dan muatannya');

  const BoardKind(this.visitorType, this.title, this.subtitle);

  final String visitorType;
  final String title;
  final String subtitle;
}

class AreaGuestsPage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;
  final BoardKind kind;

  const AreaGuestsPage({
    super.key,
    required this.client,
    required this.config,
    this.kind = BoardKind.tamu,
  });

  @override
  State<AreaGuestsPage> createState() => _AreaGuestsPageState();
}

class _AreaGuestsPageState extends State<AreaGuestsPage> {
  ActiveGuestBoard? _board;
  bool _loading = false;
  String? _error;
  DateTime _day = DateTime.now();
  bool _thisBranchOnly = true;
  bool _onSiteOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The server treats an omitted `date` as its own local today. Send one only
  /// when the operator actually picked a past day, so a PC with a wrong clock
  /// can't silently shift the board off today.
  String? get _dateParam {
    final now = DateTime.now();
    final sameDay =
        _day.year == now.year && _day.month == now.month && _day.day == now.day;
    return sameDay ? null : _ymd(_day);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? get _branchFilter =>
      _thisBranchOnly ? widget.config.branchId : null;

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
      final board = await client.activeGuests(
        branchId: _branchFilter,
        date: _dateParam,
      );
      if (!mounted) return;
      setState(() => _board = board);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal papan tamu',
      builder: (context, child) => Theme(
        data: AppTheme.dark(),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    await _load();
  }

  List<ActiveGuestRow> get _rows {
    final all = _board?.guests ?? const <ActiveGuestRow>[];
    // Transporter disaring ke papannya sendiri, dan sisanya (tamu, magang,
    // vendor) tinggal di papan tamu. Dibalik -- menyaring "hanya tamu" --
    // akan menyembunyikan magang dan vendor dari kedua papan sekaligus.
    final sesuai = [
      for (final g in all)
        if (widget.kind == BoardKind.transporter ? g.isTransporter : !g.isTransporter)
          g,
    ];
    if (widget.kind == BoardKind.transporter) {
      sesuai.sort((a, b) {
        if (a.dibatalkan != b.dibatalkan) return a.dibatalkan ? 1 : -1;
        if (a.onSite != b.onSite) return a.onSite ? -1 : 1;
        return a.queueNumber.compareTo(b.queueNumber);
      });
    }
    return _onSiteOnly ? [for (final g in sesuai) if (g.onSite) g] : sesuai;
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: widget.kind.title,
            subtitle: board == null
                ? widget.kind.subtitle
                : 'Papan tanggal ${board.date} — progres dihitung server, '
                    'sama dengan yang dibaca E-Patrol',
            icon: widget.kind == BoardKind.transporter
                ? Icons.local_shipping_outlined
                : Icons.meeting_room_outlined,
            actions: [ConsoleRefreshButton(busy: _loading, onPressed: _load)],
          ),
          const SizedBox(height: 16),
          _filterBar(),
          const SizedBox(height: 14),
          if (board != null) ...[
            _summary(board),
            const SizedBox(height: 14),
          ],
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
    final branchName = widget.config.branchName;
    final hasBranch = widget.config.branchId != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _pickDay,
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(_dateParam == null ? 'Hari ini' : _ymd(_day)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.fg,
            side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.4)),
          ),
        ),
        if (_dateParam != null)
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    setState(() => _day = DateTime.now());
                    _load();
                  },
            child: const Text('Kembali ke hari ini'),
          ),
        // Without a configured branch there is nothing to narrow to, so the
        // toggle would be a lie -- it is hidden rather than shown inert.
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
          label: const Text('Masih di area', style: TextStyle(fontSize: 12)),
          selected: _onSiteOnly,
          onSelected: (v) => setState(() => _onSiteOnly = v),
          selectedColor: AppTheme.brandGold.withValues(alpha: 0.22),
          checkmarkColor: AppTheme.brandGold,
          backgroundColor: AppTheme.panelAlt.withValues(alpha: 0.5),
          labelStyle: const TextStyle(color: AppTheme.fg),
          side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.3)),
        ),
      ],
    );
  }

  Widget _summary(ActiveGuestBoard b) {
    final isTransporter = widget.kind == BoardKind.transporter;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        StatTile(
          label: isTransporter ? 'Total armada' : 'Total tamu',
          value: b.total,
          tone: AppTheme.brandGold,
          icon: isTransporter ? Icons.local_shipping_outlined : Icons.groups_outlined,
        ),
        StatTile(
          label: 'Masih di area',
          value: b.notCheckedOut,
          tone: AppTheme.warnAmber,
          icon: Icons.meeting_room_outlined,
        ),
        StatTile(
          label: 'Sudah keluar',
          value: b.checkedOut,
          tone: AppTheme.okGreen,
          icon: Icons.check_circle_outline,
        ),
        StatTile(
          label: isTransporter ? 'Muatan tercatat' : 'Form lengkap',
          value: b.formComplete,
          tone: AppTheme.accent,
          icon: Icons.fact_check_outlined,
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
    if (_board == null) {
      return const ConsoleMessage(
        icon: Icons.hourglass_top,
        text: 'Memuat papan tamu…',
      );
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return ConsoleMessage(
        icon: Icons.meeting_room_outlined,
        text: _onSiteOnly
            ? 'Tidak ada tamu yang masih berada di area.'
            : 'Belum ada tamu pada tanggal ini.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AppTheme.panelAlt, height: 1),
      itemBuilder: (_, i) => _guestRow(rows[i]),
    );
  }

  Widget _guestRow(ActiveGuestRow g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuestAvatar(
            client: widget.client,
            photoUrl: g.photoUrl,
            name: g.name,
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
                        g.name.isEmpty ? '(tanpa nama)' : g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (g.isTransporter) ...[
                      ConsolePill(
                        text: 'Antrean #${g.queueNumber}',
                        tone: AppTheme.brandGold,
                      ),
                      const SizedBox(width: 6),
                    ],
                    ConsolePill(
                      text: planStatusLabel(g.status),
                      tone: planStatusTone(g.status),
                    ),
                    if (g.isTransporter && g.vehiclePlate.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ConsolePill(text: g.vehiclePlate, tone: AppTheme.accent),
                    ],
                    if (g.isTransporter && g.loadType.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ConsolePill(
                        text: loadTypeLabel(g.loadType),
                        tone: AppTheme.brandGold,
                      ),
                    ],
                    if (g.simExpired) ...[
                      const SizedBox(width: 6),
                      // Ditandai, bukan disembunyikan: menahan truk itu
                      // keputusan petugas, dan ia hanya bisa memutuskan kalau
                      // barisnya terlihat.
                      const ConsolePill(text: 'SIM KEDALUWARSA', tone: AppTheme.badRed),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (g.company.isNotEmpty) g.company,
                    if (!g.isTransporter && g.picTarget.isNotEmpty)
                      'PIC: ${g.picTarget}',
                    if (!g.isTransporter && g.purpose.isNotEmpty) g.purpose,
                    if (g.isTransporter && g.vehicleType.isNotEmpty)
                      g.vehicleType,
                    if (g.isTransporter && g.loadCount > 0)
                      '${g.loadCount} muatan'
                          '${g.firstShipmentNo.isNotEmpty ? ' · SI ${g.firstShipmentNo}' : ''}',
                    if (g.isTransporter && g.simExpiresAt.isNotEmpty)
                      'SIM s/d ${g.simExpiresAt}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                ),
                if (g.missingFields.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Belum terisi: ${g.missingFields.join(', ')}',
                    style: const TextStyle(
                      color: AppTheme.warnAmber,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _stepBar(g)),
          const SizedBox(width: 12),
          SizedBox(width: 108, child: _times(g)),
        ],
      ),
    );
  }

  /// Six pips: filled up to `current_step`. Deliberately not a percentage —
  /// the server counts discrete steps, and rounding them into a bar would
  /// invent precision the data does not have.
  Widget _stepBar(ActiveGuestRow g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var s = 1; s <= 6; s++) ...[
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: s <= g.currentStep
                        ? (g.checkoutComplete
                            ? AppTheme.okGreen
                            : AppTheme.brandGold)
                        : AppTheme.panelAlt,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (s < 6) const SizedBox(width: 3),
            ],
          ],
        ),
        const SizedBox(height: 5),
        // Deliberately NOT keyed off `form_complete`: the server defines that
        // as "nothing missing *and* already checked in", so every still-waiting
        // guest has it false even with a perfectly complete form. The gap worth
        // showing is `missing_fields`, which is rendered above.
        Text(
          'Langkah ${g.currentStep}/6 · ${planStatusLabel(g.status)}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _times(ActiveGuestRow g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Masuk ${hhmm(g.checkinAt)}',
          style: const TextStyle(color: AppTheme.fg, fontSize: 11.5),
        ),
        Text(
          'Keluar ${hhmm(g.checkoutAt)}',
          style: TextStyle(
            color: g.onSite ? AppTheme.warnAmber : AppTheme.muted,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
