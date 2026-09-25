import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

class InternshipAttendancePage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  const InternshipAttendancePage({
    super.key,
    required this.client,
    required this.config,
  });

  @override
  State<InternshipAttendancePage> createState() =>
      _InternshipAttendancePageState();
}

class _InternshipAttendancePageState extends State<InternshipAttendancePage> {
  final _search = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _workStart = TextEditingController(text: '08:00');
  final _workEnd = TextEditingController(text: '16:00');
  final _lat = TextEditingController(text: '-6.955353');
  final _lng = TextEditingController(text: '107.798688');
  final _radius = TextEditingController(text: '50');

  List<InternshipVisitorRow> _visitors = const [];
  List<Branch> _branches = const [];
  InternshipAttendanceDetail? _detail;
  int? _selectedId;
  int? _contractBranchId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  bool _savingContract = false;
  bool _savingPoint = false;
  String? _error;
  String? _notice;
  bool _usingProfileFallback = false;
  bool _attendanceExpanded = true;
  bool _logsExpanded = false;

  static const _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static String _formatMonthLabel(int year, int month) {
    if (month >= 1 && month <= 12) {
      return '${_monthNames[month - 1]} $year';
    }
    return '$year-$month';
  }

  List<({String key, String label})> get _monthOptions {
    final now = DateTime.now();
    final list = <({String key, String label})>[];
    for (var i = 2; i >= -12; i--) {
      final d = DateTime(now.year, now.month + i);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      list.add((key: key, label: _formatMonthLabel(d.year, d.month)));
    }
    if (!list.any((item) => item.key == _monthParam)) {
      list.insert(0, (
        key: _monthParam,
        label: _formatMonthLabel(_month.year, _month.month),
      ));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _start.dispose();
    _end.dispose();
    _workStart.dispose();
    _workEnd.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  InternshipVisitorRow? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final row in _visitors) {
      if (row.id == id) return row;
    }
    return null;
  }

  DateTime? get _contractStartDate {
    final contract = _detail?.contract ?? _selected?.contract;
    if (contract?.startDate != null) return contract!.startDate;
    if (_start.text.trim().isNotEmpty) {
      return DateTime.tryParse(_start.text.trim());
    }
    return null;
  }

  DateTime? get _contractEndDate {
    final contract = _detail?.contract ?? _selected?.contract;
    if (contract?.endDate != null) return contract!.endDate;
    if (_end.text.trim().isNotEmpty) {
      return DateTime.tryParse(_end.text.trim());
    }
    return null;
  }

  int? get _firstBranchId => _branches.isEmpty ? null : _branches.first.id;

  List<InternshipVisitorRow> get _filtered => [
    for (final row in _visitors)
      if (row.matches(_search.text)) row,
  ];

