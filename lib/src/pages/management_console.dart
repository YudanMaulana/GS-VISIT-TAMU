import 'dart:async';

import 'package:flutter/material.dart';

import '../admin_auth.dart';
import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import 'area_guests_page.dart';
import 'detection_info_page.dart';
import 'face_search_page.dart';
import 'guest_management_page.dart';
import 'internship_attendance_page.dart';
import 'pending_checkin_page.dart';
import 'migrate_user_page.dart';
import 'reset_data_page.dart';
import 'support_reports_page.dart';
import 'transporter_checkin_page.dart';
import 'vendor_companies_page.dart';
import 'walk_in_page.dart';

/// Konsol Kelola Data — di balik gate admin. Lima bagian, semuanya aktif:
/// Cari Wajah dan Deteksi & Embedding memakai engine lokal, sedangkan
/// Semua Profil, Tamu di Area, dan Belum Check-in membaca server lewat
/// sidecar (GUI ini tidak punya jalur langsung ke server).
///
/// Semua Profil sengaja hanya bisa menyunting teks profil. Ganti foto
/// referensi, lepas tautan Google, dan hapus tamu tidak disediakan dan juga
/// tidak diteruskan sidecar, jadi konsol ini tidak bisa merusak data wajah
/// maupun riwayat kunjungan.
/// Halaman-halaman konsol.
///
/// Dulu menu menunjuk halaman lewat nomor urut di dalam list. Menyisipkan satu
/// halaman di tengah menggeser semua nomor sesudahnya, dan menunya diam-diam
/// mengarah ke halaman yang salah -- tanpa satu pun galat, karena nomor
/// tetangganya sama-sama sah. Dengan nama, salah tunjuk jadi tidak bisa
/// dikompilasi.
enum ConsolePage {
  cariWajah,
  deteksi,
  manajemenTamu,
  vendorCompanies,
  tamuArea,
  transporterArea,
  transporterCheckin,
  transporterCheckout,
  internshipAttendance,
  belumCheckin,
  secondMonitor,
  supportReports,
  migrasi,
  reset,
}

class ManagementConsole extends StatefulWidget {
  final SidecarClient? client;
  final SidecarClient? cameraClient;
  final DetectionState? cameraState;
  final AppConfig config;
  final AdminSession session;
  final bool embedded;

  /// Membuka jendela kiosk di layar sentuh kedua. Dimiliki HomePage, bukan
  /// halaman ini: jendelanya hidup lebih lama daripada konsol yang dibuka
  /// tutup, dan penerimanya channel juga dipasang di sana.
  final Future<void> Function()? onOpenKiosk;

  /// Membuka jendela pratinjau kamera untuk petugas (frame live + tombol
  /// ambil). Bukan layar tamu — lihat [onOpenKiosk].
  final Future<void> Function()? onOpenPreview;

  const ManagementConsole({
    super.key,
    required this.client,
    this.cameraClient,
    this.cameraState,
    required this.config,
    required this.session,
    this.embedded = false,
    this.onOpenKiosk,
    this.onOpenPreview,
  });

  @override
  State<ManagementConsole> createState() => _ManagementConsoleState();
}

