// Run only against a disposable test backend; this creates real test accounts.
import 'package:flutter_test/flutter_test.dart';
import 'package:calmpost/data/social_repository.dart';

void main() {
  const server = String.fromEnvironment('MULTIPLAYER_TEST_URL');
  test(
    'two clients invite, share progress, rank and revoke access over HTTP',
    () async {
      final api = SocialRepository();
      addTearDown(api.close);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final alice = await api.authenticate(
        server,
        'a$stamp',
        'multiplayer-test-password',
        name: 'Alice',
      );
      final bob = await api.authenticate(
        server,
        'b$stamp',
        'multiplayer-test-password',
        name: 'Bob',
      );
      final circle =
          await api.call(alice, 'POST', '/circles', {'name': 'HTTP test group'})
              as Json;
      final cid = circle['id'];
      await expectLater(
        api.call(bob, 'GET', '/circles/$cid'),
        throwsA(isA<SocialFailure>().having((e) => e.status, 'status', 404)),
      );
      final invite =
          await api.call(alice, 'POST', '/circles/$cid/invite') as Json;
      await api.call(bob, 'POST', '/join', {'code': invite['code']});
      await api.call(bob, 'POST', '/check-in');
      final board = await api.call(alice, 'GET', '/circles/$cid') as Json;
      expect(board['members'][0]['user_id'], bob.userId);
      expect(board['members'][0]['xp'], 5);
      expect(
        (await api.call(alice, 'GET', '/people/${bob.userId}'))['can_view'],
        false,
      );
      final friend = await api.call(bob, 'POST', '/invites') as Json;
      await api.call(alice, 'POST', '/join', {'code': friend['code']});
      final profile =
          await api.call(alice, 'GET', '/people/${bob.userId}') as Json;
      expect(profile['progress']['streak'], 1);
      final feed = await api.call(alice, 'GET', '/feed') as List;
      expect(feed.first['user_id'], bob.userId);
      await api.call(alice, 'POST', "/events/${feed.first['id']}/cheer");
      expect((await api.call(bob, 'GET', '/feed'))[0]['cheers'], 1);
      await api.call(alice, 'DELETE', '/circles/$cid/members/${bob.userId}');
      await expectLater(
        api.call(bob, 'GET', '/circles/$cid'),
        throwsA(isA<SocialFailure>()),
      );
      await api.call(alice, 'DELETE', '/circles/$cid');
      await api.call(alice, 'POST', '/logout');
      await api.call(bob, 'POST', '/logout');
    },
    skip: server.isEmpty
        ? 'Set MULTIPLAYER_TEST_URL to a disposable backend'
        : false,
  );
}