  String get _monthParam =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      var usingProfileFallback = false;
      List<InternshipVisitorRow> visitors;
      try {
        visitors = await client.internshipVisitors();
      } catch (e) {
        if (!_isMissingEndpoint(e)) rethrow;
        usingProfileFallback = true;
        final profiles = await client.visitors();
        visitors = [
          for (final v in profiles)
            if (v.visitorType == 'magang')
              InternshipVisitorRow(
                id: v.id,
                visitorCode: v.visitorCode,
                fullName: v.fullName,
                institutionName: v.institutionName.isNotEmpty
                    ? v.institutionName
                    : v.company,
                major: v.major,
                phone: v.phone,
                email: v.email,
                branchName: '',
                visitorType: v.visitorType,
                company: v.company,
              ),
        ];
      }
      final branchEnvelope = await client.branches();
      final branchBody = branchEnvelope['body'];
      final branchList = branchBody is Map
          ? branchBody['branches'] ?? branchBody['data']
          : branchBody;
      if (!mounted) return;
      setState(() {
        _visitors = visitors;
        _usingProfileFallback = usingProfileFallback;
        _branches = [
          for (final b in (branchList as List? ?? const []))
            if (b is Map) Branch.fromJson(Map<String, dynamic>.from(b)),
        ];
        if (_selectedId != null &&
            !_visitors.any((row) => row.id == _selectedId)) {
          _selectedId = null;
          _detail = null;
        }
      });
      if (_selectedId == null && visitors.isNotEmpty) {
        _select(visitors.first);
      } else if (_selectedId != null) {
        await _loadDetail();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDetail() async {
    final client = widget.client;
    final selected = _selected;
    if (client == null || selected == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_usingProfileFallback) {
        setState(() {
          _detail = InternshipAttendanceDetail(
            visitor: selected,
            contract: selected.contract,
            logs: const [],
          );
          _error =
              'Endpoint admin absensi magang & vendor belum aktif di server publik. '
              'Daftar peserta dibaca dari Semua Profil untuk sementara.';
        });
        return;
      }
      final detail = await client.internshipAttendance(
        visitorId: selected.id,
        month: _monthParam,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _fillContract(detail.contract ?? selected.contract);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(InternshipVisitorRow row) {
    setState(() {
      _selectedId = row.id;
      _detail = null;
      _notice = null;
      _error = null;
      _fillContract(row.contract);
    });
    _loadDetail();
  }

  void _fillContract(InternshipContract? contract) {
    _contractBranchId =
        contract?.branchId ?? widget.config.branchId ?? _firstBranchId;
    _start.text = _ymd(contract?.startDate ?? DateTime.now());
    _end.text = _ymd(
      contract?.endDate ?? DateTime.now().add(const Duration(days: 90)),
    );
    _workStart.text = contract?.workStart ?? '08:00';
    _workEnd.text = contract?.workEnd ?? '16:00';
  }

  Future<void> _saveContract() async {
    final client = widget.client;
    final selected = _selected;
    final branchId = _contractBranchId;
    if (client == null || selected == null || branchId == null) return;
    setState(() {
      _savingContract = true;
      _error = null;
      _notice = null;
    });
    try {
      await client.saveInternshipContract(
        visitorId: selected.id,
        branchId: branchId,
        startDate: _start.text.trim(),
        endDate: _end.text.trim(),
        workStart: _workStart.text.trim(),
        workEnd: _workEnd.text.trim(),
      );
      if (!mounted) return;
      setState(() => _notice = 'Kontrak dan jadwal tersimpan.');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _savingContract = false);
    }
  }

  Future<void> _savePoint() async {
    final client = widget.client;
    final branchId = widget.config.branchId ?? _contractBranchId;
    if (client == null || branchId == null) return;
    setState(() {
      _savingPoint = true;
      _error = null;
      _notice = null;
    });
    try {
      final lat = double.tryParse(_lat.text.trim());
      final lng = double.tryParse(_lng.text.trim());
      final radius = double.tryParse(_radius.text.trim());
      if (lat == null || lng == null || radius == null || radius <= 0) {
        throw Exception('Latitude, longitude, dan radius harus berupa angka.');
      }
      await client.updateBranchAttendancePoint(
        branchId: branchId,
        lat: lat,
        lng: lng,
        radiusM: radius.round(),
      );
      if (!mounted) return;
      setState(() => _notice = 'Titik absensi cabang tersimpan.');
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _savingPoint = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadDetail();
  }

  static String _clean(Object e) => _isMissingEndpoint(e)
      ? 'Endpoint admin absensi magang & vendor belum aktif di server publik. '
            'Deploy backend terbaru atau aktifkan route /api/admin/internships.'
      : e.toString().replaceFirst('Exception: ', '');

  static bool _isMissingEndpoint(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('not found') || text.contains('http 404');
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Absensi Magang',
            subtitle: _usingProfileFallback
                ? 'Mode fallback profil magang — kontrak, log absensi, dan titik cabang aktif setelah endpoint backend siap'
                : 'Pusat kelola kontrak, titik absensi radius cabang, dan monitoring presensi peserta magang.',
            icon: Icons.event_available_outlined,
            actions: [
              ConsoleRefreshButton(busy: _loading, onPressed: _load),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) _banner(_error!, AppTheme.badRed),
          if (_notice != null) _banner(_notice!, AppTheme.okGreen),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 380, child: _listPane()),
                const SizedBox(width: 16),
                Expanded(
                  child: selected == null
                      ? const ConsoleMessage(
                          icon: Icons.badge_outlined,
                          text: 'Belum ada peserta magang.',
                        )
                      : _detailPane(selected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color tone) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: consolePanel(),
      child: Text(text, style: TextStyle(color: tone)),
    ),
  );

  Widget _listPane() {
    final rows = _filtered;
    return Container(
      decoration: consolePanel(subtle: true),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppTheme.fg),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari nama, kampus/sekolah, jurusan...',
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const ConsoleMessage(
                    icon: Icons.search_off,
                    text: 'Tidak ada peserta magang yang cocok.',
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => Divider(
                       height: 1,
                       color: AppTheme.panelAlt.withValues(alpha: 0.7),
                     ),
                    itemBuilder: (_, i) => _visitorTile(rows[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _visitorTile(InternshipVisitorRow row) => InternshipVisitorTile(
        row: row,
        selected: row.id == _selectedId,
        onTap: () => _select(row),
      );

  Widget _detailPane(InternshipVisitorRow selected) {
    return ListView(
      children: [
        _profileCard(selected),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _contractCard()),
            const SizedBox(width: 14),
            Expanded(child: _attendancePointCard()),
          ],
        ),
        const SizedBox(height: 14),
        _attendanceCard(),
      ],
    );
  }

  Widget _profileCard(InternshipVisitorRow row) => Container(
    padding: const EdgeInsets.all(16),
    decoration: consolePanel(),
    child: Row(
      children: [
        Icon(
          row.isVendor ? Icons.business_outlined : Icons.school_outlined,
          color: AppTheme.brandGold,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    row.fullName,
                    style: const TextStyle(
                      color: AppTheme.fg,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConsolePill(
                    text: row.isVendor ? 'Vendor' : 'Magang',
                    tone: row.isVendor ? AppTheme.brandGold : AppTheme.accent,
                  ),
                ],
              ),
              Text(
                [
                  row.visitorCode,
                  if (row.isVendor) ...[
                    if (row.company.isNotEmpty) row.company,
                  ] else ...[
                    if (row.institutionName.isNotEmpty) row.institutionName,
                    if (row.major.isNotEmpty) row.major,
                  ],
                  row.phone,
                ].where((v) => v.isNotEmpty).join(' | '),
                style: const TextStyle(color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _contractCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: consolePanel(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kontrak & Jadwal',
          style: TextStyle(
            color: AppTheme.fg,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _contractBranchId,
          items: [
            for (final b in _branches)
              DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: _savingContract || _usingProfileFallback
              ? null
              : (v) => setState(() => _contractBranchId = v),
          decoration: const InputDecoration(labelText: 'Cabang penempatan'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(_start, 'Mulai (YYYY-MM-DD)')),
            const SizedBox(width: 10),
            Expanded(child: _field(_end, 'Selesai (YYYY-MM-DD)')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _field(_workStart, 'Masuk (HH:mm)')),
            const SizedBox(width: 10),
            Expanded(child: _field(_workEnd, 'Pulang (HH:mm)')),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _savingContract || _usingProfileFallback
              ? null
              : _saveContract,
          icon: _savingContract
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            _usingProfileFallback
                ? 'Endpoint belum aktif'
                : _savingContract
                ? 'Menyimpan...'
                : 'Simpan kontrak',
          ),
        ),
      ],
    ),
  );

  Widget _attendancePointCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: consolePanel(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Titik Absensi Cabang',
          style: TextStyle(
            color: AppTheme.fg,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_lat, 'Latitude')),
            const SizedBox(width: 10),
            Expanded(child: _field(_lng, 'Longitude')),
          ],
        ),
        const SizedBox(height: 10),
        _field(_radius, 'Radius meter'),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _savingPoint || _usingProfileFallback ? null : _savePoint,
          icon: _savingPoint
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.location_on_outlined),
          label: Text(
            _usingProfileFallback
                ? 'Endpoint belum aktif'
                : _savingPoint
                ? 'Menyimpan...'
                : 'Simpan titik',
          ),
        ),
      ],
    ),
  );

  Widget _attendanceCard() {
    final detail = _detail;
    final logs = detail?.logs ?? const <InternshipAttendanceLog>[];
    final hadir = logs.where((l) => l.present).length;
    final checkout = logs.where((l) => l.checkoutAt != null).length;

    final contractStart = _contractStartDate;
    final contractEnd = _contractEndDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOnly = contractStart != null
        ? DateTime(contractStart.year, contractStart.month, contractStart.day)
        : null;
    final endOnly = contractEnd != null
        ? DateTime(contractEnd.year, contractEnd.month, contractEnd.day)
        : null;

    final byDay = {for (final log in logs) log.workDate.day: log};
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    int tidakHadir = 0;
    if (startOnly != null) {
      for (var d = 1; d <= daysInMonth; d++) {
        final cDate = DateTime(_month.year, _month.month, d);
        final dOnly = DateTime(cDate.year, cDate.month, cDate.day);
        final isWk = cDate.weekday == DateTime.saturday ||
            cDate.weekday == DateTime.sunday;
        final isFut = dOnly.isAfter(today);
        final inC = !dOnly.isBefore(startOnly) &&
            (endOnly == null || !dOnly.isAfter(endOnly));
        final pres = byDay[d]?.present == true;
        if (inC && !isWk && !isFut && !pres) {
          tidakHadir++;
        }
      }
    }

    return Container(
      decoration: consolePanel(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris Header dengan Pemicu Dropdown & Pemilih Bulan
          InkWell(
            onTap: () => setState(() => _attendanceExpanded = !_attendanceExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.brandGold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.calendar_month_outlined,
                      color: AppTheme.brandGold,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kehadiran Bulanan',
                          style: TextStyle(
                            color: AppTheme.fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _formatMonthLabel(_month.year, _month.month),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dropdown Pemilih Bulan
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _monthParam,
                        dropdownColor: AppTheme.panelAlt,
                        borderRadius: BorderRadius.circular(12),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: AppTheme.brandGold,
                        ),
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        items: [
                          for (final opt in _monthOptions)
                            DropdownMenuItem(
                              value: opt.key,
                              child: Text(opt.label),
                            ),
                        ],
                        onChanged: _loading
                            ? null
                            : (val) {
                                if (val == null) return;
                                final parts = val.split('-');
                                setState(() {
                                  _month = DateTime(
                                    int.parse(parts[0]),
                                    int.parse(parts[1]),
                                  );
                                });
                                _loadDetail();
                              },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Bulan sebelumnya',
                    visualDensity: VisualDensity.compact,
                    onPressed: _loading ? null : () => _shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Bulan berikutnya',
                    visualDensity: VisualDensity.compact,
                    onPressed: _loading ? null : () => _shiftMonth(1),
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _attendanceExpanded
                        ? 'Tutup rincian kehadiran'
                        : 'Buka rincian kehadiran',
                    onPressed: () => setState(
                      () => _attendanceExpanded = !_attendanceExpanded,
                    ),
                    icon: Icon(
                      _attendanceExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: AppTheme.brandGold,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_attendanceExpanded) ...[
            const Divider(height: 1, color: Color(0x1AFFFFFF)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      StatTile(
                        label: 'Hari hadir',
                        value: hadir,
                        tone: AppTheme.okGreen,
                        icon: Icons.check_circle_outline,
                      ),
                      if (tidakHadir > 0)
                        StatTile(
                          label: 'Tidak hadir',
                          value: tidakHadir,
                          tone: AppTheme.badRed,
                          icon: Icons.cancel_outlined,
                        ),
                      StatTile(
                        label: 'Checkout lengkap',
                        value: checkout,
                        tone: AppTheme.brandGold,
                        icon: Icons.timelapse_outlined,
                      ),
                      StatTile(
                        label: 'Total log tersimpan',
                        value: logs.length,
                        tone: AppTheme.muted,
                        icon: Icons.calendar_today_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_loading && detail == null)
                    const SizedBox(
                      height: 180,
                      child: ConsoleMessage(
                        icon: Icons.hourglass_empty,
                        text: 'Memuat absensi...',
                      ),
                    )
                  else
                    _calendar(logs),
                  const SizedBox(height: 14),
                  // Dropdown / Accordion Rincian Log Harian
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _logsExpanded = !_logsExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: consolePanel(subtle: true),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.format_list_bulleted,
                            size: 16,
                            color: AppTheme.brandGold,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Rincian Log Harian (${logs.length} data)',
                            style: const TextStyle(
                              color: AppTheme.fg,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _logsExpanded ? 'Tutup daftar' : 'Buka daftar',
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _logsExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppTheme.muted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_logsExpanded) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: _logTable(logs),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _calendar(List<InternshipAttendanceLog> logs) {
    final byDay = {for (final log in logs) log.workDate.day: log};
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7;
    const weekDays = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final contractStart = _contractStartDate;
    final contractEnd = _contractEndDate;
    final startOnly = contractStart != null
        ? DateTime(contractStart.year, contractStart.month, contractStart.day)
        : null;
    final endOnly = contractEnd != null
        ? DateTime(contractEnd.year, contractEnd.month, contractEnd.day)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: Center(
                    child: Text(
                      weekDays[d],
                      style: TextStyle(
                        color: d == 0
                            ? AppTheme.badRed.withValues(alpha: 0.85)
                            : AppTheme.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leading + days,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 2.15,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (_, i) {
            if (i < leading) return const SizedBox.shrink();
            final day = i - leading + 1;
            final cellDate = DateTime(_month.year, _month.month, day);
            final dateOnly =
                DateTime(cellDate.year, cellDate.month, cellDate.day);
            final isWeekend = cellDate.weekday == DateTime.saturday ||
                cellDate.weekday == DateTime.sunday;
            final isFuture = dateOnly.isAfter(today);
            final inContract = (startOnly == null || !dateOnly.isBefore(startOnly)) &&
                (endOnly == null || !dateOnly.isAfter(endOnly));

            final log = byDay[day];
            final present = log?.present == true;

            // Jika ada data kehadiran yang kosong sejak tanggal pertama dicantumkan kontraknya,
            // beri tanda merah selain Sabtu dan Minggu.
            final isAbsent = inContract &&
                !isWeekend &&
                !isFuture &&
                !present &&
                startOnly != null;

            String timeText;
            Color timeColor;
            if (log != null && log.checkinAt != null) {
              final inTime = hhmm(log.checkinAt);
              final outTime = log.checkoutAt != null
                  ? hhmm(log.checkoutAt)
                  : '-';
              timeText = '$inTime - $outTime';
              timeColor = AppTheme.fg;
            } else if (present) {
              timeText = 'Hadir';
              timeColor = AppTheme.fg;
            } else if (isAbsent) {
              timeText = 'Tidak hadir';
              timeColor = AppTheme.badRed.withValues(alpha: 0.95);
            } else {
              timeText = '-';
              timeColor = AppTheme.muted;
            }

            String tooltipText;
            if (present) {
              tooltipText =
                  'Tgl $day: Masuk ${hhmm(log?.checkinAt)} — Pulang ${log?.checkoutAt != null ? hhmm(log?.checkoutAt) : "Belum checkout"}';
            } else if (isAbsent) {
              tooltipText =
                  'Tgl $day: Tidak ada absensi (Hari kerja dalam masa kontrak)';
            } else if (isWeekend) {
              tooltipText =
                  'Tgl $day: Akhir pekan (${cellDate.weekday == DateTime.sunday ? "Minggu" : "Sabtu"})';
            } else if (isFuture) {
              tooltipText = 'Tgl $day: Belum berjalan';
            } else {
              tooltipText = 'Tgl $day: Di luar periode kontrak aktif';
            }

            final cardBg = isAbsent
                ? AppTheme.badRed.withValues(alpha: 0.18)
                : (present
                    ? AppTheme.okGreen.withValues(alpha: 0.15)
                    : AppTheme.panelAlt.withValues(alpha: 0.35));

            final cardBorder = isAbsent
                ? AppTheme.badRed.withValues(alpha: 0.55)
                : (present
                    ? AppTheme.okGreen.withValues(alpha: 0.5)
                    : AppTheme.panelAlt);

            final dayColor = isAbsent
                ? AppTheme.badRed
                : (present ? AppTheme.okGreen : AppTheme.fg);

            return Tooltip(
              message: tooltipText,
              waitDuration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: dayColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                        if (present)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppTheme.okGreen,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (isAbsent)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppTheme.badRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      timeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 9.5,
                        fontWeight: (present || isAbsent)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _logTable(List<InternshipAttendanceLog> logs) {
    if (logs.isEmpty) {
      return const SizedBox(
        height: 120,
        child: ConsoleMessage(
          icon: Icons.event_busy,
          text: 'Belum ada log absensi pada bulan ini.',
        ),
      );
    }
    return Column(
      children: [
        for (final log in logs)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: consolePanel(subtle: true),
            child: Row(
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    _ymd(log.workDate),
                    style: const TextStyle(
                      color: AppTheme.fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Masuk ${hhmm(log.checkinAt)} | Pulang ${hhmm(log.checkoutAt)}',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
                ConsolePill(
                  text: log.present
                      ? 'Hadir'
                      : (log.status.isEmpty ? '-' : log.status),
                  tone: log.present ? AppTheme.okGreen : AppTheme.muted,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    style: const TextStyle(color: AppTheme.fg),
    decoration: InputDecoration(labelText: label),
  );
}

class InternshipVisitorTile extends StatelessWidget {
  final InternshipVisitorRow row;
  final bool selected;
  final VoidCallback onTap;

  const InternshipVisitorTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contract = row.contract;
    final isVendor = row.isVendor;
    final orgInfo = [
      if (isVendor)
        (row.company.isNotEmpty ? row.company : 'Vendor')
      else ...[
        if (row.institutionName.isNotEmpty) row.institutionName,
        if (row.major.isNotEmpty) row.major,
      ],
    ].join(' · ');

    return Material(
      color: selected ? AppTheme.brandGold.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppTheme.brandGold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.fullName.isEmpty ? '(tanpa nama)' : row.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ConsolePill(
                    text: contract == null ? 'Belum kontrak' : 'Aktif',
                    tone: contract == null ? AppTheme.badRed : AppTheme.okGreen,
                  ),
                  ConsolePill(
                    text: isVendor ? 'Vendor' : 'Magang',
                    tone: isVendor ? AppTheme.brandGold : AppTheme.accent,
                  ),
                ],
              ),
              if (orgInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  orgInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                ),
              ],
              if (contract?.endDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  's/d ${_ymd(contract!.endDate!)}',
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
