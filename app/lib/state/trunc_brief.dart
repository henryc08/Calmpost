import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import '../domain/trunc_guidance.dart';
import 'game.dart';
import 'providers.dart';

final truncBriefProvider = FutureProvider.autoDispose<TruncReply?>((ref) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(binProvider.select((b) => b.valueOrNull == null ? null : truncSignature(b.valueOrNull!)));
  ref.watch(gameProvider.select((g) => g.logs.length));
  final s = ref.read(binProvider).valueOrNull;
  if (s == null || !guidanceFor(s).usable || moistureNeedsInspection(s)) return null;
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  ref.onCancel(timer.cancel);
  return repo.askTrunc(truncOverviewQuestion, includePhotos: false);
});

bool moistureNeedsInspection(BinSnapshot s) => guidanceFor(s).status == 'inspect';

/// Moods bad enough to point someone at Trunc for help.
const truncAlertMoods = {BinMood.wet, BinMood.dry, BinMood.struggling};

/// True when fresh readings put the bin in really bad shape. Stale or missing
/// readings never raise it: an alarm about old data would be wrong.
bool binNeedsHelp(BinHealth? h) => h != null && !h.snapshot.readingsStale && truncAlertMoods.contains(h.mood);

final binNeedsHelpProvider = Provider<bool>((ref) => binNeedsHelp(ref.watch(healthProvider)));
