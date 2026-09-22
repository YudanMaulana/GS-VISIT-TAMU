import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Google Sign-In for Linux desktop via the OAuth 2.0 **loopback** flow (the
/// only supported desktop path — the mobile `google_sign_in` plugin has no
/// Linux backend).
///
/// Flow: PKCE challenge -> spin a one-shot HTTP server on 127.0.0.1 -> open the
/// system browser to Google's consent page -> capture the redirected code ->
/// exchange it (with the PKCE verifier) for an `id_token` -> read the verified
/// email from that token.
///
/// The `id_token` is minted by Google's token endpoint and arrives here over
/// TLS, not through any untrusted party, so reading its payload for the email
/// (plus checking `aud` and `email_verified`) is enough for this local admin
/// gate — we are not standing in for the server's own verification.
class GoogleDesktopAuth {
  final String clientId;
  final String clientSecret;

  GoogleDesktopAuth({required this.clientId, required this.clientSecret});

  static final _rand = Random.secure();

  /// Alur penuh, mengembalikan **email** akun Google. Dipakai kalau app hanya
  /// perlu tahu siapa yang masuk.
  Future<String> signInEmail({Duration timeout = const Duration(minutes: 3)}) async =>
      _verifiedEmail(await signInIdToken(timeout: timeout));

  /// Alur penuh, mengembalikan `id_token` mentahnya.
  ///
  /// Dipakai untuk login admin: token diserahkan ke server, dan **server**
  /// yang memverifikasinya ke Google lalu memutuskan akun ini admin atau
  /// bukan. App tidak pernah menyimpulkan sendiri siapa yang berwenang.
  /// Throws [GoogleAuthException] on cancel/mismatch/failure.
  /// Refresh token dari alur terakhir, kalau Google menerbitkannya. Disimpan
  /// pemanggil (sidecar) supaya sesi bisa diperbarui tanpa browser.
  String? lastRefreshToken;

  Future<String> signInIdToken({Duration timeout = const Duration(minutes: 3)}) async {
    final verifier = _randomUrlSafe(64);
    final challenge = _b64Url(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _randomUrlSafe(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    try {
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        // offline + consent: hanya dengan keduanya Google menerbitkan
        // refresh_token. Tanpa itu, sesi admin mati tiap kali token server
        // kedaluwarsa (12 jam) dan operator harus mengulang alur browser --
        // "login Google sekali saat pasang" jadi tidak pernah benar-benar
        // sekali.
        'access_type': 'offline',
        'prompt': 'consent select_account',
      });

      await _openBrowser(authUrl.toString());
      final code = await _awaitRedirect(server, state).timeout(
        timeout,
        onTimeout: () => throw const GoogleAuthException('Waktu masuk Google habis.'),
      );

      return await _exchange(code, verifier, redirectUri);
    } finally {
      await server.close(force: true);
    }
  }

  /// Wait for Google to redirect back with `?code=...&state=...`, answer the
  /// browser with a friendly page, and return the code.
  Future<String> _awaitRedirect(HttpServer server, String expectedState) async {
    await for (final req in server) {
      final params = req.uri.queryParameters;
      final error = params['error'];
      final code = params['code'];
      final state = params['state'];

      final ok = error == null && code != null && state == expectedState;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok));
      await req.response.close();

      if (error != null) {
        throw GoogleAuthException('Google menolak: $error');
      }
      if (state != expectedState) {
        throw const GoogleAuthException('State tidak cocok (kemungkinan gangguan keamanan).');
      }
      if (code != null) return code;
    }
    throw const GoogleAuthException('Tidak ada kode otorisasi diterima.');
  }

  Future<String> _exchange(String code, String verifier, String redirectUri) async {
    final resp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );
    if (resp.statusCode != 200) {
      throw GoogleAuthException('Tukar token gagal (${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    lastRefreshToken = data['refresh_token'] as String? ?? lastRefreshToken;
    final idToken = data['id_token'] as String?;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleAuthException('Respons Google tanpa id_token.');
    }
    return idToken;
  }

  /// Read + sanity-check the id_token payload. Not full signature verification:
  /// the token came straight from Google's TLS token endpoint above.
  String _verifiedEmail(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) throw const GoogleAuthException('id_token tidak valid.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;

    if (payload['aud'] != clientId) {
      throw const GoogleAuthException('Token bukan untuk aplikasi ini (aud tidak cocok).');
    }
    if (payload['email_verified'] != true) {
      throw const GoogleAuthException('Email Google belum terverifikasi.');
    }
    final email = payload['email'] as String?;
    if (email == null || email.isEmpty) {
      throw const GoogleAuthException('Token tanpa email.');
    }
    return email;
  }

  static Future<void> _openBrowser(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else {
        await Process.start('xdg-open', [url]);
      }
    } catch (_) {
      throw const GoogleAuthException('Tidak bisa membuka browser.');
    }
  }

  static String _randomUrlSafe(int bytes) =>
      _b64Url(List<int>.generate(bytes, (_) => _rand.nextInt(256)));

  static String _b64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _resultPage(bool ok) => '''
<!doctype html><html lang="id"><head><meta charset="utf-8">
<title>Visit</title>
<style>body{font-family:sans-serif;background:#071634;color:#EAF2FF;
display:flex;height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}
.card{max-width:420px;padding:32px}h1{color:${ok ? '#5BDFC1' : '#FF6B6B'}}</style></head>
<body><div class="card"><h1>${ok ? 'Berhasil' : 'Gagal'}</h1>
<p>${ok ? 'Anda sudah masuk. Silakan kembali ke aplikasi Visit.' : 'Login dibatalkan atau gagal. Kembali ke aplikasi dan coba lagi.'}</p>
<p>Tab ini boleh ditutup.</p></div></body></html>''';
}

class GoogleAuthException implements Exception {
  final String message;
  const GoogleAuthException(this.message);
  @override
  String toString() => message;
}
