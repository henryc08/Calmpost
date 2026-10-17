import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class SocialFailure implements Exception {
  const SocialFailure(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SocialSession {
  const SocialSession({
    required this.server,
    required this.token,
    required this.userId,
    this.binId,
  });
  final String server, token, userId;
  final String? binId;
  Json toJson() => {
    'server': server,
    'token': token,
    'user_id': userId,
    'bin_id': binId,
  };
  factory SocialSession.fromJson(Json j) => SocialSession(
    server: j['server'],
    token: j['token'],
    userId: j['user_id'],
    binId: j['bin_id'],
  );
}

abstract class SessionStore {
  Future<SocialSession?> read();
  Future<void> write(SocialSession? value);
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'calmpost.social.session';
  @override
  Future<SocialSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return SocialSession.fromJson(jsonDecode(raw) as Json);
    } on FormatException {
      await write(null);
      return null;
    }
  }

  @override
  Future<void> write(SocialSession? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(value.toJson()));
}

class SocialRepository {
  SocialRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  static String normalizeServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const SocialFailure('Enter a valid server address');
    }
    // Passwords and sessions may use HTTP only on a local development network.
    final h = uri.host;
    final parts = h.split('.').map(int.tryParse).toList();
    final ipv4 =
        parts.length == 4 &&
        parts.every((p) => p != null && p >= 0 && p <= 255);
    final local =
        h == 'localhost' ||
        h == '::1' ||
        (ipv4 &&
            (parts[0] == 127 ||
                parts[0] == 10 ||
                (parts[0] == 192 && parts[1] == 168) ||
                (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31)));
    if (uri.scheme == 'http' && !local) {
      throw const SocialFailure('Use HTTPS for a public server');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<dynamic> request(
    String server,
    String method,
    String path, {
    String? token,
    Json? body,
  }) async {
    final req = http.Request(method, Uri.parse('$server/social$path'));
    req.followRedirects = false;
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 15)),
      ).timeout(const Duration(seconds: 15));
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw const SocialFailure('The server returned an unreadable response');
      }
      if (response.statusCode >= 300) {
        final detail = data is Map ? data['detail'] : null;
        throw SocialFailure(
          detail is String ? detail : 'Check the fields and try again',
          response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const SocialFailure('The server took too long. Please try again');
    } on http.ClientException {
      throw const SocialFailure(
        'Could not reach the server. Check your connection',
      );
    }
  }

  Future<SocialSession> authenticate(
    String server,
    String handle,
    String password, {
    String? name,
  }) async {
    server = normalizeServer(server);
    final result =
        await request(
              server,
              'POST',
              name == null ? '/login' : '/register',
              body: {
                'handle': handle.trim().toLowerCase(),
                'password': password,
                if (name != null) 'display_name': name.trim(),
              },
            )
            as Json;
    final session = SocialSession(
      server: server,
      token: result['token'],
      userId: result['user_id'],
    );
    final me = await call(session, 'GET', '/me') as Json;
    return SocialSession(
      server: server,
      token: session.token,
      userId: session.userId,
      binId: me['bin_id'],
    );
  }

  Future<dynamic> call(
    SocialSession session,
    String method,
    String path, [
    Json? body,
  ]) => request(session.server, method, path, token: session.token, body: body);
}
