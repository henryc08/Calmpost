import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:calmpost/data/social_repository.dart';

void main() {
  test(
    'authentication normalizes handle, scopes bearer token, restores owned bin',
    () async {
      final seen = <http.Request>[];
      final repo = SocialRepository(
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({'token': 'secret-session', 'user_id': 'alice'}),
              200,
            );
          }
          return http.Response(jsonEncode({'bin_id': 'my-bin'}), 200);
        }),
      );
      final session = await repo.authenticate(
        'https://compost.example/',
        ' ALICE ',
        'my-test-password',
      );
      expect(session.binId, 'my-bin');
      expect(jsonDecode(seen.first.body)['handle'], 'alice');
      expect(seen.first.headers.containsKey('Authorization'), isFalse);
      expect(seen.last.headers['Authorization'], 'Bearer secret-session');
      expect(seen.last.url.toString(), 'https://compost.example/social/me');
      repo.close();
    },
  );
  test('private group authorization failures remain errors', () async {
    final repo = SocialRepository(
      client: MockClient(
        (_) async => http.Response('{"detail":"Private group not found"}', 404),
      ),
    );
    const session = SocialSession(
      server: 'https://compost.example',
      token: 'a',
      userId: 'alice',
    );
    await expectLater(
      repo.call(session, 'GET', '/circles/secret'),
      throwsA(isA<SocialFailure>().having((e) => e.status, 'status', 404)),
    );
    repo.close();
  });
  test(
    'public passwords use HTTPS and local development hosts are explicit',
    () {
      expect(
        SocialRepository.normalizeServer('http://192.168.1.10:8000/'),
        'http://192.168.1.10:8000',
      );
      expect(
        () => SocialRepository.normalizeServer('http://compost.example'),
        throwsA(isA<SocialFailure>()),
      );
      expect(
        () => SocialRepository.normalizeServer(
          'https://user:pass@compost.example',
        ),
        throwsA(isA<SocialFailure>()),
      );
      expect(
        () => SocialRepository.normalizeServer('http://10.evil.example'),
        throwsA(isA<SocialFailure>()),
      );
    },
  );
  test('network and malformed responses have actionable errors', () async {
    final repo = SocialRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      repo.authenticate('https://compost.example', 'alice', 'my-password'),
      throwsA(isA<SocialFailure>()),
    );
    repo.close();
  });
  test('sessions survive storage and logout clears them', () async {
    const store = SecureSessionStore();
    const session = SocialSession(
      server: 'https://compost.example',
      token: 'private-token',
      userId: 'alice',
      binId: 'my-bin',
    );
    await store.write(session);
    expect((await store.read())!.toJson(), session.toJson());
    await store.write(null);
    expect(await store.read(), isNull);
  });
}
