import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/toronto_repository.dart';
import '../domain/toronto.dart';
import 'game.dart';
import 'social.dart';

final torontoRepositoryProvider = Provider((ref) => TorontoRepository());
final torontoDataProvider = FutureProvider<TorontoData>(
  (ref) => ref.watch(torontoRepositoryProvider).load(),
);
final torontoProgressProvider =
    StateNotifierProvider<TorontoProgressNotifier, AsyncValue<TorontoProgress>>(
      (ref) {
        final session = ref.watch(socialSessionProvider);
        final account = session.valueOrNull;
        final scope = account == null
            ? 'guest'
            : '${account.server}|${account.userId}';
        return TorontoProgressNotifier(
          TorontoProgressStore(ref.watch(gameStorageProvider), scope),
          ready: !session.isLoading,
          accountUnavailable: session.hasError,
        );
      },
    );

class TorontoProgressNotifier
    extends StateNotifier<AsyncValue<TorontoProgress>> {
  TorontoProgressNotifier(
    this.store, {
    bool ready = true,
    this.accountUnavailable = false,
  }) : super(const AsyncLoading()) {
    if (ready) reload();
  }
  final TorontoProgressStore store;
  final bool accountUnavailable;
  bool saving = false;
  void reload() {
    try {
      if (accountUnavailable) throw StateError('Account could not be restored');
      state = AsyncData(store.read());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<bool> save(TorontoProgress Function(TorontoProgress) update) async {
    final current = state.valueOrNull;
    if (saving || current == null) return false;
    saving = true;
    try {
      final next = update(current);
      await store.write(next);
      if (!mounted) return false;
      state = AsyncData(next);
      return true;
    } catch (_) {
      return false;
    } finally {
      saving = false;
    }
  }

  Future<bool> reset() async {
    if (saving || accountUnavailable) return false;
    saving = true;
    try {
      await store.reset();
      if (mounted) state = AsyncData(TorontoProgress());
      return true;
    } catch (_) {
      return false;
    } finally {
      saving = false;
    }
  }
}
