import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../domain/toronto.dart';
import '../../state/toronto.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'toronto_widgets.dart';

class TorontoLearningScreen extends ConsumerStatefulWidget {
  const TorontoLearningScreen({super.key});
  @override
  ConsumerState<TorontoLearningScreen> createState() =>
      _TorontoLearningScreenState();
}

class _TorontoLearningScreenState extends ConsumerState<TorontoLearningScreen> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  TorontoRoute? _selected;
  bool _saving = false;
  String? _error;
  TorontoProgressNotifier? _owner;

  Future<void> _save(TorontoProgress Function(TorontoProgress) update) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(torontoProgressProvider.notifier);
    final saved = await notifier.save(update);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!identical(notifier, ref.read(torontoProgressProvider.notifier))) {
        _selected = null;
        return;
      }
      if (saved) {
        _selected = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      } else {
        _error =
            'Your answer was not saved. Please retry. Your previous progress is safe.';
      }
    });
  }

  Future<void> _recover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset local learning?'),
        content: const Text(
          'This removes this account’s Toronto learning record on this device. Your bin, compost logs, XP and collection stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reset local learning'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final saved = await ref.read(torontoProgressProvider.notifier).reset();
    if (mounted && !saved) {
      setState(() => _error = 'Could not reset local learning. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(torontoProgressProvider.notifier);
    if (!identical(_owner, notifier)) {
      _owner = notifier;
      _selected = null;
    }
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Small scraps.\nNew habits.',
        controller: _scroll,
        subtitle: 'The Toronto sorting challenge',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: [
          ...ref
              .watch(torontoDataProvider)
              .when(
                loading: () => [
                  const CircularProgressIndicator(color: C.forest),
                ],
                error: (_, _) => [
                  Text('The City-data guide could not load.', style: T.body),
                  PillButton(
                    label: 'Try again',
                    onTap: () => ref.invalidate(torontoDataProvider),
                  ),
                ],
                data: (data) => ref
                    .watch(torontoProgressProvider)
                    .when(
                      loading: () => [
                        Text('Restoring local learning…', style: T.body),
                      ],
                      error: (_, _) => [
                        Text(
                          ref.watch(socialSessionProvider).hasError
                              ? 'Your account could not be restored.'
                              : 'Your local learning record could not be read.',
                          style: T.heading,
                        ),
                        Text(
                          ref.watch(socialSessionProvider).hasError
                              ? 'Retry account restoration to save learning under the right identity. The Toronto sorting guide is still available.'
                              : 'You can retry or explicitly reset it. Your compost logs and game rewards are separate.',
                          style: T.body,
                        ),
                        PillButton(
                          label: 'Try again',
                          onTap: () {
                            if (ref.read(socialSessionProvider).hasError) {
                              ref.invalidate(socialSessionProvider);
                            } else {
                              ref
                                  .read(torontoProgressProvider.notifier)
                                  .reload();
                            }
                          },
                        ),
                        if (!ref.watch(socialSessionProvider).hasError)
                          TextButton(
                            onPressed: _recover,
                            child: const Text('Reset local learning'),
                          ),
                      ],
                      data: (p) => _content(data, p),
                    ),
              ),
          if (_error != null) ...[
            const SizedBox(height: S.x3),
            Text(_error!, style: T.body.copyWith(color: C.clay)),
          ],
        ],
      ),
    );
  }

  List<Widget> _content(TorontoData data, TorontoProgress p) {
    if (p.complete) return _result(data, p);
    if (p.baselineDone && !p.lessonsDone) {
      final lesson = torontoLessons.firstWhere(
        (l) => !p.learned.contains(l.id),
      );
      return [
        SectionLabel('LEARN · ${p.learned.length + 1} OF 3'),
        const SizedBox(height: S.x3),
        ThinBar(
          value: p.learned.length / 3,
          color: C.leaf,
          track: C.sunk,
          height: 5,
        ),
        const SizedBox(height: S.x5),
        Icon(
          switch (lesson.id) {
            'food' => PhosphorIconsRegular.bowlFood,
            'packaging' => PhosphorIconsRegular.forkKnife,
            _ => PhosphorIconsRegular.newspaper,
          },
          color: C.forest,
          size: 46,
        ),
        const SizedBox(height: S.x4),
        Text(lesson.title, style: T.title),
        const SizedBox(height: S.x3),
        Text(lesson.body, style: T.body),
        const SectionBreak(),
        for (final id in lesson.itemIds) ...[
          Text(
            '${data.byId(id).name} → ${data.byId(id).route.label}',
            style: T.heading,
          ),
          const SizedBox(height: S.x2),
          Text(data.byId(id).action, style: T.small),
          const SizedBox(height: S.x4),
        ],
        TorontoSourceLink(
          data.sources[data.byId(lesson.itemIds.first).source]!,
        ),
        const SizedBox(height: S.x5),
        PillButton(
          label: _saving ? 'Saving…' : 'I’ve explored this lesson',
          onTap: _saving ? null : () => _save((p) => p.learn(lesson.id)),
        ),
      ];
    }
    final followUp = p.baselineDone;
    final answers = followUp ? p.after : p.before;
    final questions = followUp ? torontoAfter : torontoBefore;
    final question = questions[answers.length];
    return [
      SectionLabel(
        '${followUp ? 'TRY NEW ITEMS' : 'BEFORE YOU LEARN'} · ${answers.length + 1} OF 3',
      ),
      const SizedBox(height: S.x3),
      Text(
        followUp ? 'Use what you learned.' : 'What would you do today?',
        style: T.title,
      ),
      const SizedBox(height: S.x2),
      Text(
        followUp
            ? 'These are different items. Your first answers stay saved so you can compare.'
            : 'Three quick questions, then three short lessons. It is fine to be unsure. Answers are revealed after the challenge.',
        style: T.body,
      ),
      const SizedBox(height: S.x5),
      Text(question.prompt, style: T.heading.copyWith(fontSize: 23)),
      const SizedBox(height: S.x2),
      Text('Which Toronto disposal stream?', style: T.small),
      const SizedBox(height: S.x4),
      for (final route in [
        TorontoRoute.green,
        TorontoRoute.recycling,
        TorontoRoute.garbage,
      ]) ...[
        Semantics(
          selected: _selected == route,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(S.x4),
              backgroundColor: _selected == route ? C.leafSoft : null,
              side: BorderSide(color: _selected == route ? C.leaf : C.line),
            ),
            onPressed: _saving ? null : () => setState(() => _selected = route),
            child: Row(
              children: [
                Expanded(child: Text(route.label, style: T.heading)),
                if (_selected == route)
                  const Icon(
                    PhosphorIconsRegular.check,
                    color: C.leaf,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x2),
      ],
      const SizedBox(height: S.x4),
      PillButton(
        label: _saving ? 'Saving…' : 'Save answer & continue',
        onTap: _selected == null || _saving
            ? null
            : () {
                final answer = _selected!;
                _save(
                  (p) => p.answer(question.itemId, answer, followUp: followUp),
                );
              },
      ),
      const SizedBox(height: S.x3),
      Text(
        'Learning progress stays on this device, separate from game XP and compost weight.',
        style: T.small,
      ),
    ];
  }

  List<Widget> _result(TorontoData data, TorontoProgress p) {
    final before = data.score(p.before, torontoBefore);
    final after = data.score(p.after, torontoAfter);
    return [
      const SectionLabel('LEARNING BADGE EARNED'),
      const SizedBox(height: S.x4),
      Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: C.leafSoft,
            border: Border.all(color: C.leaf, width: 2),
          ),
          child: const Icon(
            PhosphorIconsRegular.plant,
            color: C.forest,
            size: 58,
          ),
        ),
      ),
      const SizedBox(height: S.x4),
      Center(child: Text('Toronto sorter', style: T.title)),
      const SizedBox(height: S.x2),
      Text(
        'Three lessons explored. One more reason to pause before the garbage bin.',
        style: T.body,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: S.x3),
      Text(
        'A local learning badge. No game XP, Loam or plant is awarded.',
        style: T.small,
        textAlign: TextAlign.center,
      ),
      const SectionBreak(),
      const SectionLabel('YOUR FIRST-ATTEMPT RESULTS'),
      const SizedBox(height: S.x4),
      Wrap(
        spacing: S.x8,
        runSpacing: S.x4,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$before / 3', style: T.stat),
              Text('Before learning', style: T.small),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$after / 3', style: T.stat.copyWith(color: C.leaf)),
              Text('Different items after', style: T.small),
            ],
          ),
        ],
      ),
      const SizedBox(height: S.x3),
      Text(
        'A short practice comparison, not proof of lasting behaviour change or less waste. We keep your first answers even when you revisit.',
        style: T.small,
      ),
      const SectionBreak(),
      const SectionLabel('TAKE THE ANSWERS WITH YOU'),
      const SizedBox(height: S.x3),
      for (final q in [...torontoBefore, ...torontoAfter]) ...[
        Text(q.prompt, style: T.heading),
        const SizedBox(height: S.x1),
        Text(
          'You chose ${(p.before[q.itemId] ?? p.after[q.itemId])!.label}. Toronto route: ${data.byId(q.itemId).route.label}.',
          style: T.small,
        ),
        const SizedBox(height: S.x1),
        Text(data.byId(q.itemId).action, style: T.body),
        const SizedBox(height: S.x4),
      ],
      Text(
        'Your next step: check a real item in the Toronto guide, use the route, then save a sorting action.',
        style: T.body,
      ),
      const SizedBox(height: S.x3),
      PillButton(
        label: 'Back to Toronto Challenge',
        onTap: () => Navigator.pop(context),
      ),
      const SizedBox(height: S.x3),
      TorontoSourceLink(data.sources['green']!),
      TorontoSourceLink(data.sources['recycling']!),
    ];
  }
}
