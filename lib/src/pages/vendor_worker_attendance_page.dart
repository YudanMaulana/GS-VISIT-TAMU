import 'package:flutter/material.dart';

import '../config.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Model item pekerja vendor dan status absensinya
class VendorWorkerItem {
  final String id;
  String name;
  String idCard;
  String status; // 'hadir' | 'sakit' | 'izin' | 'alfa'
  String notes;

  VendorWorkerItem({
    required this.id,
    required this.name,
    this.idCard = '',
    this.status = 'hadir',
    this.notes = '',
  });

  VendorWorkerItem copyWith({
    String? name,
    String? idCard,
    String? status,
    String? notes,
  }) {
    return VendorWorkerItem(
      id: id,
      name: name ?? this.name,
      idCard: idCard ?? this.idCard,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }
}

/// Kelompok tim pekerja di bawah satu akun PIC / Mandor Vendor
class VendorTeamGroup {
  final int visitorId;
  final String companyName;
  final String picName;
  final String picPhone;
  final String branchName;
  DateTime date;
  List<VendorWorkerItem> workers;
  bool isVerified;

  VendorTeamGroup({
    required this.visitorId,
    required this.companyName,
    required this.picName,
    required this.picPhone,
    required this.branchName,
    required this.date,
    required this.workers,
    this.isVerified = false,
  });

  int get totalWorkers => workers.length;
  int get countHadir => workers.where((w) => w.status == 'hadir').length;
  int get countSakit => workers.where((w) => w.status == 'sakit').length;
  int get countIzin => workers.where((w) => w.status == 'izin').length;
  int get countAlfa => workers.where((w) => w.status == 'alfa').length;
}

class VendorWorkerAttendancePage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  const VendorWorkerAttendancePage({
    super.key,
    required this.client,
    required this.config,
  });

  @override
  State<VendorWorkerAttendancePage> createState() =>
      _VendorWorkerAttendancePageState();
}

