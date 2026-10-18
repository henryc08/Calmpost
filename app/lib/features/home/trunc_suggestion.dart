import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../domain/trunc_guidance.dart';
import '../../state/providers.dart';
import '../../state/trunc_brief.dart';
import '../../ui/brand.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

/// An open text section, not another chat window or a second recommendation.
class TruncSuggestion extends ConsumerWidget {
  const TruncSuggestion({super.key, required this.snapshot});
  final BinSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = guidanceFor(snapshot);
    final active = ref.watch(tabProvider) == AppTab.home && ModalRoute.of(context)?.isCurrent != false;
    final result = active ? ref.watch(truncBriefProvider) : const AsyncData<TruncReply?>(null);
    // Never carry an old response across sensor/need changes or a failed refresh.
    final answer = result.isLoading || result.hasError ? null : result.valueOrNull;
    final at = answer?.context.readingsAt;
    final usable =
        answer != null &&
        answer.onTopic &&
        answer.usedReadings &&
        answer.need == local.need &&
        !answer.context.readingsStale &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 2) &&
        local.usable &&
        local.status != 'inspect';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('TRUNC'),
        const SizedBox(height: S.x3),
        Text('For your bin, right now', style: T.title.copyWith(fontSize: 28)),
        const SizedBox(height: S.x3),
        Semantics(liveRegion: true, child: Text(usable ? answer.reply : local.summary, style: T.body)),
        if (usable && !answer.model.startsWith('rules') && answer.model != 'mock') ...[
          const SizedBox(height: S.x2),
          Text(local.limits.join(' '), style: T.small),
        ],
        const SizedBox(height: S.x3),
        Text(
          result.isLoading
              ? 'Checking your bin’s context…'
              : result.hasError
              ? 'Connection unavailable · showing guidance from the available readings.'
              : usable && !answer.model.startsWith('rules') && answer.model != 'mock'
              ? 'Gemini explanation · action checked against bin rules'
              : 'Based on the bin’s care rules',
          style: T.small,
        ),
        Text(
          snapshot.readingsStale
              ? 'Readings are stale · ${snapshot.ageLabel(DateTime.now())}'
              : 'Readings as of ${(usable ? at : snapshot.time).toLocal().hour.toString().padLeft(2, '0')}:${(usable ? at : snapshot.time).toLocal().minute.toString().padLeft(2, '0')}',
          style: T.small,
        ),
        if (result.hasError)
          TextButton(
            onPressed: () => ref.invalidate(truncBriefProvider),
            child: Text('Retry suggestion', style: T.button),
          ),
        const SizedBox(height: S.x3),
        Align(
          alignment: Alignment.bottomLeft,
          child: TextButton(
            onPressed: () => Routes.trunc(context),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            child: Text('Ask Trunc a specific question', style: T.button.copyWith(color: C.forest)),
          ),
        ),
      ],
    );
  }
}
