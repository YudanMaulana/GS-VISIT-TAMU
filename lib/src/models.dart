import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One metric row, mirroring the Python `ReportLine` (label/value/ok). The
/// values and pass/fail flags are computed by the shared Python
/// `report.build_report_lines`, so this GUI never re-thresholds anything.
class ReportLine {
  final String label;
  final String value;
  final bool? ok; // true=OK, false=fail, null=informational/not evaluated

  ReportLine(this.label, this.value, this.ok);

  factory ReportLine.fromJson(Map<String, dynamic> j) =>
      ReportLine(j['label'] as String, j['value'] as String, j['ok'] as bool?);
}

/// A visitor record as returned by the server (fields per the Android
/// `Visitor` model).
class VisitorInfo {
  /// Id basis data tamu. Dibutuhkan untuk membuat rencana kunjungan dan
  /// mengirim jawaban kuis atas namanya — `visitor_code` bagus untuk dibaca
  /// manusia, tapi bukan yang diminta endpoint-endpoint itu.
  final int id;
  final String fullName;
  final String company;
  final String phone;
  final String purpose;
  final String visitorCode;

  VisitorInfo({
    this.id = 0,
    required this.fullName,
    required this.company,
    required this.phone,
    required this.purpose,
    required this.visitorCode,
  });

  factory VisitorInfo.fromJson(Map<String, dynamic> j) => VisitorInfo(
    id: (j['id'] as num?)?.toInt() ?? 0,
    fullName: j['full_name'] as String? ?? '',
    company: j['company'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    purpose: j['purpose'] as String? ?? '',
    visitorCode: j['visitor_code'] as String? ?? '',
  );
}

/// Outcome of a server submit (checkin/checkout/register): whether the face
/// was recognised/registered, the matched visitor, similarity, and the
/// visitor's stored reference photo. This is what the sidebar shows so it's
/// clear "terdaftar / tidak" plus the user's data.
class RecognitionResult {
  final bool ok; // HTTP-level success
  final bool success; // server body.success (face recognised / registered)
  final String mode; // checkin | checkout | register
  final String message;
  final double? similarity;
  final VisitorInfo? visitor;
  final String? visitType; // checkin | checkout (from visit)
  final Object? visitId; // visit.id — needed to attach signatures
  final bool signed; // visit already has a visitor signature
  final Uint8List? photo; // stored reference photo
  final String? error;

  RecognitionResult({
    required this.ok,
    required this.success,
    required this.mode,
    required this.message,
    this.similarity,
    this.visitor,
    this.visitType,
    this.visitId,
    this.signed = false,
    this.photo,
    this.error,
  });

  factory RecognitionResult.fromJson(Map<String, dynamic> j) {
    final body = j['body'];
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final visitorJson = map['visitor'];
    final visitJson = map['visit'];
    double? sim = (map['similarity'] as num?)?.toDouble();
    if (sim == null && visitJson is Map && visitJson['similarity'] is num) {
      sim = (visitJson['similarity'] as num).toDouble();
    }
    Uint8List? photo;
    final pb64 = j['photo_b64'] as String?;
    if (pb64 != null && pb64.isNotEmpty) photo = base64Decode(pb64);

    // `signature_visitor_url` on the visit is the server's own record that this
    // visit has been signed — the POS trusts that rather than local state, so a
    // restart or a second terminal still sees the truth.
    final signatureUrl = visitJson is Map
        ? visitJson['signature_visitor_url']
        : null;

    return RecognitionResult(
      ok: j['ok'] == true,
      success: j['success'] == true,
      mode: j['mode'] as String? ?? '',
      message: map['message'] as String? ?? (j['error'] as String? ?? ''),
      similarity: sim,
      visitor: visitorJson is Map<String, dynamic>
          ? VisitorInfo.fromJson(visitorJson)
          : null,
      visitType: visitJson is Map ? visitJson['type'] as String? : null,
      visitId: visitJson is Map ? visitJson['id'] : null,
      signed: signatureUrl != null && '$signatureUrl'.isNotEmpty,
      photo: photo,
      error: j['error'] as String?,
    );
  }
}

/// Live auto-identify result for the currently tracked face — the name drawn
/// on the bounding box. Produced by the side-effect-free
/// `POST /api/visitors/identify`, cached per face track by the sidecar so the
/// server is asked once per person, not once per frame.
class Identity {
  final bool recognized;
  final int visitorId;
  final String visitorCode;
  final String visitorType;
  final String? name;
  final double? similarity;
  final double? threshold;
  final String message;
  final String status; // 'ok' | 'error'

  Identity({
    required this.recognized,
    this.visitorId = 0,
    this.visitorCode = '',
    this.visitorType = '',
    this.name,
    this.similarity,
    this.threshold,
    this.message = '',
    this.status = 'ok',
  });

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
    recognized: j['recognized'] == true,
    visitorId: (j['visitor_id'] as num?)?.toInt() ?? 0,
    visitorCode: j['visitor_code'] as String? ?? '',
    visitorType: j['visitor_type'] as String? ?? '',
    name: j['name'] as String?,
    similarity: (j['similarity'] as num?)?.toDouble(),
    threshold: (j['threshold'] as num?)?.toDouble(),
    message: j['message'] as String? ?? '',
    status: j['status'] as String? ?? 'ok',
  );
}