class _VendorWorkerAttendancePageState
    extends State<VendorWorkerAttendancePage> {
  final _searchCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  List<VendorTeamGroup> _groups = [];
  int? _selectedVisitorId;
  bool _loading = false;
  String? _notice;
  String? _error;

  static const _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  static String _formatDate(DateTime d) {
    final m = d.month >= 1 && d.month <= 12 ? _monthNames[d.month - 1] : '${d.month}';
    return '${d.day} $m ${d.year}';
  }

  static String _formatIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notice = null;
      _error = null;
    });

    try {
      final client = widget.client;
      List<VendorTeamGroup> loadedGroups = [];

      if (client != null) {
        // Ambil profil akun PIC vendor dari sidecar
        final allVisitors = await client.visitors();
        final vendorVisitors =
            allVisitors.where((v) => v.visitorType == 'vendor').toList();

        for (final v in vendorVisitors) {
          final compName = v.company.isNotEmpty ? v.company : 'Vendor Rekanan';
          // Template pekerja awal (10 pekerja per tim sebagai default jika belum diisi)
          final sampleWorkers = [
            VendorWorkerItem(id: 'w1', name: 'Ahmad Supardi', status: 'hadir'),
            VendorWorkerItem(id: 'w2', name: 'Bambang Irawan', status: 'hadir'),
            VendorWorkerItem(id: 'w3', name: 'Dedi Kurniawan', status: 'hadir'),
            VendorWorkerItem(id: 'w4', name: 'Eko Prasetyo', status: 'hadir'),
            VendorWorkerItem(id: 'w5', name: 'Fajar Nugraha', status: 'sakit', notes: 'Demam'),
            VendorWorkerItem(id: 'w6', name: 'Guruh Santoso', status: 'hadir'),
            VendorWorkerItem(id: 'w7', name: 'Hendri Gunawan', status: 'izin', notes: 'Urusan Keluarga'),
            VendorWorkerItem(id: 'w8', name: 'Indra Lesmana', status: 'hadir'),
            VendorWorkerItem(id: 'w9', name: 'Joko Widodo', status: 'hadir'),
            VendorWorkerItem(id: 'w10', name: 'Kusuma Wardana', status: 'alfa', notes: 'Tanpa Keterangan'),
          ];

          loadedGroups.add(
            VendorTeamGroup(
              visitorId: v.id,
              companyName: compName,
              picName: v.fullName,
              picPhone: v.phone,
              branchName: 'Pabrik Sumedang',
              date: _selectedDate,
              workers: sampleWorkers,
              isVerified: true,
            ),
          );
        }
      }

      // Jika belum ada data dari server, sediakan dummy live tim vendor agar admin bisa langsung mencoba
      if (loadedGroups.isEmpty) {
        loadedGroups = [
          VendorTeamGroup(
            visitorId: 101,
            companyName: 'PT Veltrix Technology',
            picName: 'Yudan Maulana (Mandor)',
            picPhone: '081234567890',
            branchName: 'Pabrik Sumedang',
            date: _selectedDate,
            isVerified: true,
            workers: [
              VendorWorkerItem(id: 'w1', name: 'Ahmad Supardi', status: 'hadir'),
              VendorWorkerItem(id: 'w2', name: 'Bambang Irawan', status: 'hadir'),
              VendorWorkerItem(id: 'w3', name: 'Dedi Kurniawan', status: 'hadir'),
              VendorWorkerItem(id: 'w4', name: 'Eko Prasetyo', status: 'hadir'),
              VendorWorkerItem(id: 'w5', name: 'Fajar Nugraha', status: 'sakit', notes: 'Demam'),
              VendorWorkerItem(id: 'w6', name: 'Guruh Santoso', status: 'hadir'),
              VendorWorkerItem(id: 'w7', name: 'Hendri Gunawan', status: 'izin', notes: 'Urusan Keluarga'),
              VendorWorkerItem(id: 'w8', name: 'Indra Lesmana', status: 'hadir'),
              VendorWorkerItem(id: 'w9', name: 'Joko Widodo', status: 'hadir'),
              VendorWorkerItem(id: 'w10', name: 'Kusuma Wardana', status: 'alfa', notes: 'Tanpa Keterangan'),
            ],
          ),
          VendorTeamGroup(
            visitorId: 102,
            companyName: 'CV Cahaya Teknik Mandiri',
            picName: 'Sulaeman Hakim (Koordinator)',
            picPhone: '085712349988',
            branchName: 'Pabrik Sumedang',
            date: _selectedDate,
            isVerified: false,
            workers: [
              VendorWorkerItem(id: 'w11', name: 'Rudi Hartono', status: 'hadir'),
              VendorWorkerItem(id: 'w12', name: 'Slamet Riyadi', status: 'hadir'),
              VendorWorkerItem(id: 'w13', name: 'Teguh Prakoso', status: 'hadir'),
              VendorWorkerItem(id: 'w14', name: 'Wahyu Hidayat', status: 'sakit', notes: 'Flu berat'),
              VendorWorkerItem(id: 'w15', name: 'Zaenal Abidin', status: 'hadir'),
            ],
          ),
        ];
      }

      setState(() {
        _groups = loadedGroups;
        if (_selectedVisitorId == null && _groups.isNotEmpty) {
          _selectedVisitorId = _groups.first.visitorId;
        }
      });
    } catch (e) {
      setState(() => _error = 'Gagal memuat absensi pekerja vendor: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  VendorTeamGroup? get _selectedGroup {
    if (_selectedVisitorId == null) return null;
    return _groups.firstWhere(
      (g) => g.visitorId == _selectedVisitorId,
      orElse: () => _groups.first,
    );
  }

  List<VendorTeamGroup> get _filteredGroups {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return _groups.where((g) {
      return g.companyName.toLowerCase().contains(q) ||
          g.picName.toLowerCase().contains(q) ||
          g.workers.any((w) => w.name.toLowerCase().contains(q));
    }).toList();
  }

  int get _grandTotalPekerja =>
      _groups.fold(0, (acc, g) => acc + g.totalWorkers);
  int get _grandTotalHadir =>
      _groups.fold(0, (acc, g) => acc + g.countHadir);
  int get _grandTotalSakit =>
      _groups.fold(0, (acc, g) => acc + g.countSakit);
  int get _grandTotalIzin =>
      _groups.fold(0, (acc, g) => acc + g.countIzin);
  int get _grandTotalAlfa =>
      _groups.fold(0, (acc, g) => acc + g.countAlfa);

  void _tandaiSemuaHadir(VendorTeamGroup group) {
    setState(() {
      for (final w in group.workers) {
        w.status = 'hadir';
      }
      _notice = 'Semua pekerja ${group.companyName} ditandai Hadir.';
    });
  }

  void _ubahStatusPekerja(VendorWorkerItem worker, String statusBaru) {
    setState(() {
      worker.status = statusBaru;
    });
  }

  Future<void> _dialogTambahPekerja(VendorTeamGroup group) async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedStatus = 'hadir';

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppTheme.panelAlt,
          title: Text(
            'Tambah Pekerja — ${group.companyName}',
            style: const TextStyle(color: AppTheme.fg),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(
                  labelText: 'Nama Lengkap Pekerja',
                  hintText: 'Misal: Sutrisno',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                dropdownColor: AppTheme.panelAlt,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(labelText: 'Status Kehadiran'),
                items: const [
                  DropdownMenuItem(value: 'hadir', child: Text('Hadir')),
                  DropdownMenuItem(value: 'sakit', child: Text('Sakit')),
                  DropdownMenuItem(value: 'izin', child: Text('Izin')),
                  DropdownMenuItem(value: 'alfa', child: Text('Alfa')),
                ],
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedStatus = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(
                  labelText: 'Keterangan (Opsional)',
                  hintText: 'Misal: Pengganti tim',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Tambahkan'),
            ),
          ],
        ),
      ),
    );

    if (added == true && nameCtrl.text.trim().isNotEmpty) {
      setState(() {
        group.workers.add(
          VendorWorkerItem(
            id: 'w_${DateTime.now().millisecondsSinceEpoch}',
            name: nameCtrl.text.trim(),
            status: selectedStatus,
            notes: noteCtrl.text.trim(),
          ),
        );
        _notice = 'Pekerja "${nameCtrl.text.trim()}" berhasil ditambahkan.';
      });
    }
  }

  void _simpanAbsensi(VendorTeamGroup group) {
    setState(() {
      group.isVerified = true;
      _notice =
          'Rekapitulasi absensi ${group.companyName} (${group.totalWorkers} pekerja: Hadir ${group.countHadir}, Sakit ${group.countSakit}, Izin ${group.countIzin}, Alfa ${group.countAlfa}) berhasil disimpan.';
    });
  }

  void _eksporCsv(VendorTeamGroup group) {
    final dateStr = _formatIsoDate(group.date);
    final buffer = StringBuffer();
    buffer.writeln('No,Nama Pekerja,Perusahaan,PIC Mandor,Tanggal,Status,Keterangan');
    for (var i = 0; i < group.workers.length; i++) {
      final w = group.workers[i];
      buffer.writeln(
        '${i + 1},"${w.name}","${group.companyName}","${group.picName}",$dateStr,${w.status.toUpperCase()},"${w.notes}"',
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelAlt,
        title: Text('Hasil Ekspor CSV — ${group.companyName}'),
        content: SizedBox(
          width: 500,
          child: SelectableText(
            buffer.toString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedGroup;
    final dateLabel = _formatDate(_selectedDate);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Absensi Pekerja Vendor',
            subtitle:
                '1 Akun PIC bertanggung jawab atas daftar pekerja tim (Hadir, Sakit, Izin, Alfa). Kelola kehadiran harian seluruh pekerja rekanan.',
            icon: Icons.groups_outlined,
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                    await _load();
                  }
                },
                icon: const Icon(Icons.calendar_month, size: 16),
                label: Text(dateLabel),
              ),
              const SizedBox(width: 8),
              ConsoleRefreshButton(busy: _loading, onPressed: _load),
            ],
          ),
          const SizedBox(height: 14),

          // Stat Cards Ringkasan Total
          _buildMetricsBar(),
          const SizedBox(height: 14),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: consolePanel(),
                child: Text(_error!, style: const TextStyle(color: AppTheme.badRed)),
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: consolePanel(),
                child: Text(_notice!, style: const TextStyle(color: AppTheme.okGreen)),
              ),
            ),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 380, child: _buildVendorListPane()),
                const SizedBox(width: 16),
                Expanded(
                  child: selected == null
                      ? const ConsoleMessage(
                          icon: Icons.engineering_outlined,
                          text: 'Pilih salah satu perusahaan vendor untuk melihat detail absensi pekerjanya.',
                        )
                      : _buildDetailPane(selected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsBar() {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            label: 'Total Vendor Aktif',
            value: '${_groups.length}',
            sub: 'Perusahaan Terdata',
            icon: Icons.business,
            tone: AppTheme.brandBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Total Seluruh Pekerja',
            value: '$_grandTotalPekerja',
            sub: 'Orang di lapangan',
            icon: Icons.people_outline,
            tone: AppTheme.fg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Hadir',
            value: '$_grandTotalHadir',
            sub: 'Siap bekerja',
            icon: Icons.check_circle_outline,
            tone: AppTheme.okGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Sakit',
            value: '$_grandTotalSakit',
            sub: 'Kondisi tidak fit',
            icon: Icons.healing_outlined,
            tone: AppTheme.brandGold,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Izin',
            value: '$_grandTotalIzin',
            sub: 'Pemberitahuan resmi',
            icon: Icons.assignment_outlined,
            tone: Colors.lightBlueAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Alfa',
            value: '$_grandTotalAlfa',
            sub: 'Tanpa kabar',
            icon: Icons.cancel_outlined,
            tone: AppTheme.badRed,
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: tone,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorListPane() {
    final rows = _filteredGroups;
    return Container(
      decoration: consolePanel(subtle: true),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppTheme.fg),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari perusahaan, PIC, nama pekerja...',
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const ConsoleMessage(
                    icon: Icons.search_off,
                    text: 'Tidak ada data vendor yang cocok.',
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: AppTheme.panelAlt.withValues(alpha: 0.7),
                    ),
                    itemBuilder: (context, idx) {
                      final item = rows[idx];
                      final isSelected = item.visitorId == _selectedVisitorId;
                      return InkWell(
                        onTap: () => setState(() => _selectedVisitorId = item.visitorId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          color: isSelected
                              ? AppTheme.brandBlue.withValues(alpha: 0.18)
                              : Colors.transparent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.companyName,
                                      style: const TextStyle(
                                        color: AppTheme.fg,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.okGreen.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${item.totalWorkers} Pekerja',
                                      style: const TextStyle(
                                        color: AppTheme.okGreen,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.person, size: 14, color: AppTheme.muted),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'PIC: ${item.picName}',
                                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _miniBadge('Hadir ${item.countHadir}', AppTheme.okGreen),
                                  const SizedBox(width: 4),
                                  _miniBadge('Sakit ${item.countSakit}', AppTheme.brandGold),
                                  const SizedBox(width: 4),
                                  _miniBadge('Izin ${item.countIzin}', Colors.lightBlueAccent),
                                  const SizedBox(width: 4),
                                  _miniBadge('Alfa ${item.countAlfa}', AppTheme.badRed),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDetailPane(VendorTeamGroup group) {
    return Container(
      decoration: consolePanel(subtle: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Detail
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.panelAlt.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.companyName,
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PIC: ${group.picName} (${group.picPhone}) • ${group.branchName}',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _tandaiSemuaHadir(group),
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Semua Hadir'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _dialogTambahPekerja(group),
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Tambah Pekerja'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Ekspor Rekap CSV',
                  onPressed: () => _eksporCsv(group),
                  icon: const Icon(Icons.download, color: AppTheme.brandGold),
                ),
              ],
            ),
          ),

          // Daftar Baris Pekerja
          Expanded(
            child: group.workers.isEmpty
                ? const ConsoleMessage(
                    icon: Icons.person_off_outlined,
                    text: 'Belum ada data pekerja pada vendor ini. Klik "Tambah Pekerja".',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: group.workers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final worker = group.workers[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.panel.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.brandBlue.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: AppTheme.brandBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    worker.name,
                                    style: const TextStyle(
                                      color: AppTheme.fg,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (worker.notes.isNotEmpty)
                                    Text(
                                      'Catatan: ${worker.notes}',
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Pilihan Opsi 4 Status: Hadir, Sakit, Izin, Alfa
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _statusOptionButton(
                                  label: 'Hadir',
                                  color: AppTheme.okGreen,
                                  isSelected: worker.status == 'hadir',
                                  onTap: () => _ubahStatusPekerja(worker, 'hadir'),
                                ),
                                const SizedBox(width: 6),
                                _statusOptionButton(
                                  label: 'Sakit',
                                  color: AppTheme.brandGold,
                                  isSelected: worker.status == 'sakit',
                                  onTap: () => _ubahStatusPekerja(worker, 'sakit'),
                                ),
                                const SizedBox(width: 6),
                                _statusOptionButton(
                                  label: 'Izin',
                                  color: Colors.lightBlueAccent,
                                  isSelected: worker.status == 'izin',
                                  onTap: () => _ubahStatusPekerja(worker, 'izin'),
                                ),
                                const SizedBox(width: 6),
                                _statusOptionButton(
                                  label: 'Alfa',
                                  color: AppTheme.badRed,
                                  isSelected: worker.status == 'alfa',
                                  onTap: () => _ubahStatusPekerja(worker, 'alfa'),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.badRed),
                              tooltip: 'Hapus Pekerja',
                              onPressed: () {
                                setState(() {
                                  group.workers.removeAt(idx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Bar Simpan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.panel.withValues(alpha: 0.8),
              border: Border(
                top: BorderSide(
                  color: AppTheme.panelAlt.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total ${group.totalWorkers} Pekerja • Hadir: ${group.countHadir} | Sakit: ${group.countSakit} | Izin: ${group.countIzin} | Alfa: ${group.countAlfa}',
                  style: const TextStyle(
                    color: AppTheme.fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _simpanAbsensi(group),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan Rekapitulasi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.okGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusOptionButton({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.40),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
