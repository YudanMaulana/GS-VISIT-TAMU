import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin HTTP client for the local sidecar API (`127.0.0.1:<port>`).
class SidecarClient {
  final int port;
  final http.Client _client = http.Client();

  SidecarClient(this.port);

  Uri _u(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<DetectionState> fetchState() async {
    final resp = await _client
        .get(_u('/state'))
        .timeout(const Duration(seconds: 5));
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return DetectionState.fromJson(json);
  }

  Future<CaptureResult> capture() async {
    final resp = await _client
        .post(_u('/capture'))
        .timeout(const Duration(seconds: 10));
    return CaptureResult.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<void> reset() =>
      _client.post(_u('/reset')).timeout(const Duration(seconds: 5));

  Future<Map<String, dynamic>> submit(String mode) async {
    final resp = await _client
        .post(
          _u('/submit'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'mode': mode}),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Read one visit's current state (via the sidecar, which holds the API key).
  /// The POS polls this to see when the guest has signed **in the Android app**.
  Future<Map<String, dynamic>> getVisit(Object visitId) async {
    final resp = await _client
        .post(
          _u('/visit'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'visit_id': visitId}),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // --- Login admin --------------------------------------------------------
  // Token sesinya hidup di sidecar, bukan di sini. GUI hanya menanyakan
  // "sudah masuk atau belum" dan menerima pesan galat siap tampil dari server.

  Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    final resp = await _client
        .post(
          _u('/admin_login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 30));
    return _decodeSidecarEnvelope(resp, route: '/admin_login');
  }

  /// Login admin dengan `id_token` Google. Jalan masuk pertama kali app
  /// dipasang, dan cadangan kalau kata sandi terlupa.
  Future<Map<String, dynamic>> adminGoogle(
    String idToken, {
    String? refreshToken,
  }) async {
    final resp = await _client
        .post(
          _u('/admin_google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id_token': idToken,
            'refresh_token': ?refreshToken,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return _decodeSidecarEnvelope(resp, route: '/admin_google');
  }

  Future<Map<String, dynamic>> adminConsoleCodeLogin(
    String idToken, {
    required String consoleCode,
    String? refreshToken,
  }) async {
    final resp = await _client
        .post(
          _u('/admin_console_code_login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id_token': idToken,
            'console_code': consoleCode,
            'refresh_token': ?refreshToken,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return _decodeSidecarEnvelope(resp, route: '/admin_console_code_login');
  }

  /// Cabang yang melekat pada kredensial mesin ini, menurut server.
  ///
  /// Inilah pengganti kolom cabang yang dulu diketik tangan di Pengaturan.
  /// Cabang yang diketik terpisah dari kredensialnya bisa berbeda darinya, dan
  /// bedanya baru ketahuan setelah ada check-in tercatat di cabang yang salah
  /// -- saat catatannya sudah telanjur ada.
  Future<Map<String, dynamic>> branchOfCredential() async {
    final resp = await _client
        .post(
          _u('/branch_of_credential'),
          headers: {'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 20));
    return _decodeSidecarEnvelope(resp, route: '/branch_of_credential');
  }

  /// "Token yang tersimpan di sidecar masih sah?" -- dipanggil saat konsol
  /// dibuka, bukan diasumsikan dari keberhasilan login yang lalu.
  Future<Map<String, dynamic>> adminMe() async {
    final resp = await _client
        .get(_u('/admin_me'))
        .timeout(const Duration(seconds: 20));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Ada/tidaknya sesi admin di sidecar ini. Tidak pernah mengembalikan
  /// tokennya sendiri.
  Future<Map<String, dynamic>> adminState() async {
    final resp = await _client
        .get(_u('/admin_state'))
        .timeout(const Duration(seconds: 10));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> adminSetPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final resp = await _client
        .post(
          _u('/admin_password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Catat sesi admin lokal (hasil login Google desktop yang emailnya sudah
  /// cocok) supaya alur browser tidak diulang tiap app dibuka. Yang disimpan
  /// hanya emailnya, di sisi sidecar — bukan token Google-nya.
  Future<Map<String, dynamic>> adminLocalLogin(String email) async {
    final resp = await _client
        .post(
          _u('/admin_local_login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 15));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> adminLogout() async {
    final resp = await _client
        .post(_u('/admin_logout'))
        .timeout(const Duration(seconds: 10));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Foto hasil [capture] terakhir sebagai base64 -- persis berkas yang akan
  /// dikirim ke server, jadi yang lolos penjagaan ketajaman itu juga yang
  /// tersimpan sebagai wajah tamu.
  Future<Map<String, dynamic>> lastStill() async {
    final resp = await _client
        .get(_u('/last_still'))
        .timeout(const Duration(seconds: 15));
    // 404 di sini artinya satu hal yang spesifik: proses sidecar yang berjalan
    // lebih tua daripada GUI ini. Itu terjadi kalau prefs menunjuk salinan
    // detector lain (mis. hasil ekstrak paket rilis) -- gejalanya menyamar
    // sebagai "foto tidak terbaca", padahal kameranya tidak salah apa-apa.
    if (resp.statusCode == 404) {
      return {'ok': false, 'stale_sidecar': true};
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Apakah proses sidecar yang berjalan sudah memuat rute pendaftaran tamu
  /// tanpa HP. Diperiksa sekali saat halaman dibuka, bukan saat tombol
  /// ditekan: lebih baik ketahuan sebelum tamu mengetik formulir yang tidak
  /// akan bisa dikirim.
  Future<bool> supportsWalkIn() async {
    try {
      final resp = await _client
          .get(_u('/last_still'))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode != 404;
    } catch (_) {
      return true; // gagal jaringan bukan bukti versi lama
    }
  }

  /// Daftarkan tamu yang tidak punya HP: tiga sudut wajah dari kamera pos
  /// dikirim sekaligus, dan sidecar yang menyusun multipart-nya.
  ///
  /// Timeout panjang: server menghitung tiga embedding sekaligus.
  Future<Map<String, dynamic>> registerWalkIn({
    required String frontalB64,
    required String leftB64,
    required String rightB64,
    required Map<String, String> fields,
  }) async {
    final resp = await _client
        .post(
          _u('/register_walk_in'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'frontal_b64': frontalB64,
            'left_b64': leftB64,
            'right_b64': rightB64,
            'fields': fields,
          }),
        )
        .timeout(const Duration(seconds: 150));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Unggah tanda tangan tamu untuk satu kunjungan.
  ///
  /// Inilah yang menggerbang check-out di server; tanda tangan PIC tetap
  /// opsional dan tidak dikirim dari kiosk.
  Future<Map<String, dynamic>> uploadSignature({
    required int visitId,
    required String pngBase64,
  }) async {
    final resp = await _client
        .post(
          _u('/visit_signature'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'visit_id': visitId, 'png_b64': pngBase64}),
        )
        .timeout(const Duration(seconds: 90));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Keadaan tamu hari ini: punya rencana atau tidak, statusnya, dan apakah
  /// tanda tangan tamu sudah masuk. Dihitung sidecar dari dua panggilan
  /// server sekaligus, supaya GUI tidak perlu tahu aturan mana yang menggerbang
  /// check-out.
  Future<Map<String, dynamic>> guestStatus(int visitorId) async {
    final resp = await _client
        .get(
          _u(
            '/guest_status',
          ).replace(queryParameters: {'visitor_id': '$visitorId'}),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Area di cabang POS ini, untuk formulir rencana kunjungan.
  Future<Map<String, dynamic>> areas() async {
    final resp = await _client
        .get(_u('/areas'))
        .timeout(const Duration(seconds: 25));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Materi safety induction dalam bahasa [lang].
  Future<Map<String, dynamic>> safetyInduction({String lang = 'id'}) async {
    final resp = await _client
        .get(_u('/safety_induction').replace(queryParameters: {'lang': lang}))
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Soal kuis safety dalam bahasa [lang]. Pilihan jawaban tidak membawa kunci
  /// jawaban — penilaian ada di server.
  Future<Map<String, dynamic>> safetyQuiz({String lang = 'id'}) async {
    final resp = await _client
        .get(_u('/safety_quiz').replace(queryParameters: {'lang': lang}))
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Kirim jawaban kuis. [answers] = {id soal: id pilihan}.
  Future<Map<String, dynamic>> submitSafetyQuiz({
    required int visitorId,
    required Map<int, int> answers,
  }) async {
    final resp = await _client
        .post(
          _u('/safety_quiz_submit'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'visitor_id': visitorId,
            'answers': answers.map((k, v) => MapEntry('$k', v)),
          }),
        )
        .timeout(const Duration(seconds: 40));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Buat rencana kunjungan. `branch_id` sengaja TIDAK dikirim dari sini:
  /// sidecar mengisinya dari cabang POS ini, karena cabang adalah fakta
  /// perangkat — bukan sesuatu yang boleh datang dari layar.
  Future<Map<String, dynamic>> createVisitPlan(
    Map<String, dynamic> payload,
  ) async {
    final resp = await _client
        .post(
          _u('/visit_plan'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 40));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Isikan email (+ nomor HP) ke tamu non-mobile supaya login Google-nya
  /// nanti mendarat di data ini.
  ///
  /// Mengembalikan amplop mentah, bukan melempar seperti [updateVisitor]:
  /// server membedakan 400 (alamat tanpa @), 409 (sudah tertaut, tidak boleh
  /// diambil alih), dan 404 (tamu tidak ada) — dan halaman migrasi perlu
  /// membedakan ketiganya, bukan sekadar tahu "gagal".
  Future<Map<String, dynamic>> migrateVisitor({
    required int visitorId,
    required String email,
    String? phone,
  }) async {
    final resp = await _client
        .post(
          _u('/visitor_update'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'visitor_id': visitorId,
            'fields': {
              'email': email,
              if (phone != null && phone.isNotEmpty) 'phone': phone,
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Siapkan tanda tangan petugas untuk konfirmasi transporter berikutnya.
  ///
  /// Disimpan di sidecar, bukan dikirim sendiri, karena tanda tangan dan foto
  /// wajah harus berangkat sebagai SATU permintaan check-in — server
  /// menetapkan jam masuk saat permintaan itu diterima, dan dua permintaan
  /// terpisah berarti dua waktu untuk satu kejadian.
  Future<Map<String, dynamic>> armOfficerSignature({
    required String pngB64,
    required String officerName,
  }) async {
    final resp = await _client
        .post(
          _u('/officer_signature'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'png_b64': pngB64, 'officer_name': officerName}),
        )
        .timeout(const Duration(seconds: 20));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Tambah satu baris muatan ke rencana bongkar muat.
  Future<Map<String, dynamic>> addLoad({
    required int planId,
    required Map<String, String> load,
  }) async {
    final resp = await _client
        .post(
          _u('/visit_load'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'plan_id': planId, 'load': load}),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Muatan satu rencana, dibaca ulang untuk memastikan barisnya benar-benar
  /// tersimpan — bukan memercayai status 200-nya.
  Future<List<Map<String, dynamic>>> loads(int planId) async {
    final resp = await _client
        .get(
          _u('/visit_loads').replace(queryParameters: {'plan_id': '$planId'}),
        )
        .timeout(const Duration(seconds: 25));
    final env = jsonDecode(resp.body) as Map<String, dynamic>;
    final body = env['body'];
    final list = body is List ? body : (body is Map ? body['loads'] : null);
    if (list is! List) return const [];
    return [
      for (final l in list)
        if (l is Map) Map<String, dynamic>.from(l),
    ];
  }

  /// Baca ulang satu tamu dari server.
  ///
  /// Dipakai untuk membuktikan hasil PATCH: server mengabaikan field yang
  /// tidak dikenalnya alih-alih menolak, jadi status 200 bukan bukti nilainya
  /// tersimpan.
  Future<VisitorRecord?> visitor(int visitorId) async {
    final resp = await _client
        .get(
          _u('/visitor').replace(queryParameters: {'visitor_id': '$visitorId'}),
        )
        .timeout(const Duration(seconds: 25));
    final env = jsonDecode(resp.body) as Map<String, dynamic>;
    final body = env['body'];
    if (env['ok'] != true || body is! Map) return null;
    final v = body['visitor'] ?? body;
    if (v is! Map) return null;
    return VisitorRecord.fromJson(Map<String, dynamic>.from(v));
  }

  /// Katalog kategori tamu untuk formulir kiosk. Daftarnya milik server --
  /// app tidak pernah mengetikkannya sendiri.
  Future<Map<String, dynamic>> guestCategories() async {
    final resp = await _client
        .get(_u('/guest_categories'))
        .timeout(const Duration(seconds: 25));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Wilayah administratif: tanpa [parentCode] mengembalikan provinsi, selain
  /// itu anak dari kode tersebut.
  Future<Map<String, dynamic>> regions({String? parentCode, String? q}) async {
    final uri = _u('/regions').replace(
      queryParameters: {
        if (parentCode != null && parentCode.isNotEmpty)
          'parent_code': parentCode,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final resp = await _client.get(uri).timeout(const Duration(seconds: 30));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Reset data masa pengujian lewat `/api/admin/reset` di server.
  ///
  /// [dryRun] memakai jalur yang sama tanpa menghapus apa pun, jadi pratinjau
  /// yang ditampilkan ke operator benar-benar mencerminkan apa yang akan
  /// hilang. Untuk eksekusi sungguhan, [confirm] harus berisi kalimat milik
  /// lingkupnya -- yang diketik operator sendiri, bukan diisi GUI.
  ///
  /// Timeout-nya panjang: server membuat backup DB + foto sebelum menghapus
  /// baris pertama, dan itu tumbuh seiring galeri.
  Future<Map<String, dynamic>> adminReset({
    required String scope,
    bool dryRun = false,
    String? confirm,
  }) async {
    final resp = await _client
        .post(
          _u('/admin_reset'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'scope': scope,
            if (dryRun) 'dry_run': true,
            if (!dryRun) 'confirm': confirm ?? '',
          }),
        )
        .timeout(const Duration(seconds: 200));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// List of Garudafood branches (Fase 2), for the Settings dropdown so the
  /// operator picks a cabang by name rather than typing a raw id.
  Future<Map<String, dynamic>> branches() async {
    final resp = await _client
        .get(_u('/branches'))
        .timeout(const Duration(seconds: 10));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Local webcams (laptop/USB) for the Settings dropdown. Pure hardware
  /// enumeration -- no server/API key involved, unlike [branches].
  Future<Map<String, dynamic>> cameras() async {
    final resp = await _client
        .get(_u('/cameras'))
        .timeout(const Duration(seconds: 5));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Face search: send an uploaded photo's JPEG bytes to the sidecar, which
  /// runs local MediaPipe detection (for the visual) and asks the server to
  /// match it against every stored visitor. The detection + model load can take
  /// a couple of seconds, hence the generous timeout.
  Future<FaceSearchResult> identifyPhoto(Uint8List jpeg) async {
    final resp = await _client
        .post(
          _u('/identify_photo'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'jpeg_b64': base64Encode(jpeg)}),
        )
        .timeout(const Duration(seconds: 45));
    return FaceSearchResult.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Detection + embedding pipeline spec, for the info page.
  Future<EngineInfo> engineInfo() async {
    final resp = await _client
        .get(_u('/engine_info'))
        .timeout(const Duration(seconds: 10));
    return EngineInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // --- Konsol Kelola Data ---------------------------------------------------
  // The sidecar owns the server connection, so every admin view goes through
  // it. Each returns the sidecar envelope {ok, status, body} / {ok, error};
  // [_unwrap] turns that into either the payload or a thrown message, so the
  // pages only ever deal with data or a string to show.

  static Map<String, dynamic> _decodeSidecarEnvelope(
    http.Response resp, {
    required String route,
  }) {
    final env = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 404 && env['error']?.toString() == 'not found') {
      return {
        'ok': false,
        'status': 404,
        'error':
            'Sidecar lokal tidak mengenal $route. Tutup semua jendela Garudashield Visit lalu buka lagi dari menu terbaru.',
      };
    }
    return env;
  }

  static Map<String, dynamic> _unwrap(http.Response resp) {
    final env = _decodeSidecarEnvelope(
      resp,
      route: resp.request?.url.path ?? '',
    );
    if (env['ok'] != true) {
      final err = env['error'] as String?;
      if (err != null) throw Exception(err);
      final body = env['body'];
      final msg = body is Map ? body['message'] ?? body['detail'] : null;
      throw Exception(
        msg?.toString() ?? 'Server menolak (HTTP ${env['status']})',
      );
    }
    final body = env['body'];
    return body is Map<String, dynamic> ? body : {'data': body};
  }

  /// Every enrolled guest. The server returns a bare JSON list here (not the
  /// usual `{success, ...}` envelope), so it arrives under `data`.
  Future<List<VisitorRecord>> visitors() async {
    final resp = await _client
        .get(_u('/visitors'))
        .timeout(const Duration(seconds: 30));
    final body = _unwrap(resp)['data'];
    return [
      for (final v in (body as List? ?? []))
        if (v is Map) VisitorRecord.fromJson(v.cast<String, dynamic>()),
    ];
  }

  /// PATCH one guest, returning the server's own updated copy so the list can
  /// refresh from truth rather than from what the form hoped it sent.
  /// [fields] must already be narrowed to what changed — see
  /// [VisitorRecord.diff], since the server treats a sent "" as "clear it".
  Future<VisitorRecord?> updateVisitor(
    int visitorId,
    Map<String, String> fields,
  ) async {
    final resp = await _client
        .post(
          _u('/visitor_update'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'visitor_id': visitorId, 'fields': fields}),
        )
        .timeout(const Duration(seconds: 25));
    final body = _unwrap(resp);
    if (body['success'] == false) {
      throw Exception(body['message']?.toString() ?? 'Gagal menyimpan.');
    }
    final v = body['visitor'];
    return v is Map ? VisitorRecord.fromJson(v.cast<String, dynamic>()) : null;
  }

  /// Tamu di Area. [date] is a local calendar date "YYYY-MM-DD"; omit for today.
  Future<ActiveGuestBoard> activeGuests({int? branchId, String? date}) async {
    final q = <String, String>{
      if (branchId != null && branchId > 0) 'branch_id': '$branchId',
      if (date != null && date.isNotEmpty) 'date': date,
    };
    final uri = Uri.parse(
      'http://127.0.0.1:$port/active_guests',
    ).replace(queryParameters: q.isEmpty ? null : q);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 25));
    return ActiveGuestBoard.fromJson(_unwrap(resp));
  }

  /// Visit-plan board. [status] takes one value or a comma-separated list; an
  /// unrecognised value returns an empty board server-side, not everything.
  Future<List<PlanRow>> visitPlans({String? status, int? branchId}) async {
    final q = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (branchId != null && branchId > 0) 'branch_id': '$branchId',
    };
    final uri = Uri.parse(
      'http://127.0.0.1:$port/visit_plans',
    ).replace(queryParameters: q.isEmpty ? null : q);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 25));
    final plans = _unwrap(resp)['plans'];
    return [
      for (final p in (plans as List? ?? []))
        if (p is Map) PlanRow.fromJson(p.cast<String, dynamic>()),
    ];
  }

  Future<List<InternshipVisitorRow>> internshipVisitors() async {
    final resp = await _client
        .get(_u('/internship_visitors'))
        .timeout(const Duration(seconds: 30));
    final body = _unwrap(resp);
    final list = body['visitors'] ?? body['data'] ?? body['items'];
    return [
      for (final v in (list as List? ?? const []))
        if (v is Map)
          InternshipVisitorRow.fromJson(Map<String, dynamic>.from(v)),
    ];
  }

  Future<InternshipAttendanceDetail> internshipAttendance({
    required int visitorId,
    String? month,
  }) async {
    final resp = await _client
        .get(
          _u('/internship_attendance').replace(
            queryParameters: {
              'visitor_id': '$visitorId',
              if (month != null && month.isNotEmpty) 'month': month,
            },
          ),
        )
        .timeout(const Duration(seconds: 30));
    return InternshipAttendanceDetail.fromJson(_unwrap(resp));
  }

  Future<void> saveInternshipContract({
    required int visitorId,
    required int branchId,
    required String startDate,
    required String endDate,
    required String workStart,
    required String workEnd,
    bool active = true,
  }) async {
    final resp = await _client
        .post(
          _u('/internship_contract'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'visitor_id': visitorId,
            'branch_id': branchId,
            'contract_start': startDate,
            'contract_end': endDate,
            'work_start': workStart,
            'work_end': workEnd,
            'active': active,
          }),
        )
        .timeout(const Duration(seconds: 30));
    _unwrap(resp);
  }

  Future<void> updateBranchAttendancePoint({
    required int branchId,
    required double lat,
    required double lng,
    required int radiusM,
  }) async {
    final resp = await _client
        .post(
          _u('/branch_attendance_point'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'branch_id': branchId,
            'attendance_lat': lat,
            'attendance_lng': lng,
            'attendance_radius_m': radiusM,
          }),
        )
        .timeout(const Duration(seconds: 30));
    _unwrap(resp);
  }

  Future<List<Map<String, dynamic>>> supportReports({
    bool unreadOnly = false,
  }) async {
    final resp = await _client
        .get(
          _u(
            '/support_reports',
          ).replace(queryParameters: {if (unreadOnly) 'unread_only': '1'}),
        )
        .timeout(const Duration(seconds: 30));
    final body = _unwrap(resp);
    final list = body['reports'] ?? body['items'] ?? body['data'];
    return [
      for (final item in (list as List? ?? const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  Future<void> replySupportReport({
    required int reportId,
    required String message,
    List<File> attachments = const [],
  }) async {
    final resp = await _client
        .post(
          _u('/support_report_reply'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'report_id': reportId,
            'message': message,
            'attachments': [
              for (final file in attachments)
                {
                  'filename': _fileNameOf(file.path),
                  'data_b64': base64Encode(await file.readAsBytes()),
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    _unwrap(resp);
  }

  Future<void> closeSupportReport({required int reportId}) async {
    final resp = await _client
        .post(
          _u('/support_report_close'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'report_id': reportId}),
        )
        .timeout(const Duration(seconds: 30));
    _unwrap(resp);
  }

  Future<List<VendorCompany>> fetchVendorCompanies() async {
    final resp = await _client
        .get(_u('/vendor_companies'))
        .timeout(const Duration(seconds: 25));
    final body = _unwrap(resp);
    final list = body['companies'] ?? body['data'] ?? body['items'];
    return [
      for (final item in (list as List? ?? const []))
        if (item is Map)
          VendorCompany.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<VendorCompany> saveVendorCompany({
    required String name,
    String companyType = 'PT',
    bool active = true,
    int? branchId,
  }) async {
    final resp = await _client
        .post(
          _u('/vendor_company_save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'company_type': companyType,
            'is_active': active,
            'branch_id': ?branchId,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = _unwrap(resp);
    final companyData = body['company'] ?? body['data'] ?? body;
    if (companyData is Map) {
      return VendorCompany.fromJson(Map<String, dynamic>.from(companyData));
    }
    return VendorCompany(
      id: 0,
      name: name,
      companyType: companyType,
      active: active,
    );
  }

  Future<void> toggleVendorCompanyStatus({
    required int id,
    required bool active,
  }) async {
    final resp = await _client
        .post(
          _u('/vendor_company_toggle'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': id,
            'is_active': active,
          }),
        )
        .timeout(const Duration(seconds: 25));
    _unwrap(resp);
  }

  Future<void> deleteVendorCompany({required int id}) async {
    final resp = await _client
        .post(
          _u('/vendor_company_delete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id': id}),
        )
        .timeout(const Duration(seconds: 25));
    _unwrap(resp);
  }

  /// A stored photo's bytes, or null if there is none / it failed. Never
  /// throws: a missing photo must degrade to a placeholder, not break a list.
  Future<Uint8List?> photo(String photoUrl) async {
    if (photoUrl.isEmpty) return null;
    try {
      final resp = await _client
          .post(
            _u('/photo'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'photo_url': photoUrl}),
          )
          .timeout(const Duration(seconds: 25));
      final env = jsonDecode(resp.body) as Map<String, dynamic>;
      if (env['ok'] != true) return null;
      return base64Decode(env['jpeg_b64'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> shutdown() async {
    try {
      await _client.post(_u('/shutdown')).timeout(const Duration(seconds: 2));
    } catch (_) {
      /* best effort */
    }
  }

  String _fileNameOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last.trim();
    return name.isEmpty ? 'lampiran' : name;
  }

  void close() => _client.close();
}
