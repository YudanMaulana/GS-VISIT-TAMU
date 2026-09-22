import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Halaman Kelola Perusahaan Vendor (Whitelist).
///
/// Memungkinkan Admin menambahkan daftar PT/CV rekanan vendor yang sah.
/// Jika suatu perusahaan di-nonaktifkan, seluruh akun vendor dari perusahaan
/// tersebut akan diblokir dari melakukan absensi (check-in / check-out).
class VendorCompaniesPage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  const VendorCompaniesPage({
    super.key,
    required this.client,
    required this.config,
  });

  @override
  State<VendorCompaniesPage> createState() => _VendorCompaniesPageState();
}

class _VendorCompaniesPageState extends State<VendorCompaniesPage> {
  final _search = TextEditingController();
  List<VendorCompany> _companies = [];
  bool _loading = false;
  String? _error;
  String? _notice;
  String _filterStatus = 'semua'; // 'semua', 'aktif', 'nonaktif'

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VendorCompany> get _filtered {
    return _companies.where((c) {
      if (!c.matches(_search.text)) return false;
      if (_filterStatus == 'aktif' && !c.active) return false;
      if (_filterStatus == 'nonaktif' && c.active) return false;
      return true;
    }).toList();
  }

  int get _totalCount => _companies.length;
  int get _activeCount => _companies.where((c) => c.active).length;
  int get _inactiveCount => _companies.where((c) => !c.active).length;

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
      final list = await client.fetchVendorCompanies();
      if (!mounted) return;
      setState(() {
        _companies = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat daftar perusahaan vendor: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleStatus(VendorCompany company, bool newStatus) async {
    final client = widget.client;
    if (client == null) return;

    if (!newStatus) {
      // Konfirmasi saat mematikan perusahaan
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.badRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppTheme.badRed, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nonaktifkan Perusahaan?',
                  style: TextStyle(color: AppTheme.fg, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            'PERINGATAN: Menonaktifkan "${company.name}" akan berdampak pada SELURUH anggota vendor dari perusahaan tersebut.\n\n'
            'Anggota vendor TIDAK AKAN BISA melakukan absensi (Check-in maupun Check-out) sampai perusahaan diaktifkan kembali.',
            style: const TextStyle(color: AppTheme.mutedStrong, height: 1.4, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: AppTheme.muted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.badRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, Nonaktifkan'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _loading = true);
    try {
      await client.toggleVendorCompanyStatus(id: company.id, active: newStatus);
      if (!mounted) return;
      setState(() {
        _notice = 'Status "${company.name}" berhasil diubah menjadi ${newStatus ? 'Aktif' : 'Nonaktif'}.';
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memperbarui status: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteCompany(VendorCompany company) async {
    final client = widget.client;
    if (client == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text(
          'Hapus Perusahaan Vendor?',
          style: TextStyle(color: AppTheme.fg, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${company.name}" dari daftar whitelist?\n\n'
          'Jika sudah terdapat anggota yang terdaftar, disarankan untuk Menonaktifkan saja.',
          style: const TextStyle(color: AppTheme.mutedStrong, height: 1.4, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppTheme.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.badRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await client.deleteVendorCompany(id: company.id);
      if (!mounted) return;
      setState(() {
        _notice = 'Perusahaan "${company.name}" berhasil dihapus.';
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal menghapus: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showAddCompanyDialog() async {
    final client = widget.client;
    if (client == null) return;

    String selectedType = 'PT';
    final nameCtl = TextEditingController();
    bool isActive = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final trimmedName = nameCtl.text.trim();
          String previewFullName = '';
          if (trimmedName.isNotEmpty) {
            final upperName = trimmedName.toUpperCase();
            if (upperName.startsWith('$selectedType ') || upperName.startsWith('$selectedType.')) {
              previewFullName = upperName;
            } else {
              previewFullName = '$selectedType $upperName';
            }
          }

          return AlertDialog(
            backgroundColor: AppTheme.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.brandGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.business_rounded, color: AppTheme.brandGold, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Tambah Perusahaan Vendor',
                  style: TextStyle(color: AppTheme.fg, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bentuk Badan Usaha:',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final type in ['PT', 'CV', 'Lainnya']) ...[
                        Expanded(
                          child: InkWell(
                            onTap: () => setDlgState(() => selectedType = type),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selectedType == type
                                    ? AppTheme.brandGold.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedType == type
                                      ? AppTheme.brandGold
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    color: selectedType == type ? AppTheme.brandGold : AppTheme.fg,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (type != 'Lainnya') const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nama Perusahaan:',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtl,
                    onChanged: (_) => setDlgState(() {}),
                    style: const TextStyle(color: AppTheme.fg, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: selectedType == 'PT' ? 'Contoh: VELTRIX TECHNOLOGY' : 'Contoh: MITRA MAKMUR',
                      hintStyle: const TextStyle(color: AppTheme.muted),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.brandGold),
                      ),
                    ),
                  ),
                  if (previewFullName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppTheme.brandGold, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Disimpan sebagai: $previewFullName',
                              style: const TextStyle(color: AppTheme.fg, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Switch(
                        value: isActive,
                        activeThumbColor: AppTheme.okGreen,
                        activeTrackColor: AppTheme.okGreen.withValues(alpha: 0.3),
                        onChanged: (v) => setDlgState(() => isActive = v),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isActive ? 'Langsung Aktifkan Absensi' : 'Simpan sebagai Nonaktif (Absensi Tertutup)',
                        style: TextStyle(
                          color: isActive ? AppTheme.okGreen : AppTheme.badRed,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: AppTheme.muted)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Simpan Perusahaan', style: TextStyle(fontWeight: FontWeight.w800)),
                onPressed: trimmedName.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _loading = true);
                        try {
                          await client.saveVendorCompany(
                            name: previewFullName,
                            companyType: selectedType,
                            active: isActive,
                          );
                          if (!mounted) return;
                          setState(() {
                            _notice = 'Perusahaan "$previewFullName" berhasil didaftarkan.';
                          });
                          await _load();
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _error = 'Gagal menyimpan perusahaan: $e';
                            _loading = false;
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: ConsoleHeader(
            icon: Icons.business_outlined,
            title: 'Perusahaan Vendor',
            subtitle: 'Kelola whitelist PT/CV rekanan vendor dan izin absensi.',
            actions: [
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: AppTheme.muted),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Tambah Perusahaan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                onPressed: _loading ? null : _showAddCompanyDialog,
              ),
            ],
          ),
        ),

        // Notification / Notice
        if (_notice != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.okGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.okGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppTheme.okGreen, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_notice!, style: const TextStyle(color: AppTheme.okGreen, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.okGreen, size: 16),
                    onPressed: () => setState(() => _notice = null),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Error Banner
        if (_error != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.badRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.badRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.badRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: AppTheme.badRed, fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.badRed, size: 16),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Summary Tiles Strip
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: _summaryTile(
                  title: 'Total Perusahaan',
                  count: '$_totalCount',
                  icon: Icons.domain_outlined,
                  color: AppTheme.brandGold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryTile(
                  title: 'Aktif (Absen Diizinkan)',
                  count: '$_activeCount',
                  icon: Icons.check_circle_outlined,
                  color: AppTheme.okGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryTile(
                  title: 'Nonaktif (Absen Diblokir)',
                  count: '$_inactiveCount',
                  icon: Icons.block_outlined,
                  color: AppTheme.badRed,
                ),
              ),
            ],
          ),
        ),

        // Filter Bar & Search
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: AppTheme.fg, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Cari nama PT/CV perusahaan vendor...',
                    hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.muted, size: 20),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Filter Chips
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _filterChip('semua', 'Semua'),
                    _filterChip('aktif', 'Aktif'),
                    _filterChip('nonaktif', 'Nonaktif'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List / Table of Companies
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.brandGold))
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.business_outlined, color: AppTheme.muted.withValues(alpha: 0.5), size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _search.text.isEmpty
                                ? 'Belum ada perusahaan vendor terdaftar.'
                                : 'Tidak ditemukan perusahaan yang cocok dengan pencarian.',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 13.5),
                          ),
                          if (_search.text.isEmpty) ...[
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.brandGold,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: _showAddCompanyDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Tambah Perusahaan Pertama', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final company = filtered[index];
                        return _buildCompanyCard(company);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filterStatus == key;
    return InkWell(
      onTap: () => setState(() => _filterStatus = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brandGold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : AppTheme.mutedStrong,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _summaryTile({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    color: AppTheme.fg,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(VendorCompany company) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: company.active
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.badRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.brandGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.brandGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              company.companyType.isNotEmpty ? company.companyType : 'PT',
              style: const TextStyle(
                color: AppTheme.brandGold,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '${company.memberCount} vendor terdaftar',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                    ),
                    if (!company.active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.badRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Absensi Diblokir',
                          style: TextStyle(color: AppTheme.badRed, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Status Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                company.active ? 'Aktif' : 'Nonaktif',
                style: TextStyle(
                  color: company.active ? AppTheme.okGreen : AppTheme.badRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: company.active,
                activeThumbColor: AppTheme.okGreen,
                activeTrackColor: AppTheme.okGreen.withValues(alpha: 0.3),
                inactiveThumbColor: AppTheme.badRed,
                inactiveTrackColor: AppTheme.badRed.withValues(alpha: 0.2),
                onChanged: _loading ? null : (val) => _toggleStatus(company, val),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Hapus perusahaan',
                icon: const Icon(Icons.delete_outline, color: AppTheme.muted, size: 20),
                onPressed: _loading ? null : () => _deleteCompany(company),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