/// Result of a capture (auto after 10 good frames, or forced via the button).
class CaptureResult {
  final bool ok;
  final bool forced;
  final String? filename;
  final bool sharp;
  final double variance;
  final Map<String, dynamic>? submit;

  CaptureResult({
    required this.ok,
    required this.forced,
    required this.filename,
    required this.sharp,
    required this.variance,
    required this.submit,
  });

  factory CaptureResult.fromJson(Map<String, dynamic> j) => CaptureResult(
    ok: j['ok'] == true,
    forced: j['forced'] == true,
    filename: j['filename'] as String?,
    sharp: j['sharp'] == true,
    variance: (j['variance'] as num?)?.toDouble() ?? 0,
    submit: j['submit'] as Map<String, dynamic>?,
  );
}

/// Parsed `/state` snapshot from the sidecar: the annotated video frame plus
/// every §3.1 metric and the derived verdict/streak.
class DetectionState {
  final String? error;
  final bool ready;
  final Uint8List? frameBytes; // decoded JPEG (with overlay already drawn)
  final int faceCount;

  /// Pose kepala dalam derajat, konvensi ML Kit (sudah dinormalkan analyzer).
  /// Dipakai panduan tiga sudut wajah: tanpa angka ini, satu-satunya penilaian
  /// yang tersedia adalah "bagus" milik sidecar — dan itu menuntut wajah
  /// menghadap lurus, sehingga sudut kiri/kanan tidak akan pernah lolos.
  final double? yaw;
  final double? pitch;
  final List<int>? bbox;
  final String message;
  final Color color;
  final bool good;
  final int goodStreak;
  final int stableThreshold;
  final List<ReportLine> lines;
  final bool serverConfigured;
  final String serverBaseUrl;
  final CaptureResult? lastCapture;
  final RecognitionResult? recognition;
  final Identity? identity;
  final bool identifying;
  final bool autoIdentify;
  final bool autoCheckin;
  final bool presenceEnabled;
  final bool? presencePresent;
  final bool presenceTofOk;
  final int? distanceMm;

  /// Hasil percobaan auto check-in terakhir, kalau ada. `state` salah satu
  /// dari: checked_in | no_plan | not_planned | rejected | error.
  final AutoCheckinResult? autoCheckinResult;
  final int? branchId; // Fase 2: null = POS belum diatur ke satu cabang

  DetectionState({
    this.error,
    this.ready = false,
    this.frameBytes,
    this.faceCount = 0,
    this.yaw,
    this.pitch,
    this.bbox,
    this.message = '',
    this.color = Colors.grey,
    this.good = false,
    this.goodStreak = 0,
    this.stableThreshold = 10,
    this.lines = const [],
    this.serverConfigured = false,
    this.serverBaseUrl = '',
    this.lastCapture,
    this.recognition,
    this.identity,
    this.identifying = false,
    this.autoIdentify = false,
    this.autoCheckin = false,
    this.presenceEnabled = false,
    this.presencePresent,
    this.presenceTofOk = false,
    this.distanceMm,
    this.autoCheckinResult,
    this.branchId,
  });

  factory DetectionState.error(String msg) => DetectionState(error: msg);

  factory DetectionState.fromJson(Map<String, dynamic> j) {
    final err = j['error'] as String?;
    if (err != null) {
      return DetectionState(error: err, ready: j['ready'] == true);
    }

    Uint8List? bytes;
    final b64 = j['jpeg_b64'] as String?;
    if (b64 != null && b64.isNotEmpty) bytes = base64Decode(b64);

    final c = (j['color'] as List?)?.cast<num>(); // BGR from OpenCV
    final color = c != null && c.length == 3
        ? Color.fromARGB(255, c[2].toInt(), c[1].toInt(), c[0].toInt())
        : Colors.grey;

    return DetectionState(
      ready: j['ready'] == true,
      frameBytes: bytes,
      faceCount: (j['face_count'] as num?)?.toInt() ?? 0,
      yaw: (j['yaw'] as num?)?.toDouble(),
      pitch: (j['pitch'] as num?)?.toDouble(),
      bbox: (j['bbox'] as List?)?.cast<num>().map((e) => e.toInt()).toList(),
      message: j['message'] as String? ?? '',
      color: color,
      good: j['good'] == true,
      goodStreak: (j['good_streak'] as num?)?.toInt() ?? 0,
      stableThreshold: (j['stable_threshold'] as num?)?.toInt() ?? 10,
      lines:
          (j['report_lines'] as List?)
              ?.map((e) => ReportLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      serverConfigured: j['server_configured'] == true,
      serverBaseUrl: j['server_base_url'] as String? ?? '',
      lastCapture: j['last_capture'] is Map<String, dynamic>
          ? CaptureResult.fromJson(j['last_capture'] as Map<String, dynamic>)
          : null,
      recognition: j['recognition'] is Map<String, dynamic>
          ? RecognitionResult.fromJson(j['recognition'] as Map<String, dynamic>)
          : null,
      identity: j['identity'] is Map<String, dynamic>
          ? Identity.fromJson(j['identity'] as Map<String, dynamic>)
          : null,
      identifying: j['identifying'] == true,
      autoCheckin: j['auto_checkin'] == true,
      presenceEnabled: j['presence_enabled'] == true,
      presencePresent: j['presence_present'] as bool?,
      presenceTofOk: j['presence_tof_ok'] == true,
      distanceMm: (j['distance_mm'] as num?)?.toInt(),
      autoCheckinResult: j['auto_checkin_result'] is Map
          ? AutoCheckinResult.fromJson(
              Map<String, dynamic>.from(j['auto_checkin_result'] as Map),
            )
          : null,
      autoIdentify: j['auto_identify'] == true,
      branchId: (j['branch_id'] as num?)?.toInt(),
    );
  }
}

/// A Garudafood branch (Fase 2), for the Settings dropdown.
class Branch {
  final int id;
  final String code;
  final String name;

