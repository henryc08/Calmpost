import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';

/// Full-screen reward moments, shown one at a time by the app shell.
sealed class Celebration {
  const Celebration();
}

class StreakCelebration extends Celebration {
  const StreakCelebration(this.days, {this.lockUsed = false});
  final int days;
  final bool lockUsed;
}

class QuestCelebration extends Celebration {
  const QuestCelebration(this.quest, {this.allDone = false});
  final Quest quest;
  final bool allDone;
}

class LevelUpCelebration extends Celebration {
  const LevelUpCelebration(this.level, this.title);
  final int level;
  final String title;
}

class ReadyCelebration extends Celebration {
  const ReadyCelebration();
}

class HarvestCelebration extends Celebration {
  const HarvestCelebration(this.plant, this.xp, this.acorns, this.kg);
  final GardenPlant plant;
  final int xp;
  final int acorns;
  final double kg;
}

class PromotionZoneCelebration extends Celebration {
  const PromotionZoneCelebration(this.rank, this.tierName);
  final int rank;
  final String tierName;
}

class CelebrationQueue extends Notifier<List<Celebration>> {
  @override
  List<Celebration> build() => const [];

  void push(Celebration c) => state = [...state, c];

  void pop() {
    if (state.isNotEmpty) state = state.sublist(1);
  }
}

final celebrationProvider = NotifierProvider<CelebrationQueue, List<Celebration>>(CelebrationQueue.new);

/// Small top-of-screen toasts ("+5 XP · Checked in").
class Toast {
  const Toast(this.message, {this.xp = 0, this.id = 0});
  final String message;
  final int xp;
  final int id;
}

class ToastNotifier extends Notifier<Toast?> {
  int _id = 0;

  @override
  Toast? build() => null;

  void show(String message, {int xp = 0}) => state = Toast(message, xp: xp, id: ++_id);

  void clear(int id) {
    if (state?.id == id) state = null;
  }
}

final toastProvider = NotifierProvider<ToastNotifier, Toast?>(ToastNotifier.new);
