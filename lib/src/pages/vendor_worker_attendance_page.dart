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
  String position;
  String status; // 'hadir' | 'sakit' | 'izin' | 'alfa'
  String notes;
  bool isOff; // true jika pekerja sedang di-off-kan / libur / nonaktif

  VendorWorkerItem({
    required this.id,
    required this.name,
    this.idCard = '',
    this.position = 'Pekerja Lapangan',
    this.status = 'hadir',
    this.notes = '',
    this.isOff = false,
  });

  VendorWorkerItem copyWith({
    String? name,
    String? idCard,
    String? position,
    String? status,
    String? notes,
    bool? isOff,
  }) {
    return VendorWorkerItem(
      id: id,
      name: name ?? this.name,
      idCard: idCard ?? this.idCard,
      position: position ?? this.position,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      isOff: isOff ?? this.isOff,
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
  int get activeWorkersCount => workers.where((w) => !w.isOff).length;
  int get offWorkersCount => workers.where((w) => w.isOff).length;
  int get countHadir => workers.where((w) => !w.isOff && w.status == 'hadir').length;
  int get countSakit => workers.where((w) => !w.isOff && w.status == 'sakit').length;
  int get countIzin => workers.where((w) => !w.isOff && w.status == 'izin').length;
  int get countAlfa => workers.where((w) => !w.isOff && w.status == 'alfa').length;
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
          final sampleWorkers = [
            VendorWorkerItem(id: 'w1', name: 'Ahmad Supardi', position: 'Mandor Lapangan', status: 'hadir'),
            VendorWorkerItem(id: 'w2', name: 'Bambang Irawan', position: 'Teknisi Listrik', status: 'hadir'),
            VendorWorkerItem(id: 'w3', name: 'Dedi Kurniawan', position: 'Tukang Bangunan', status: 'hadir'),
            VendorWorkerItem(id: 'w4', name: 'Eko Prasetyo', position: 'Helper', status: 'hadir'),
            VendorWorkerItem(id: 'w5', name: 'Fajar Nugraha', position: 'Tukang Las', status: 'sakit', notes: 'Demam tinggi'),
            VendorWorkerItem(id: 'w6', name: 'Guruh Santoso', position: 'Operator Genset', isOff: true, notes: 'Shift Libur Mingguan'),
            VendorWorkerItem(id: 'w7', name: 'Hendri Gunawan', position: 'Tukang Bangunan', status: 'izin', notes: 'Urusan Keluarga'),
            VendorWorkerItem(id: 'w8', name: 'Indra Lesmana', position: 'Helper', status: 'hadir'),
            VendorWorkerItem(id: 'w9', name: 'Joko Widodo', position: 'Teknisi Mekanikal', status: 'hadir'),
            VendorWorkerItem(id: 'w10', name: 'Kusuma Wardana', position: 'Pekerja Lapangan', status: 'alfa', notes: 'Tanpa Keterangan'),
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
              VendorWorkerItem(id: 'w1', name: 'Ahmad Supardi', position: 'Mandor Lapangan', status: 'hadir'),
              VendorWorkerItem(id: 'w2', name: 'Bambang Irawan', position: 'Teknisi Listrik', status: 'hadir'),
              VendorWorkerItem(id: 'w3', name: 'Dedi Kurniawan', position: 'Tukang Bangunan', status: 'hadir'),
              VendorWorkerItem(id: 'w4', name: 'Eko Prasetyo', position: 'Helper', status: 'hadir'),
              VendorWorkerItem(id: 'w5', name: 'Fajar Nugraha', position: 'Tukang Las', status: 'sakit', notes: 'Demam'),
              VendorWorkerItem(id: 'w6', name: 'Guruh Santoso', position: 'Operator Genset', isOff: true, notes: 'Shift Libur Mingguan'),
              VendorWorkerItem(id: 'w7', name: 'Hendri Gunawan', position: 'Tukang Bangunan', status: 'izin', notes: 'Urusan Keluarga'),
              VendorWorkerItem(id: 'w8', name: 'Indra Lesmana', position: 'Helper', status: 'hadir'),
              VendorWorkerItem(id: 'w9', name: 'Joko Widodo', position: 'Teknisi Mekanikal', status: 'hadir'),
              VendorWorkerItem(id: 'w10', name: 'Kusuma Wardana', position: 'Pekerja Lapangan', status: 'alfa', notes: 'Tanpa Keterangan'),
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
              VendorWorkerItem(id: 'w11', name: 'Rudi Hartono', position: 'Tukang Pipa', status: 'hadir'),
              VendorWorkerItem(id: 'w12', name: 'Slamet Riyadi', position: 'Helper', status: 'hadir'),
              VendorWorkerItem(id: 'w13', name: 'Teguh Prakoso', position: 'Tukang Las', status: 'hadir'),
              VendorWorkerItem(id: 'w14', name: 'Wahyu Hidayat', position: 'Teknisi', status: 'sakit', notes: 'Flu berat'),
              VendorWorkerItem(id: 'w15', name: 'Zaenal Abidin', position: 'Pekerja Lapangan', isOff: true, notes: 'Off / Cuti'),
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
          g.workers.any((w) =>
              w.name.toLowerCase().contains(q) ||
              w.position.toLowerCase().contains(q) ||
              w.idCard.toLowerCase().contains(q));
    }).toList();
  }

  int get _grandTotalPekerja =>
      _groups.fold(0, (acc, g) => acc + g.totalWorkers);
  int get _grandTotalOff =>
      _groups.fold(0, (acc, g) => acc + g.offWorkersCount);
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
        if (!w.isOff) {
          w.status = 'hadir';
        }
      }
      _notice = 'Semua pekerja aktif ${group.companyName} ditandai Hadir.';
    });
  }

  void _ubahStatusPekerja(VendorWorkerItem worker, String statusBaru) {
    setState(() {
      final wasOff = worker.isOff;
      worker.status = statusBaru;
      if (wasOff) {
        worker.isOff = false;
        _notice = 'Pekerja "${worker.name}" diaktifkan dan ditandai ${statusBaru.toUpperCase()}.';
      }
    });
  }

  /// Toggle status aktif / OFF pekerja
  void _toggleOffPekerja(VendorWorkerItem worker) {
    setState(() {
      worker.isOff = !worker.isOff;
      if (worker.isOff) {
        _notice = 'Pekerja "${worker.name}" berhasil di-OFF-kan (Nonaktif / Libur).';
      } else {
        _notice = 'Pekerja "${worker.name}" kembali diaktifkan (ON).';
      }
    });
  }

  /// Dialog untuk mengedit nama lengkap, nomor identitas (KTP), dan posisi pekerja
  Future<void> _dialogEditNamaPekerja(VendorWorkerItem worker) async {
    final nameCtrl = TextEditingController(text: worker.name);
    final idCardCtrl = TextEditingController(text: worker.idCard);
    final posCtrl = TextEditingController(text: worker.position);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelAlt,
        title: Row(
          children: const [
            Icon(Icons.drive_file_rename_outline, color: AppTheme.brandBlue, size: 22),
            SizedBox(width: 8),
            Text('Edit Data / Nama Pekerja', style: TextStyle(color: AppTheme.fg, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(
                  labelText: 'Nama Lengkap Pekerja *',
                  hintText: 'Misal: Sutrisno Hadi',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCardCtrl,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(
                  labelText: 'Nomor KTP / Identitas',
                  hintText: '320xxxxxxxxxxxxx (opsional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: posCtrl,
                style: const TextStyle(color: AppTheme.fg),
                decoration: const InputDecoration(
                  labelText: 'Posisi / Bidang Tugas',
                  hintText: 'Misal: Tukang Las, Teknisi Listrik',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Simpan Perubahan'),
          ),
        ],
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      setState(() {
        final oldName = worker.name;
        worker.name = nameCtrl.text.trim();
        worker.idCard = idCardCtrl.text.trim();
        worker.position = posCtrl.text.trim().isEmpty ? 'Pekerja Lapangan' : posCtrl.text.trim();
        _notice = 'Nama pekerja "$oldName" berhasil diperbarui menjadi "${worker.name}".';
      });
    }
  }

  /// Dialog untuk mengedit kehadiran lengkap (status Hadir/Sakit/Izin/Alfa, catatan, dan toggle OFF)
  Future<void> _dialogEditKehadiran(VendorWorkerItem worker) async {
    final noteCtrl = TextEditingController(text: worker.notes);
    String selectedStatus = worker.status;
    bool currentIsOff = worker.isOff;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppTheme.panelAlt,
          title: Row(
            children: [
              const Icon(Icons.edit_calendar_outlined, color: AppTheme.brandGold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Kehadiran — ${worker.name}',
                  style: const TextStyle(color: AppTheme.fg, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Panel Toggle OFF / AKTIF
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: currentIsOff
                        ? AppTheme.badRed.withValues(alpha: 0.12)
                        : AppTheme.okGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: currentIsOff ? AppTheme.badRed : AppTheme.okGreen,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            currentIsOff ? Icons.pause_circle_filled : Icons.check_circle,
                            size: 20,
                            color: currentIsOff ? AppTheme.badRed : AppTheme.okGreen,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentIsOff ? 'STATUS: OFF / NONAKTIF' : 'STATUS: AKTIF BERTUGAS',
                                style: TextStyle(
                                  color: currentIsOff ? AppTheme.badRed : AppTheme.okGreen,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                currentIsOff ? 'Pekerja sedang libur atau tidak bertugas' : 'Pekerja aktif dalam perhitungan absensi',
                                style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: !currentIsOff,
                        activeThumbColor: AppTheme.okGreen,
                        inactiveThumbColor: AppTheme.badRed,
                        onChanged: (val) {
                          setModalState(() => currentIsOff = !val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  'Pilihan Status Kehadiran:',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  dropdownColor: AppTheme.panelAlt,
                  style: const TextStyle(color: AppTheme.fg),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'hadir', child: Text('🟢 Hadir (Masuk & Bekerja)')),
                    DropdownMenuItem(value: 'sakit', child: Text('🟡 Sakit (Izin Medis / Surat Dokter)')),
                    DropdownMenuItem(value: 'izin', child: Text('🔵 Izin (Keperluan Khusus / Mandor)')),
                    DropdownMenuItem(value: 'alfa', child: Text('🔴 Alfa (Tanpa Keterangan)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedStatus = val;
                        // Jika memilih status aktif, otomatis buka mode aktif
                        if (currentIsOff) currentIsOff = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppTheme.fg),
                  decoration: const InputDecoration(
                    labelText: 'Catatan / Alasan Kehadiran',
                    hintText: 'Misal: Izin pulang kampung / Sakit flu / Penugasan area lain',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Simpan Kehadiran'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      setState(() {
        worker.status = selectedStatus;
        worker.notes = noteCtrl.text.trim();
        worker.isOff = currentIsOff;
        _notice = 'Kehadiran "${worker.name}" berhasil disimpan: ${worker.isOff ? "OFF (Libur)" : worker.status.toUpperCase()}.';
      });
    }
  }

  Future<void> _dialogTambahPekerja(VendorTeamGroup group) async {
    final nameCtrl = TextEditingController();
    final idCardCtrl = TextEditingController();
    final posCtrl = TextEditingController(text: 'Pekerja Lapangan');
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
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppTheme.fg),
                    decoration: const InputDecoration(
                      labelText: 'Nama Lengkap Pekerja *',
                      hintText: 'Misal: Sutrisno',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idCardCtrl,
                    style: const TextStyle(color: AppTheme.fg),
                    decoration: const InputDecoration(
                      labelText: 'Nomor KTP / Identitas',
                      hintText: '320xxxxxxxxxxxxx (opsional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: posCtrl,
                    style: const TextStyle(color: AppTheme.fg),
                    decoration: const InputDecoration(
                      labelText: 'Posisi / Jabatan',
                      hintText: 'Misal: Pekerja Lapangan / Teknisi',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    dropdownColor: AppTheme.panelAlt,
                    style: const TextStyle(color: AppTheme.fg),
                    decoration: const InputDecoration(labelText: 'Status Kehadiran Awal'),
                    items: const [
                      DropdownMenuItem(value: 'hadir', child: Text('🟢 Hadir')),
                      DropdownMenuItem(value: 'sakit', child: Text('🟡 Sakit')),
                      DropdownMenuItem(value: 'izin', child: Text('🔵 Izin')),
                      DropdownMenuItem(value: 'alfa', child: Text('🔴 Alfa')),
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
                      hintText: 'Misal: Penugasan khusus atau tim pengganti',
                    ),
                  ),
                ],
              ),
            ),
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
            idCard: idCardCtrl.text.trim(),
            position: posCtrl.text.trim().isEmpty ? 'Pekerja Lapangan' : posCtrl.text.trim(),
            status: selectedStatus,
            notes: noteCtrl.text.trim(),
            isOff: false,
          ),
        );
        _notice = 'Pekerja "${nameCtrl.text.trim()}" berhasil ditambahkan ke ${group.companyName}.';
      });
    }
  }

  Future<void> _dialogHapusPekerja(VendorTeamGroup group, VendorWorkerItem worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelAlt,
        title: const Text('Hapus Pekerja dari Tim', style: TextStyle(color: AppTheme.fg)),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${worker.name}" dari roster pekerja ${group.companyName}?',
          style: const TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.badRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        group.workers.removeWhere((w) => w.id == worker.id);
        _notice = 'Pekerja "${worker.name}" berhasil dihapus dari daftar.';
      });
    }
  }

  void _simpanAbsensi(VendorTeamGroup group) {
    setState(() {
      group.isVerified = true;
      _notice =
          'Rekapitulasi absensi ${group.companyName} (${group.activeWorkersCount} Aktif, ${group.offWorkersCount} OFF: Hadir ${group.countHadir}, Sakit ${group.countSakit}, Izin ${group.countIzin}, Alfa ${group.countAlfa}) berhasil disimpan.';
    });
  }

  void _eksporCsv(VendorTeamGroup group) {
    final dateStr = _formatIsoDate(group.date);
    final buffer = StringBuffer();
    buffer.writeln('No,Nama Pekerja,No KTP,Posisi,Perusahaan,PIC Mandor,Tanggal,Status Keaktifan,Status Kehadiran,Keterangan');
    for (var i = 0; i < group.workers.length; i++) {
      final w = group.workers[i];
      final keaktifan = w.isOff ? 'OFF' : 'AKTIF';
      final kehadiran = w.isOff ? 'OFF / LIBUR' : w.status.toUpperCase();
      buffer.writeln(
        '${i + 1},"${w.name}","${w.idCard}","${w.position}","${group.companyName}","${group.picName}",$dateStr,$keaktifan,$kehadiran,"${w.notes}"',
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelAlt,
        title: Text('Hasil Ekspor CSV — ${group.companyName}'),
        content: SizedBox(
          width: 580,
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
                'Setiap pekerja dapat di-OFF-kan, diedit namanya, dan diatur status kehadirannya (Hadir, Sakit, Izin, Alfa).',
            icon: Icons.groups_outlined,
            actions: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: 'Hari Sebelumnya',
                    onPressed: () {
                      setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                      _load();
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
                        firstDate: DateTime(2025),
                        lastDate: today, // CEGAH HARI SELANJUTNYA: Maksimal hari ini!
                      );
                      if (picked != null) {
                        if (picked.isAfter(today)) return;
                        setState(() => _selectedDate = picked);
                        await _load();
                      }
                    },
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(dateLabel),
                  ),
                  Builder(
                    builder: (ctx) {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final isTodayOrFuture = _selectedDate.isAtSameMomentAs(today) || _selectedDate.isAfter(today);
                      return IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: isTodayOrFuture ? AppTheme.muted.withValues(alpha: 0.3) : AppTheme.fg,
                        ),
                        tooltip: isTodayOrFuture ? 'Maksimal Hari Ini (Cegah Hari Selanjutnya)' : 'Hari Berikutnya',
                        onPressed: isTodayOrFuture
                            ? null
                            : () {
                                final next = _selectedDate.add(const Duration(days: 1));
                                if (next.isAfter(today)) return;
                                setState(() => _selectedDate = next);
                                _load();
                              },
                      );
                    },
                  ),
                ],
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
                SizedBox(width: 390, child: _buildVendorListPane()),
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
            label: 'Total Vendor',
            value: '${_groups.length}',
            sub: 'Perusahaan Terdata',
            icon: Icons.business,
            tone: AppTheme.brandBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Total Pekerja',
            value: '$_grandTotalPekerja',
            sub: 'Roster tim',
            icon: Icons.people_outline,
            tone: AppTheme.fg,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Hadir',
            value: '$_grandTotalHadir',
            sub: 'Siap bekerja',
            icon: Icons.check_circle_outline,
            tone: AppTheme.okGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Sakit',
            value: '$_grandTotalSakit',
            sub: 'Kondisi tidak fit',
            icon: Icons.healing_outlined,
            tone: AppTheme.brandGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Izin',
            value: '$_grandTotalIzin',
            sub: 'Pemberitahuan resmi',
            icon: Icons.assignment_outlined,
            tone: Colors.lightBlueAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Alfa',
            value: '$_grandTotalAlfa',
            sub: 'Tanpa kabar',
            icon: Icons.cancel_outlined,
            tone: AppTheme.badRed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            label: 'Pekerja OFF',
            value: '$_grandTotalOff',
            sub: 'Libur / Nonaktif',
            icon: Icons.pause_circle_outline,
            tone: Colors.blueGrey,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tone, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: tone,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 10.5,
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
                hintText: 'Cari vendor, PIC, nama pekerja...',
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const ConsoleMessage(
                    icon: Icons.search_off,
                    text: 'Tidak ada data vendor yang cocok dengan pencarian.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = rows[idx];
                      final isSelected = item.visitorId == _selectedVisitorId;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedVisitorId = item.visitorId;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.brandBlue.withValues(alpha: 0.15)
                                : AppTheme.panel.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.brandBlue
                                  : Colors.white.withValues(alpha: 0.05),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
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
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.okGreen.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${item.activeWorkersCount}/${item.totalWorkers} Aktif',
                                      style: const TextStyle(
                                        color: AppTheme.okGreen,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.person_pin_circle_outlined, size: 13, color: AppTheme.muted),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'PIC: ${item.picName}',
                                      style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  _miniBadge('Hadir ${item.countHadir}', AppTheme.okGreen),
                                  _miniBadge('Sakit ${item.countSakit}', AppTheme.brandGold),
                                  _miniBadge('Izin ${item.countIzin}', Colors.lightBlueAccent),
                                  _miniBadge('Alfa ${item.countAlfa}', AppTheme.badRed),
                                  if (item.offWorkersCount > 0)
                                    _miniBadge('OFF ${item.offWorkersCount}', Colors.blueGrey),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
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
            padding: const EdgeInsets.all(14),
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
                      Row(
                        children: [
                          Text(
                            group.companyName,
                            style: const TextStyle(
                              color: AppTheme.fg,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (group.isVerified)
                            const Icon(Icons.verified, size: 16, color: AppTheme.okGreen),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PIC Mandor: ${group.picName} (${group.picPhone}) • ${group.branchName}',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _tandaiSemuaHadir(group),
                  icon: const Icon(Icons.done_all, size: 15),
                  label: const Text('Semua Aktif Hadir', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _dialogTambahPekerja(group),
                  icon: const Icon(Icons.person_add, size: 15),
                  label: const Text('Tambah Pekerja', style: TextStyle(fontSize: 12)),
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

          // Petunjuk Cepat
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AppTheme.panelAlt.withValues(alpha: 0.3),
            child: Row(
              children: const [
                Icon(Icons.info_outline, size: 14, color: AppTheme.brandBlue),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Fitur Pekerja: Klik tombol [OFF / AKTIF] untuk libur/aktifkan, icon pensil untuk Edit Nama, icon kalender untuk Edit Kehadiran & Catatan.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
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
                      final isOff = worker.isOff;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: isOff
                              ? AppTheme.panel.withValues(alpha: 0.22)
                              : AppTheme.panel.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isOff
                                ? AppTheme.badRed.withValues(alpha: 0.30)
                                : Colors.white.withValues(alpha: 0.05),
                            width: isOff ? 1.2 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Nomor urut / Badge Avatar
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isOff
                                    ? AppTheme.badRed.withValues(alpha: 0.15)
                                    : AppTheme.brandBlue.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: isOff
                                  ? const Icon(Icons.pause, size: 16, color: AppTheme.badRed)
                                  : Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                        color: AppTheme.brandBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),

                            // Nama, Jabatan, Identitas, Catatan
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          worker.name,
                                          style: TextStyle(
                                            color: isOff ? AppTheme.muted : AppTheme.fg,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                            decoration: isOff ? TextDecoration.lineThrough : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isOff) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.badRed.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.badRed.withValues(alpha: 0.4)),
                                          ),
                                          child: const Text(
                                            'OFF / LIBUR',
                                            style: TextStyle(
                                              color: AppTheme.badRed,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${worker.position}${worker.idCard.isNotEmpty ? " • KTP: ${worker.idCard}" : ""}',
                                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                                  ),
                                  if (worker.notes.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    InkWell(
                                      onTap: () => _dialogEditKehadiran(worker),
                                      child: Text(
                                        'Catatan: ${worker.notes}',
                                        style: const TextStyle(
                                          color: AppTheme.brandGold,
                                          fontSize: 10.5,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // 1. Toggle Tombol OFF / AKTIF
                            Tooltip(
                              message: isOff
                                  ? 'Klik untuk Mengaktifkan Pekerja (ON)'
                                  : 'Klik untuk Meng-OFF-kan Pekerja (Libur / Nonaktif)',
                              child: InkWell(
                                onTap: () => _toggleOffPekerja(worker),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isOff
                                        ? AppTheme.badRed.withValues(alpha: 0.15)
                                        : AppTheme.okGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isOff ? AppTheme.badRed : AppTheme.okGreen,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isOff ? Icons.pause_circle_filled : Icons.check_circle,
                                        size: 13,
                                        color: isOff ? AppTheme.badRed : AppTheme.okGreen,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isOff ? 'OFF' : 'AKTIF',
                                        style: TextStyle(
                                          color: isOff ? AppTheme.badRed : AppTheme.okGreen,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // 2. Tombol Edit Nama & Data Pekerja
                            IconButton(
                              icon: const Icon(Icons.drive_file_rename_outline, size: 18, color: AppTheme.brandBlue),
                              tooltip: 'Edit Nama & Identitas Pekerja',
                              onPressed: () => _dialogEditNamaPekerja(worker),
                            ),

                            // 3. Tombol Edit Kehadiran & Catatan
                            IconButton(
                              icon: const Icon(Icons.edit_calendar_outlined, size: 18, color: AppTheme.brandGold),
                              tooltip: 'Edit Status Kehadiran & Catatan Lengkap',
                              onPressed: () => _dialogEditKehadiran(worker),
                            ),
                            const SizedBox(width: 4),

                            // 4. Pilihan Cepat 4 Status: Hadir, Sakit, Izin, Alfa
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _statusOptionButton(
                                  label: 'Hadir',
                                  color: AppTheme.okGreen,
                                  isSelected: !isOff && worker.status == 'hadir',
                                  onTap: () => _ubahStatusPekerja(worker, 'hadir'),
                                ),
                                const SizedBox(width: 5),
                                _statusOptionButton(
                                  label: 'Sakit',
                                  color: AppTheme.brandGold,
                                  isSelected: !isOff && worker.status == 'sakit',
                                  onTap: () => _ubahStatusPekerja(worker, 'sakit'),
                                ),
                                const SizedBox(width: 5),
                                _statusOptionButton(
                                  label: 'Izin',
                                  color: Colors.lightBlueAccent,
                                  isSelected: !isOff && worker.status == 'izin',
                                  onTap: () => _ubahStatusPekerja(worker, 'izin'),
                                ),
                                const SizedBox(width: 5),
                                _statusOptionButton(
                                  label: 'Alfa',
                                  color: AppTheme.badRed,
                                  isSelected: !isOff && worker.status == 'alfa',
                                  onTap: () => _ubahStatusPekerja(worker, 'alfa'),
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),

                            // 5. Tombol Hapus Pekerja
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.badRed),
                              tooltip: 'Hapus Pekerja dari Tim',
                              onPressed: () => _dialogHapusPekerja(group, worker),
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
                  'Total ${group.totalWorkers} Pekerja (${group.activeWorkersCount} Aktif, ${group.offWorkersCount} OFF) • Hadir: ${group.countHadir} | Sakit: ${group.countSakit} | Izin: ${group.countIzin} | Alfa: ${group.countAlfa}',
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