  Branch({required this.id, required this.code, required this.name});

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
    id: (j['id'] as num).toInt(),
    code: j['code'] as String? ?? '',
    name: j['name'] as String? ?? '',
  );
}

/// A local webcam (laptop or USB) the sidecar found via `/cameras`, for the
/// Settings dropdown -- so the operator picks by name instead of guessing a
/// `/dev/videoN` index.
class CameraDevice {
  final int index;
  final String name;
  final String device;

  CameraDevice({required this.index, required this.name, required this.device});

  factory CameraDevice.fromJson(Map<String, dynamic> j) => CameraDevice(
    index: (j['index'] as num).toInt(),
    name: j['name'] as String? ?? '',
    device: j['device'] as String? ?? '',
  );
}

/// Local MediaPipe detection over an uploaded photo (the `detection` half of
/// the sidecar's `/identify_photo` reply). This is what makes the face
/// "benar-benar diperlihatkan": the annotated image + the §3.1 metrics the
/// engine actually computed, not just a yes/no.
class DetectionSnapshot {
  final bool found;
  final int faceCount;

  final List<int>? bbox; // x, y, w, h
  final double? yaw, pitch, roll;
  final double? brightness;
  final double? sharpnessVariance;
  final bool isSharp;
  final String message;
  final List<ReportLine> reportLines;
  final Uint8List? annotated; // JPEG with box + landmarks drawn

  DetectionSnapshot({
    required this.found,
    required this.faceCount,
    this.bbox,
    this.yaw,
    this.pitch,
    this.roll,
    this.brightness,
    this.sharpnessVariance,
    this.isSharp = false,
    this.message = '',
    this.reportLines = const [],
    this.annotated,
  });

  factory DetectionSnapshot.fromJson(Map<String, dynamic> j) {
    final ann = j['annotated_b64'] as String?;
    return DetectionSnapshot(
      found: j['found'] == true,
      faceCount: (j['face_count'] as num?)?.toInt() ?? 0,
      bbox: (j['bbox'] as List?)?.map((e) => (e as num).toInt()).toList(),
      yaw: (j['yaw'] as num?)?.toDouble(),
      pitch: (j['pitch'] as num?)?.toDouble(),
      roll: (j['roll'] as num?)?.toDouble(),
      brightness: (j['brightness'] as num?)?.toDouble(),
      sharpnessVariance: (j['sharpness_variance'] as num?)?.toDouble(),
      isSharp: j['is_sharp'] == true,
      message: j['message'] as String? ?? '',
      reportLines: (j['report_lines'] as List? ?? [])
          .map((e) => ReportLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      annotated: (ann != null && ann.isNotEmpty) ? base64Decode(ann) : null,
    );
  }
}

/// The server-side 1:N match half of `/identify_photo`: did any stored visitor
/// match this face, and how strongly vs. the server's own threshold.
class FaceMatch {
  final bool attempted; // false = no API key, server never asked
  final bool ok; // HTTP-level
  final bool success; // a visitor matched
  final String message;
  final double? similarity;
  final double? threshold;
  final VisitorInfo? visitor;
  final Uint8List? photo; // matched visitor's stored reference photo
  final String? error;

  FaceMatch({
    this.attempted = false,
    this.ok = false,
    this.success = false,
    this.message = '',
    this.similarity,
    this.threshold,
    this.visitor,
    this.photo,
    this.error,
  });

  factory FaceMatch.fromJson(Map<String, dynamic> j) {
    final body = j['body'];
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final visitorJson = map['visitor'];
    final pb64 = j['photo_b64'] as String?;
    return FaceMatch(
      attempted: j['attempted'] == true,
      ok: j['ok'] == true,
      success: j['success'] == true,
      message: map['message'] as String? ?? (j['error'] as String? ?? ''),
      similarity: (map['similarity'] as num?)?.toDouble(),
      threshold: (map['threshold'] as num?)?.toDouble(),
      visitor: visitorJson is Map<String, dynamic>
          ? VisitorInfo.fromJson(visitorJson)
          : null,
      photo: (pb64 != null && pb64.isNotEmpty) ? base64Decode(pb64) : null,
      error: j['error'] as String?,
    );
  }
}

/// Full `/identify_photo` reply: local detection + server match.
class FaceSearchResult {
  final bool ok;
  final String? error;
  final DetectionSnapshot? detection;
  final FaceMatch? match;

  FaceSearchResult({required this.ok, this.error, this.detection, this.match});

  factory FaceSearchResult.fromJson(Map<String, dynamic> j) {
    final det = j['detection'];
    final idn = j['identify'];
    return FaceSearchResult(
      ok: j['ok'] == true,
      error: j['error'] as String?,
      detection: det is Map<String, dynamic>
          ? DetectionSnapshot.fromJson(det)
          : null,
      match: idn is Map<String, dynamic> ? FaceMatch.fromJson(idn) : null,
    );
  }
}

/// One labelled spec row for the Detection & Embedding info page.
class SpecRow {
  final String label;
  final String value;
  const SpecRow(this.label, this.value);
}

/// Parsed `/engine_info`: the detection (local, MediaPipe) + embedding
/// (server, ArcFace) pipeline spec, grouped for display.
class EngineInfo {
  final List<SpecRow> detection;
  final List<SpecRow> embedding;
  final bool serverConfigured;
  final String serverBaseUrl;

