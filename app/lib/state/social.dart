import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/social_repository.dart';

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const SecureSessionStore(),
);
final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final repo = SocialRepository();
  ref.onDispose(repo.close);
  return repo;
});

final socialSessionProvider =
    AsyncNotifierProvider<SocialAccount, SocialSession?>(SocialAccount.new);

class SocialAccount extends AsyncNotifier<SocialSession?> {
  int _binRevision = 0;
  @override
  Future<SocialSession?> build() => ref.read(sessionStoreProvider).read();

  Future<void> signIn(
    String server,
    String handle,
    String password, {
    String? name,
  }) async {
    final session = await ref
        .read(socialRepositoryProvider)
        .authenticate(server, handle, password, name: name);
    await ref.read(sessionStoreProvider).write(session);
    state = AsyncData(session);
    refreshSocial(ref);
  }

  Future<void> signOut() async {
    final session = state.valueOrNull;
    if (session != null) {
      try {
        await ref
            .read(socialRepositoryProvider)
            .call(session, 'POST', '/logout');
      } on SocialFailure catch (e) {
        if (e.status != 401) rethrow;
      }
    }
    await ref.read(sessionStoreProvider).write(null);
    state = const AsyncData(null);
    refreshSocial(ref);
  }

  Future<void> pair(String token) async {
    final old = state.requireValue!;
    final revision = ++_binRevision;
    final result =
        await ref.read(socialRepositoryProvider).call(old, 'POST', '/bin', {
              'device_token': token,
            })
            as Json;
    final session = SocialSession(
      server: old.server,
      token: old.token,
      userId: old.userId,
      binId: result['bin_id'],
    );
    if (!identical(state.valueOrNull, old) || revision != _binRevision) return;
    state = AsyncData(session);
    await ref.read(sessionStoreProvider).write(session);
    refreshSocial(ref);
  }

  /// Reconcile a cached pairing without dropping it on network failure or a
  /// social refresh. Ignore responses that started before another account/pair.
  Future<void> refreshBin() async {
    final old = state.valueOrNull;
    if (old == null) return;
    final revision = _binRevision;
    final me =
        await ref.read(socialRepositoryProvider).call(old, 'GET', '/me')
            as Json;
    if (!identical(state.valueOrNull, old) ||
        revision != _binRevision ||
        !me.containsKey('bin_id')) {
      return;
    }
    await syncBin(old, me['bin_id'] as String?);
  }

  Future<void> syncBin(SocialSession expected, String? binId) async {
    if (!identical(state.valueOrNull, expected) || expected.binId == binId) {
      return;
    }
    _binRevision++;
    final next = SocialSession(
      server: expected.server,
      token: expected.token,
      userId: expected.userId,
      binId: binId,
    );
    state = AsyncData(next);
    await ref.read(sessionStoreProvider).write(next);
  }
}

void refreshSocial(Ref ref) {
  ref.invalidate(socialDataProvider);
}

// A single read boundary keeps loading, retry and periodic refresh consistent
// across profiles, feeds and groups. Writes only invalidate after success.
final socialDataProvider = FutureProvider.autoDispose.family<dynamic, String>((
  ref,
  path,
) async {
  final session = ref.watch(socialSessionProvider).valueOrNull;
  if (session == null) return null;
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final account = ref.read(socialSessionProvider.notifier);
  final result = await ref
      .watch(socialRepositoryProvider)
      .call(session, 'GET', path);
  if (path == '/me' && result is Json && result.containsKey('bin_id')) {
    await account.syncBin(session, result['bin_id'] as String?);
  }
  return result;
});

Future<dynamic> socialWrite(
  WidgetRef ref,
  String method,
  String path, [
  Json? body,
]) async {
  final session = ref.read(socialSessionProvider).valueOrNull;
  if (session == null) throw const SocialFailure('Sign in to continue');
  final result = await ref
      .read(socialRepositoryProvider)
      .call(session, method, path, body);
  ref.invalidate(socialDataProvider);
  return result;
}