class _ManagementConsoleState extends State<ManagementConsole> {
  ConsolePage _halaman = ConsolePage.manajemenTamu;
  DetectionState _state = DetectionState();
  Timer? _poll;
  bool _busy = false;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    // Own poll so the live-detection view updates while the console is open,
    // independent of the POS screen behind it.
    _poll = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick());
  }

  Future<void> _tick() async {
    final client = widget.cameraClient ?? widget.client;
    // Hanya halaman yang benar-benar menampilkan kamera yang perlu frame:
    // Deteksi & Embedding dan Second Monitor, yang keduanya melukis
    // pratinjau langsung. Memoles sidecar 11x/detik sementara operator membaca
    // tabel admin itu pemborosan murni, dan halaman-halaman itu punya tombol
    // muat ulang sendiri.
    if ((_halaman != ConsolePage.deteksi &&
            _halaman != ConsolePage.secondMonitor &&
            _halaman != ConsolePage.transporterCheckin &&
            _halaman != ConsolePage.transporterCheckout) ||
        _busy ||
        client == null) {
      return;
    }
    _busy = true;
    try {
      final s = await client.fetchState();
      if (mounted) setState(() => _state = s);
    } catch (_) {
      // transient
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _lockAndExit() {
    widget.session.lock();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    widget.session.touch(); // any interaction that rebuilds slides the timeout
    final cameraClient = widget.cameraClient ?? widget.client;
    final cameraState = widget.cameraState ?? _state;
    final isi = switch (_halaman) {
      ConsolePage.cariWajah => FaceSearchPage(client: widget.client),
      ConsolePage.deteksi => DetectionInfoPage(
        client: cameraClient,
        state: cameraState,
      ),
      ConsolePage.manajemenTamu => GuestManagementPage(client: widget.client),
      ConsolePage.vendorCompanies => VendorCompaniesPage(
        client: widget.client,
        config: widget.config,
      ),
      ConsolePage.tamuArea => AreaGuestsPage(
        client: widget.client,
        config: widget.config,
      ),
      ConsolePage.transporterArea => AreaGuestsPage(
        client: widget.client,
        config: widget.config,
        kind: BoardKind.transporter,
      ),
      ConsolePage.transporterCheckin => TransporterCheckinPage(
        client: cameraClient,
        state: cameraState,
        // Nama petugas terisi dari sesi admin yang sedang masuk: yang
        // menandatangani adalah orang yang login, bukan nama yang diketik
        // bebas tiap kali.
        officerName: widget.session.email,
      ),
      ConsolePage.transporterCheckout => TransporterCheckinPage(
        client: cameraClient,
        state: cameraState,
        officerName: widget.session.email,
        kind: KonfirmasiMode.keluar,
      ),
      ConsolePage.internshipAttendance => InternshipAttendancePage(
        client: widget.client,
        config: widget.config,
      ),
      ConsolePage.belumCheckin => PendingCheckinPage(
        client: widget.client,
        config: widget.config,
      ),
      ConsolePage.secondMonitor => WalkInPage(
        client: cameraClient,
        config: widget.config,
        state: cameraState,
        onOpenKiosk: widget.onOpenKiosk ?? () async {},
      ),
      ConsolePage.supportReports => SupportReportsPage(client: widget.client),
      ConsolePage.migrasi => MigrateUserPage(client: widget.client),
      ConsolePage.reset => ResetDataPage(
        client: widget.client,
        config: widget.config,
      ),
    };

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 16 : 18,
        widget.embedded ? 0 : 18,
        widget.embedded ? 16 : 18,
        widget.embedded ? 16 : 18,
      ),
      child: Row(
        children: [
          _nav(),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.50),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: AppTheme.softShadow(0.16),
              ),
              clipBehavior: Clip.antiAlias,
              child: isi,
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: content),
      ),
    );
  }

  Widget _nav() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: _sidebarCollapsed ? 76 : 276,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071634),
            AppTheme.brandBlueDeep,
            AppTheme.brandBlue,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandGold.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(8, 0),
          ),
          const BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _navHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _navSection('OPERASIONAL'),
                _navItem(
                  ConsolePage.tamuArea,
                  Icons.meeting_room_outlined,
                  'Tamu di Area',
                ),
                _navItem(
                  ConsolePage.transporterArea,
                  Icons.local_shipping_outlined,
                  'Transporter di Area',
                ),
                _navItem(
                  ConsolePage.transporterCheckin,
                  Icons.how_to_reg_outlined,
                  'Konfirmasi Masuk',
                ),
                _navItem(
                  ConsolePage.transporterCheckout,
                  Icons.logout_outlined,
                  'Konfirmasi Keluar',
                ),
                _navItem(
                  ConsolePage.belumCheckin,
                  Icons.pending_actions_outlined,
                  'Belum Check-in',
                ),
                _navItem(
                  ConsolePage.internshipAttendance,
                  Icons.event_available_outlined,
                  'Absensi Magang & Vendor',
                ),
                _navSection('DATA & MASTER'),
                _navItem(
                  ConsolePage.manajemenTamu,
                  Icons.people_alt_outlined,
                  'Semua Profil',
                ),
                _navItem(
                  ConsolePage.vendorCompanies,
                  Icons.business_outlined,
                  'Perusahaan Vendor',
                ),
                _navItem(
                  ConsolePage.migrasi,
                  Icons.swap_horiz_outlined,
                  'Migrasi Tamu',
                ),
                _navSection('KAMERA & KIOSK'),
                _navItem(
                  ConsolePage.secondMonitor,
                  Icons.tablet_android_outlined,
                  'Second Monitor',
                ),
                _navItem(
                  ConsolePage.cariWajah,
                  Icons.person_search_outlined,
                  'Cari Wajah',
                ),
                _navItem(
                  ConsolePage.deteksi,
                  Icons.center_focus_strong_outlined,
                  'Deteksi & Embedding',
                ),
                if (widget.onOpenPreview != null)
                  _navAction(
                    Icons.videocam_outlined,
                    'Preview Kamera',
                    () => widget.onOpenPreview!(),
                  ),
                _navSection('PUSAT BANTUAN & SISTEM'),
                _navItem(
                  ConsolePage.supportReports,
                  Icons.support_agent_outlined,
                  'Laporan Error',
                ),
                _navItem(
                  ConsolePage.reset,
                  Icons.delete_forever_outlined,
                  'Reset Data',
                  tone: AppTheme.badRed,
                ),
              ],
            ),
          ),
          _navFooter(),
        ],
      ),
    );
  }

  Widget _navHeader() {
    if (_sidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.brandGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.brandGold.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.dashboard_customize_outlined,
                color: AppTheme.brandGold,
                size: 20,
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Perluas sidebar',
              child: IconButton(
                onPressed: () => setState(() => _sidebarCollapsed = false),
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.muted,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
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
                Icons.dashboard_customize_outlined,
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
                    'MODUL KONSOL',
                    style: TextStyle(
                      color: AppTheme.brandGold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Kelola Operasional POS',
                    style: TextStyle(
                      color: AppTheme.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Perkecil sidebar',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _sidebarCollapsed = true),
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppTheme.muted,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navFooter() {
    if (_sidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: Center(
          child: Tooltip(
            message: widget.embedded
                ? 'Kunci Konsol (${widget.session.email.isEmpty ? 'Admin' : widget.session.email})'
                : 'Kunci & Keluar (${widget.session.email.isEmpty ? 'Admin' : widget.session.email})',
            child: IconButton(
              onPressed: widget.embedded
                  ? () => setState(widget.session.lock)
                  : _lockAndExit,
              icon: const Icon(Icons.lock_outline, size: 18),
              style: IconButton.styleFrom(
                foregroundColor: AppTheme.mutedStrong,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: AppTheme.okGreen,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.session.email.isEmpty
                      ? 'Admin aktif'
                      : _maskedEmail(widget.session.email),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.embedded
                ? () => setState(widget.session.lock)
                : _lockAndExit,
            icon: const Icon(Icons.lock_outline, size: 15),
            label: Text(
              widget.embedded ? 'Kunci Konsol' : 'Kunci & Keluar',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.mutedStrong,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// [tone] menggantikan emas merek untuk menu yang perlu dibaca sebagai
  /// peringatan, bukan sekadar tujuan navigasi berikutnya.
  /// Judul kelompok di nav. Kecil, huruf besar, berjarak — cukup untuk
  /// memisahkan tanpa ikut tampak bisa diklik seperti menu.
  Widget _navSection(String judul) {
    if (_sidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        judul,
        style: TextStyle(
          color: AppTheme.brandGold.withValues(alpha: 0.85),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// Entri nav yang menjalankan aksi alih-alih berpindah halaman (mis.
  /// membuka jendela pratinjau). Dibuat seragam dengan entri biasa supaya
  /// operator tidak perlu tahu bedanya.
  Widget _navAction(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _sidebarCollapsed ? 8 : 10,
        vertical: 2,
      ),
      child: Tooltip(
        message: _sidebarCollapsed ? label : '',
        waitDuration: const Duration(milliseconds: 250),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: _sidebarCollapsed ? 6 : 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: _sidebarCollapsed
                  ? Center(child: _navIcon(icon, AppTheme.muted))
                  : Row(
                      children: [
                        const SizedBox(width: 3.5),
                        const SizedBox(width: 8),
                        _navIcon(icon, AppTheme.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    ConsolePage halaman,
    IconData icon,
    String label, {
    Color? tone,
  }) {
    final selected = halaman == _halaman;
    final accent = tone ?? AppTheme.brandGold;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _sidebarCollapsed ? 8 : 10,
        vertical: 2,
      ),
      child: Tooltip(
        message: _sidebarCollapsed ? label : '',
        waitDuration: const Duration(milliseconds: 250),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => setState(() => _halaman = halaman),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: _sidebarCollapsed ? 6 : 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: _sidebarCollapsed
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 3.5,
                            height: 20,
                            decoration: BoxDecoration(
                              color: selected ? accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        _navIcon(
                          icon,
                          selected ? accent : (tone ?? AppTheme.muted),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 3.5,
                          height: 22,
                          decoration: BoxDecoration(
                            color: selected ? accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _navIcon(
                          icon,
                          selected ? accent : (tone ?? AppTheme.muted),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.fg
                                  : (tone ?? AppTheme.muted),
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, Color color) {
    return Container(
      height: 32,
      width: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  String _maskedEmail(String email) {
    final trimmed = email.trim();
    final at = trimmed.indexOf('@');
    final name = at <= 0 ? trimmed : trimmed.substring(0, at);
    if (name.isEmpty) return 'Admin aktif';
    final visible = name.length <= 6 ? name : name.substring(0, 6);
    return '$visible***';
  }
}