  EngineInfo({
    required this.detection,
    required this.embedding,
    required this.serverConfigured,
    required this.serverBaseUrl,
  });

  static List<SpecRow> _rows(
    Map<String, dynamic> m,
    List<(String, String)> keys,
  ) => [
    for (final (k, label) in keys)
      if (m[k] != null) SpecRow(label, '${m[k]}'),
  ];

  factory EngineInfo.fromJson(Map<String, dynamic> j) {
    final det = (j['detection'] as Map?)?.cast<String, dynamic>() ?? {};
    final emb = (j['embedding'] as Map?)?.cast<String, dynamic>() ?? {};
    final srv = (j['server'] as Map?)?.cast<String, dynamic>() ?? {};
    return EngineInfo(
      detection: _rows(det, [
        ('engine', 'Engine'),
        ('model_file', 'Model'),
        ('landmarks', 'Landmark'),
        ('blendshapes', 'Blendshapes'),
        ('runs_on', 'Berjalan di'),
        ('purpose', 'Fungsi'),
      ]),
      embedding: _rows(emb, [
        ('engine', 'Engine'),
        ('dimensions', 'Dimensi'),
        ('detector', 'Detektor'),
        ('similarity', 'Kemiripan'),
        ('runs_on', 'Berjalan di'),
        ('note', 'Catatan'),
      ]),
      serverConfigured: srv['configured'] == true,
      serverBaseUrl: srv['base_url'] as String? ?? '',
    );
  }
}

/// Hasil satu percobaan auto check-in dari sidecar.
///
/// Wajah dikenali BUKAN berarti tamu boleh masuk: sidecar membaca rencana
/// kunjungannya dulu, dan hanya rencana berstatus `planned` yang di-check-in.
/// Sisanya dilaporkan apa adanya supaya operator tahu kenapa gerbang diam.
class AutoCheckinResult {
  /// checked_in | no_plan | not_planned | rejected | error
  final String state;
  final String name;
  final String message;

  AutoCheckinResult({
    required this.state,
    required this.name,
    required this.message,
  });

  bool get success => state == 'checked_in';

  /// Keadaan yang bukan salah siapa-siapa: tamu memang tidak punya rencana,
  /// atau sudah lewat gerbang. Tidak perlu ditampilkan sebagai kegagalan.
  bool get benign => state == 'no_plan' || state == 'not_planned';

