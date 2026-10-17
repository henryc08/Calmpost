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
    await ref.read(sessionStoreProvider).write(session);
    state = AsyncData(session);
    refreshSocial(ref);
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
  return ref.watch(socialRepositoryProvider).call(session, 'GET', path);
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
