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
      // Exercise the real Dart repository, HTTP API and database together.
      for (final kind in ['request', 'offer']) {
        final post =
            await api.call(alice, 'POST', '/circles/$cid/exchange', {
                  'kind': kind,
                  'material_id': 'dry_leaves',
                  'quantity': 'One small bag',
                  'request_id': 'live-$stamp-$kind',
                })
                as Json;
        final path = '/circles/$cid/exchange/${post['id']}';
        final reservation =
            await api.call(bob, 'POST', '$path/claim', {
                  'version': post['version'],
                  'request_id': 'claim-$stamp-$kind',
                  'note': 'Garden gate at noon',
                })
                as Json;
        final receipt = {'reservation_id': reservation['reservation_id']};
        final waiting = await api.call(alice, 'POST', '$path/confirm', receipt);
        expect(waiting['status'], 'reserved');
        final completed = await api.call(bob, 'POST', '$path/confirm', receipt);
        expect(completed['status'], 'completed');
        expect(completed['creator_xp'], kind == 'request' ? 10 : 0);
        expect(completed['responder_xp'], kind == 'request' ? 10 : 0);
        final retried = await api.call(bob, 'POST', '$path/confirm', receipt);
        expect(retried['responder_xp'], completed['responder_xp']);
      }
      final aliceProgress = await api.call(alice, 'GET', '/me') as Json;
      final bobProgress = await api.call(bob, 'GET', '/me') as Json;
      expect(aliceProgress['progress']['total_xp'], 10);
      expect(bobProgress['progress']['total_xp'], 15);
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
