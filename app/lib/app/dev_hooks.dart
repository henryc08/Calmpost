import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_repository.dart';
import '../domain/models.dart';
import '../features/celebrations/celebration_screen.dart';
import '../state/celebrations.dart';
import '../state/game.dart';
import '../state/providers.dart';
import '../ui/art/wren.dart';
import '../ui/tokens.dart';
import 'routes.dart';

/// Web-preview deep links for design reviews and screenshots, e.g.
/// `?tab=2`, `?scenario=tooWet`, `?open=log`, `?celebrate=streak`.
/// No effect on Android builds.
class DevHooks {
  static int initialTab() => kIsWeb ? int.tryParse(Uri.base.queryParameters['tab'] ?? '') ?? 0 : 0;

  static void apply(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return;
    final q = Uri.base.queryParameters;
    final scenario = Scenario.values.where((s) => s.name == q['scenario']).firstOrNull;
    if (scenario != null) ref.read(scenarioProvider.notifier).state = scenario;
    if (q['checkin'] == '1') ref.read(gameProvider.notifier).checkIn();

    final quest = ref.read(gameProvider).quests.first;
    final c = switch (q['celebrate']) {
      'streak' => const StreakCelebration(7),
      'quest' => QuestCelebration(quest.copyWith(progress: 1)),
      'level' => const LevelUpCelebration(10, 'Soil Whisperer'),
      'ready' => const ReadyCelebration(),
      'harvest' => HarvestCelebration(GardenPlant(species: PlantSpecies.pumpkin, day: DateTime.now(), rare: true), 100, 50, 4.2),
      'promo' => const PromotionZoneCelebration(6, 'Fern'),
      _ => null,
    };
    if (c != null) {
      Navigator.of(context).push(celebrationRoute(c));
      return;
    }
    final item = ref.read(repositoryProvider).food(q['item'] ?? '');
    switch (q['open']) {
      case 'log':
        Routes.log(context, item: item);
      case 'layer':
        Routes.layer(context, Zone.values.where((z) => z.name == q['zone']).firstOrNull ?? Zone.top);
      case 'health':
        Routes.health(context);
      case 'streak':
        Routes.streak(context);
      case 'shop':
        Routes.shop(context);
      case 'debug':
        Routes.debug(context);
    }
  }
}

/// Renders the launcher icon artwork (web only, `?icon=1`), 432×432 at top-left.
class IconArt extends StatelessWidget {
  const IconArt({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 432,
          height: 432,
          child: ColoredBox(
            color: C.leaf,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [Positioned(left: 216 - 210, top: 216 - 0.36 * 420 + 18, width: 420, height: 420, child: _StillWren())],
            ),
          ),
        ),
      ),
    );
  }
}

class _StillWren extends StatelessWidget {
  const _StillWren();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: WrenPainter(mood: WrenMood.happy, t: 0, hat: WrenHat.sprout, tail: 60),
  );
}