  factory AutoCheckinResult.fromJson(Map<String, dynamic> j) =>
      AutoCheckinResult(
        state: j['state'] as String? ?? 'error',
        name: j['name'] as String? ?? '',
        message: j['message'] as String? ?? '',
      );
}

// --- Konsol Kelola Data ------------------------------------------------------
// Types below back the three admin pages. They are deliberately separate from
// [VisitorInfo] above: that one is the 5-field view a recognition result shows,
// this one is the full editable record with the id the PATCH needs.

/// Server timestamps are ISO-8601 UTC. Parse to local so every screen shows
/// the operator's own clock, and tolerate junk by returning null rather than
/// throwing inside a list builder.
DateTime? _serverDate(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// One enrolled guest, as `GET /api/visitors` returns them.
class VisitorRecord {
  final int id;
  final String visitorCode;
  final String visitorType;
  final String fullName;
  final String company;
  final String institutionName;
  final String major;
  final String phone;
  final String purpose;

  /// Masih dibaca dari server karena data lama memilikinya, tapi tidak lagi
  /// ditampilkan maupun disunting: tidak ada satu pun alur pendaftaran --
  /// mobile maupun non-mobile -- yang mengumpulkannya.
  final String dateOfBirth;
  final String guestCategory;
  final String address;
  final int safetyScore;
  final bool googleLinked;

  /// Nomor & masa berlaku SIM -- hanya diisi mobile app untuk transporter.
  /// Server tetap mengirimnya untuk semua jenis (kolomnya memang tidak
  /// dibatasi per jenis), tapi konsol hanya menampilkannya untuk transporter
  /// -- lihat `guest_management_page.dart`.
  final String simNumber;
  final String simExpiresAt;

  /// Alamat Google tamu. Sebelum tertaut ia janji ("kalau nanti login dengan
  /// email ini, kamu masuk ke data ini"); sesudah tertaut ia alamat yang sudah
  /// diverifikasi Google.
  ///
  /// Sengaja TIDAK ikut di [editable]: mengubahnya berarti memindahkan siapa
  /// yang berhak atas data ini, dan itu tidak boleh tercampur dengan
  /// penyuntingan kolom biasa yang dilakukan sambil lalu. Ada halamannya
  /// sendiri (Migrasi Tamu) dengan konfirmasi.
  final String email;

  /// Tamu yang didaftarkan petugas di pos karena tidak punya HP. Server
  /// memakai ini untuk mencoret "Nomor HP" dari daftar wajib -- hanya untuk
  /// tamu ini. Ditampilkan sebagai chip supaya operator tidak melihat nomor
  /// kosong lalu mengira datanya belum selesai diisi.
  final bool walkIn;
  final String photoUrl;
  final DateTime? createdAt;

  VisitorRecord({
    required this.id,
    required this.visitorCode,
    required this.visitorType,
    required this.fullName,
    required this.company,
    this.institutionName = '',
    this.major = '',
    required this.phone,
    required this.purpose,
    required this.dateOfBirth,
    required this.guestCategory,
    required this.address,
    required this.safetyScore,
    required this.googleLinked,
    this.email = '',
    required this.walkIn,
    required this.photoUrl,
    required this.createdAt,
    this.simNumber = '',
    this.simExpiresAt = '',
  });

  /// The only fields `PATCH /api/visitors/{id}` accepts. `visitor_code`, the
  /// Google link and the face embedding are unreachable through it by design,
  /// so they are shown read-only and never keyed here.
  ///
  /// `sim_expires_at`: server-side `UpdateVisitorRequest` types it as a real
  /// date, not a string -- sending "" to try to clear it is expected to
  /// fail validation (422) rather than clear it. That's an acceptable
  /// failure mode (a visible error, not silent data loss), so it is kept
  /// editable rather than blocked on that one edge case.
  Map<String, String> get editable => {
    'full_name': fullName,
    'company': company,
    'phone': phone,
    'guest_category': guestCategory,
    'address': address,
    'visitor_type': visitorType,
    'sim_number': simNumber,
    'sim_expires_at': simExpiresAt,
  };

  /// Only what actually changed. The server honours an explicitly-sent "" as
  /// "clear this field", so sending the untouched whole form would quietly
  /// rewrite fields the operator never looked at — this keeps a save narrow.
  Map<String, String> diff(Map<String, String> edited) {
    final before = editable;
    return {
      for (final e in edited.entries)
        if (before[e.key] != e.value) e.key: e.value,
    };
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        company.toLowerCase().contains(q) ||
        phone.toLowerCase().contains(q) ||
        visitorCode.toLowerCase().contains(q) ||
        // Email ikut dicari karena ia yang dipakai operator saat menelusuri
        // tamu yang mengeluh tidak bisa login: yang orang itu tahu tentang
        // dirinya adalah alamat Google-nya, bukan kode tamunya.
        email.toLowerCase().contains(q);
  }

  factory VisitorRecord.fromJson(Map<String, dynamic> j) => VisitorRecord(
    id: (j['id'] as num?)?.toInt() ?? 0,
    visitorCode: j['visitor_code'] as String? ?? '',
    visitorType: j['visitor_type'] as String? ?? 'tamu',
    fullName: j['full_name'] as String? ?? '',
    company: j['company'] as String? ?? '',
    institutionName:
        j['institution_name']?.toString() ??
        j['school_name']?.toString() ??
        j['university_name']?.toString() ??
        '',
    major: j['major']?.toString() ?? '',
    phone: j['phone'] as String? ?? '',
    purpose: j['purpose'] as String? ?? '',
    dateOfBirth: j['date_of_birth'] as String? ?? '',
    guestCategory: j['guest_category'] as String? ?? '',
    address: j['address'] as String? ?? '',
    safetyScore: (j['safety_score'] as num?)?.toInt() ?? 0,
    googleLinked: j['google_linked'] == true,
    email: j['email'] as String? ?? '',
    walkIn: j['walk_in'] == true,
    photoUrl: j['photo_url'] as String? ?? '',
    createdAt: _serverDate(j['created_at']),
    simNumber: j['sim_number'] as String? ?? '',
    simExpiresAt: j['sim_expires_at'] as String? ?? '',
  );
}

/// One row of the "Tamu di Area" board. `currentStep` / `missingFields` are
/// *derived server-side* (active_guest_service) — this GUI never recomputes
/// progress, so the patrol app and this console can never disagree.
class ActiveGuestRow {
  final int planId;
  final int visitorId;
  final String name;
  final String company;
  final String picTarget;
  final String purpose;
  final String phone;
  final String status;
  final String photoUrl;
  final DateTime? checkinAt;
  final DateTime? checkoutAt;
  final bool formComplete;
  final bool checkoutComplete;
  final int currentStep;
  final List<String> missingFields;

  // --- Fase transporter -----------------------------------------------------
  // Papan yang sama melayani dua jenis pengunjung; `visitorType` yang
  // memisahkannya. Field di bawah hanya terisi untuk transporter, dan itu
  // disengaja: papan tamu tidak perlu tahu soal plat maupun SIM.

  /// 'tamu' | 'transporter' | 'magang' | 'vendor'.
  final String visitorType;

  /// Masa berlaku SIM sopir; kosong = tidak diketahui, BUKAN kedaluwarsa.
  final String simExpiresAt;

  /// Ditandai server, bukan dihitung ulang di sini — supaya papan POS dan app
  /// patroli tidak bisa berbeda pendapat soal tanggal yang sama.
  final bool simExpired;

  final String vehiclePlate;
  final String vehicleType;

  /// 'bongkar' | 'muat' | 'bongkar_muat' | '' (belum dipilih / tamu).
  final String loadType;

  /// Berapa baris muatan di rencana ini, dan nomor shipment pertamanya.
  /// Papan adalah daftar, bukan surat jalan: sisanya dibuka di detail.
  final int loadCount;
  final String firstShipmentNo;
  final int queueNumber;

  bool get isTransporter => visitorType == 'transporter';
  bool get dibatalkan =>
      status == 'expired' || status == 'cancelled' || status == 'batal';

  ActiveGuestRow({
    required this.planId,
    required this.visitorId,
    required this.name,
    required this.company,
    required this.picTarget,
    required this.purpose,
    required this.phone,
    required this.status,
    required this.photoUrl,
    required this.checkinAt,
    required this.checkoutAt,
    required this.formComplete,
    required this.checkoutComplete,
    required this.currentStep,
    required this.missingFields,
    this.visitorType = 'tamu',
    this.simExpiresAt = '',
    this.simExpired = false,
    this.vehiclePlate = '',
    this.vehicleType = '',
    this.loadType = '',
    this.loadCount = 0,
    this.firstShipmentNo = '',
    this.queueNumber = 0,
  });

  /// Still physically on site: checked in, not yet checked out, and not cancelled.
  bool get onSite => checkinAt != null && checkoutAt == null && !dibatalkan;

  factory ActiveGuestRow.fromJson(Map<String, dynamic> j) => ActiveGuestRow(
    planId: (j['plan_id'] as num?)?.toInt() ?? 0,
    visitorId: (j['visitor_id'] as num?)?.toInt() ?? 0,
    name: j['name'] as String? ?? '',
    company: j['company'] as String? ?? '',
    picTarget: j['pic_target'] as String? ?? '',
    purpose: j['purpose'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    status: j['status'] as String? ?? '',
    photoUrl: j['photo_url'] as String? ?? '',
    checkinAt: _serverDate(j['checkin_at']),
    checkoutAt: _serverDate(j['checkout_at']),
    formComplete: j['form_complete'] == true,
    checkoutComplete: j['checkout_complete'] == true,
    currentStep: (j['current_step'] as num?)?.toInt() ?? 0,
    missingFields: [for (final f in (j['missing_fields'] as List? ?? [])) '$f'],
    visitorType: j['visitor_type'] as String? ?? 'tamu',
    simExpiresAt: j['sim_expires_at'] as String? ?? '',
    simExpired: j['sim_expired'] == true,
    vehiclePlate: j['vehicle_plate'] as String? ?? '',
    vehicleType: j['vehicle_type'] as String? ?? '',
    loadType: j['load_type'] as String? ?? '',
    loadCount: (j['load_count'] as num?)?.toInt() ?? 0,
    firstShipmentNo: j['first_shipment_no'] as String? ?? '',
    queueNumber: (j['queue_number'] as num?)?.toInt() ??
        (j['plan_id'] as num?)?.toInt() ??
        0,
  );
}

/// `GET /api/active-guests/today`: the board plus its counters and the date
/// the server considers "today" (its WIB day, not this PC's).
class ActiveGuestBoard {
  final String date;
  final int total;
  final int checkedOut;
  final int notCheckedOut;
  final int formComplete;
  final List<ActiveGuestRow> guests;

  ActiveGuestBoard({
    required this.date,
    required this.total,
    required this.checkedOut,
    required this.notCheckedOut,
    required this.formComplete,
    required this.guests,
  });

  factory ActiveGuestBoard.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return ActiveGuestBoard(
      date: j['date'] as String? ?? '',
      total: (s['total'] as num?)?.toInt() ?? 0,
      checkedOut: (s['checked_out'] as num?)?.toInt() ?? 0,
      notCheckedOut: (s['not_checked_out'] as num?)?.toInt() ?? 0,
      formComplete: (s['form_complete'] as num?)?.toInt() ?? 0,
      guests: [
        for (final g in (j['guests'] as List? ?? []))
          if (g is Map) ActiveGuestRow.fromJson(g.cast<String, dynamic>()),
      ],
    );
  }
}

/// One row of `GET /api/visit-plans` — a plan plus the compact visitor and
/// branch summaries that endpoint attaches.
class PlanRow {
  final int id;
  final int visitorId;
  final String status;
  final String visitorName;
  final String company;
  final String photoUrl;
  final String branchName;
  final String picTarget;
  final String purpose;
  final DateTime? createdAt;
  final DateTime? visitDate;

  PlanRow({
    required this.id,
    required this.visitorId,
    required this.status,
    required this.visitorName,
    required this.company,
    required this.photoUrl,
    required this.branchName,
    required this.picTarget,
    required this.purpose,
    required this.createdAt,
    required this.visitDate,
  });

  factory PlanRow.fromJson(Map<String, dynamic> j) {
    final v = (j['visitor'] as Map?)?.cast<String, dynamic>() ?? {};
    final b = (j['branch'] as Map?)?.cast<String, dynamic>() ?? {};
    return PlanRow(
      id: (j['id'] as num?)?.toInt() ?? 0,
      visitorId: (j['visitor_id'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? '',
      visitorName: v['full_name'] as String? ?? '(tanpa nama)',
      company: v['company'] as String? ?? '',
      photoUrl: v['photo_url'] as String? ?? '',
      branchName: b['name'] as String? ?? '',
      picTarget: j['pic_target'] as String? ?? '',
      purpose: j['purpose'] as String? ?? '',
      createdAt: _serverDate(j['created_at']),
      visitDate: _serverDate(j['visit_date']),
    );
  }
}

class InternshipVisitorRow {
  final int id;
  final String visitorCode;
  final String fullName;
  final String institutionName;
  final String major;
  final String phone;
  final String email;
  final String branchName;
  final InternshipContract? contract;
  final String visitorType;
  final String company;

  InternshipVisitorRow({
    required this.id,
    required this.visitorCode,
    required this.fullName,
    required this.institutionName,
    required this.major,
    required this.phone,
    required this.email,
    required this.branchName,
    this.contract,
    this.visitorType = 'magang',
    this.company = '',
  });

  bool get isVendor => visitorType == 'vendor';

  factory InternshipVisitorRow.fromJson(Map<String, dynamic> j) {
    final contract = j['contract'];
    final branch = (j['branch'] as Map?)?.cast<String, dynamic>() ?? {};
    final vType = j['visitor_type']?.toString() ?? 'magang';
    final comp = j['company']?.toString() ?? '';
    return InternshipVisitorRow(
      id: (j['id'] as num?)?.toInt() ?? (j['visitor_id'] as num?)?.toInt() ?? 0,
      visitorCode: j['visitor_code']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? j['name']?.toString() ?? '',
      institutionName:
          j['institution_name']?.toString() ??
          j['school_name']?.toString() ??
          j['university_name']?.toString() ??
          (vType == 'vendor' ? comp : ''),
      major: j['major']?.toString() ?? '',
      phone: j['phone']?.toString() ?? '',
      email: j['email']?.toString() ?? '',
      branchName:
          j['branch_name']?.toString() ?? branch['name']?.toString() ?? '',
      contract: contract is Map
          ? InternshipContract.fromJson(Map<String, dynamic>.from(contract))
          : null,
      visitorType: vType,
      company: comp,
    );
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        visitorCode.toLowerCase().contains(q) ||
        institutionName.toLowerCase().contains(q) ||
        company.toLowerCase().contains(q) ||
        visitorType.toLowerCase().contains(q) ||
        major.toLowerCase().contains(q) ||
        phone.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q);
  }
}

class InternshipContract {
  final int id;
  final int visitorId;
  final int? branchId;
  final String branchName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String workStart;
  final String workEnd;
  final bool active;

  InternshipContract({
    required this.id,
    required this.visitorId,
    this.branchId,
    required this.branchName,
    required this.startDate,
    required this.endDate,
    required this.workStart,
    required this.workEnd,
    required this.active,
  });

  factory InternshipContract.fromJson(Map<String, dynamic> j) {
    final branch = (j['branch'] as Map?)?.cast<String, dynamic>() ?? {};
    return InternshipContract(
      id: (j['id'] as num?)?.toInt() ?? 0,
      visitorId: (j['visitor_id'] as num?)?.toInt() ?? 0,
      branchId: (j['branch_id'] as num?)?.toInt(),
      branchName:
          j['branch_name']?.toString() ?? branch['name']?.toString() ?? '',
      startDate: _dateOnly(j['start_date'] ?? j['contract_start']),
      endDate: _dateOnly(j['end_date'] ?? j['contract_end']),
      workStart: j['work_start']?.toString() ?? '08:00',
      workEnd: j['work_end']?.toString() ?? '16:00',
      active: j['active'] != false,
    );
  }
}

class InternshipAttendanceLog {
  final DateTime workDate;
  final DateTime? checkinAt;
  final DateTime? checkoutAt;
  final String status;
  final double? checkinDistanceM;
  final double? checkoutDistanceM;

  InternshipAttendanceLog({
    required this.workDate,
    required this.checkinAt,
    required this.checkoutAt,
    required this.status,
    this.checkinDistanceM,
    this.checkoutDistanceM,
  });

  bool get present => checkinAt != null || status == 'present';

  factory InternshipAttendanceLog.fromJson(Map<String, dynamic> j) =>
      InternshipAttendanceLog(
        workDate:
            _dateOnly(j['work_date'] ?? j['date']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        checkinAt: _serverDate(j['checkin_at'] ?? j['check_in_at']),
        checkoutAt: _serverDate(j['checkout_at'] ?? j['check_out_at']),
        status: j['status']?.toString() ?? '',
        checkinDistanceM: (j['checkin_distance_m'] as num?)?.toDouble(),
        checkoutDistanceM: (j['checkout_distance_m'] as num?)?.toDouble(),
      );
}

class InternshipAttendanceDetail {
  final InternshipVisitorRow? visitor;
  final InternshipContract? contract;
  final List<InternshipAttendanceLog> logs;

  InternshipAttendanceDetail({
    required this.visitor,
    required this.contract,
    required this.logs,
  });

  factory InternshipAttendanceDetail.fromJson(Map<String, dynamic> j) {
    final visitor = j['visitor'];
    final contract = j['contract'];
    final list = j['attendance'] ?? j['logs'] ?? j['days'] ?? j['data'];
    return InternshipAttendanceDetail(
      visitor: visitor is Map
          ? InternshipVisitorRow.fromJson(Map<String, dynamic>.from(visitor))
          : null,
      contract: contract is Map
          ? InternshipContract.fromJson(Map<String, dynamic>.from(contract))
          : null,
      logs: [
        for (final item in (list as List? ?? const []))
          if (item is Map)
            InternshipAttendanceLog.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

DateTime? _dateOnly(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString();
  if (text.isEmpty) return null;
  final date = DateTime.tryParse(text);
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}

/// Akun admin sebagaimana dilaporkan server. Tidak ada kata sandi maupun token
/// di sini: token hidup di sidecar, dan kata sandi tidak pernah menyentuh app.
class AdminAccount {
  final int id;
  final String email;
  final String fullName;
  final String googleEmail;
  final bool active;

  AdminAccount({
    required this.id,
    required this.email,
    required this.fullName,
    required this.googleEmail,
    required this.active,
  });

  factory AdminAccount.fromJson(Map<String, dynamic> j) => AdminAccount(
    id: (j['id'] as num?)?.toInt() ?? 0,
    email: j['email'] as String? ?? '',
    fullName: j['full_name'] as String? ?? '',
    googleEmail: j['google_email'] as String? ?? '',
    active: j['active'] != false,
  );
}

/// Balasan login admin. [message] datang dari server dan ditampilkan apa
/// adanya -- pesan rem percobaan menyebut sisa detiknya, dan menggantinya
/// dengan "Login gagal" membuang satu-satunya petunjuk kenapa kata sandi yang
/// benar pun ditolak.
class AdminLoginResult {
  final bool success;
  final String message;
  final AdminAccount? admin;
  final bool mustSetPassword;

  AdminLoginResult({
    required this.success,
    required this.message,
    required this.admin,
    required this.mustSetPassword,
  });

  factory AdminLoginResult.fromEnvelope(Map<String, dynamic> envelope) {
    final body = envelope['body'];
    if (body is! Map) {
      return AdminLoginResult(
        success: false,
        message:
            envelope['error']?.toString() ?? 'Tidak bisa menghubungi server.',
        admin: null,
        mustSetPassword: false,
      );
    }
    final map = Map<String, dynamic>.from(body);
    final admin = map['admin'];
    return AdminLoginResult(
      success: map['success'] == true,
      message: map['message']?.toString() ?? '',
      admin: admin is Map
          ? AdminAccount.fromJson(Map<String, dynamic>.from(admin))
          : null,
      mustSetPassword: map['must_set_password'] == true,
    );
  }
}

/// Satu wilayah administratif (provinsi/kabupaten/kecamatan/desa) dari
/// `GET /api/regions`. Kodenya BPS; server yang menyusun kolom `address` yang
/// terbaca, jadi app tidak pernah merangkai namanya sendiri.
class Region {
  final String code;
  final String name;

  Region({required this.code, required this.name});

  factory Region.fromJson(Map<String, dynamic> j) => Region(
    code: j['code']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
  );
}

/// Hasil `POST /api/visitors/register` untuk tamu tanpa HP.
///
/// [embeddingsSaved] wajib diperiksa, bukan sekadar [success]: kalau `photos`
/// atau `angles` tidak terkirim sebagai field berulang, server tetap membalas
/// sukses tetapi hanya menyimpan satu embedding -- dan kegagalan itu baru
/// terasa berbulan-bulan kemudian saat wajah tamu sulit dikenali.
class WalkInResult {
  final bool success;
  final String message;
  final String visitorCode;
  final int visitorId;
  final int embeddingsSaved;

  WalkInResult({
    required this.success,
    required this.message,
    required this.visitorCode,
    required this.visitorId,
    required this.embeddingsSaved,
  });

  bool get allAnglesSaved => embeddingsSaved >= 3;

  factory WalkInResult.fromEnvelope(Map<String, dynamic> envelope) {
    final body = envelope['body'];
    if (body is! Map) {
      return WalkInResult(
        success: false,
        message:
            envelope['error']?.toString() ?? 'Tidak bisa menghubungi server.',
        visitorCode: '',
        visitorId: 0,
        embeddingsSaved: 0,
      );
    }
    final map = Map<String, dynamic>.from(body);
    final visitor = map['visitor'];
    final v = visitor is Map ? Map<String, dynamic>.from(visitor) : const {};
    return WalkInResult(
      success: map['success'] == true,
      message: map['message']?.toString() ?? '',
      visitorCode: v['visitor_code']?.toString() ?? '',
      visitorId: (v['id'] as num?)?.toInt() ?? 0,
      embeddingsSaved: (map['embeddings_saved'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Perusahaan vendor yang diizinkan (whitelist).
///
/// Jika [active] bernilai false, seluruh anggota vendor dari perusahaan ini
/// tidak diperkenankan melakukan absensi (check-in / check-out).
class VendorCompany {
  final int id;
  final String name;
  final String companyType;
  final bool active;
  final int? branchId;
  final String? branchName;
  final int memberCount;
  final DateTime? createdAt;

  VendorCompany({
    required this.id,
    required this.name,
    this.companyType = 'PT',
    this.active = true,
    this.branchId,
    this.branchName,
    this.memberCount = 0,
    this.createdAt,
  });

  bool matches(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        companyType.toLowerCase().contains(query) ||
        (branchName ?? '').toLowerCase().contains(query);
  }

  factory VendorCompany.fromJson(Map<String, dynamic> j) {
    final rawCreated = j['created_at']?.toString();
    return VendorCompany(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: j['name'] as String? ?? '',
      companyType:
          j['company_type'] as String? ?? (j['type'] as String? ?? 'PT'),
      active: j['is_active'] != false && j['active'] != false,
      branchId: (j['branch_id'] as num?)?.toInt(),
      branchName: j['branch_name'] as String?,
      memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      createdAt: rawCreated != null ? DateTime.tryParse(rawCreated) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company_type': companyType,
    'is_active': active,
    if (branchId != null) 'branch_id': branchId,
  };
}
