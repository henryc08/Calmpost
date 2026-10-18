import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/routes.dart';
import '../../data/food_catalog.dart';
import '../../domain/toronto.dart';
import '../../domain/models.dart';
import '../../state/toronto.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'toronto_widgets.dart';

Future<void> showTorontoItemSheet(
  BuildContext context, {
  String? itemId,
  String? catalogId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: C.paper,
  builder: (_) => TorontoItemSheet(itemId: itemId, catalogId: catalogId),
);

class TorontoItemSheet extends ConsumerStatefulWidget {
  const TorontoItemSheet({super.key, this.itemId, this.catalogId});
  final String? itemId, catalogId;
  @override
  ConsumerState<TorontoItemSheet> createState() => _TorontoItemSheetState();
}

class _TorontoItemSheetState extends ConsumerState<TorontoItemSheet> {
  bool _saving = false;
  String? _error;
  Future<void> _apply(TorontoItem item) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(torontoProgressProvider.notifier);
    final saved = await notifier.save((p) => p.apply(item.id));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!identical(notifier, ref.read(torontoProgressProvider.notifier))) {
        return;
      }
      if (!saved) {
        _error = 'Could not save your action on this device. Please retry.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(torontoDataProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        S.gutter,
        S.x5,
        S.gutter,
        S.x6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: data.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: C.forest)),
        error: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toronto guidance could not load.', style: T.heading),
            PillButton(
              label: 'Try again',
              onTap: () => ref.invalidate(torontoDataProvider),
            ),
          ],
        ),
        data: (d) {
          final item = widget.itemId == null
              ? d.forCatalog(widget.catalogId ?? '')
              : d.items.where((i) => i.id == widget.itemId).firstOrNull;
          final learning = ref.watch(torontoProgressProvider);
          final progress = learning.valueOrNull;
          if (item == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check this material with Toronto', style: T.title),
                const SizedBox(height: S.x3),
                Text(
                  'This material is outside our reviewed Toronto subset. We cannot infer a municipal destination from its home-compost category. Search Waste Wizard before disposing of it.',
                  style: T.body,
                ),
                TorontoSourceLink(d.sources['wizard']!),
              ],
            );
          }
          final applied = progress?.applied.contains(item.id) ?? false;
          final food =
              foodById[widget.catalogId] ??
              item.catalogIds
                  .map((id) => foodById[id])
                  .whereType<FoodItem>()
                  .firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TORONTO · OFFICIAL SORTING GUIDANCE', style: T.caps),
              const SizedBox(height: S.x3),
              Text(item.name, style: T.title),
              const SizedBox(height: S.x4),
              Text(
                item.route.label,
                style: T.stat.copyWith(
                  fontSize: 32,
                  color: routeColor(item.route),
                ),
              ),
              const SizedBox(height: S.x2),
              Text(item.action, style: T.body),
              const SizedBox(height: S.x3),
              Text(
                'Apartment, condo or co-op? Ask your property manager where this stream is collected. A sorting rule does not confirm your building has collection.',
                style: T.small,
              ),
              const SectionBreak(),
              const SectionLabel('ONE SMALL ACTION'),
              const SizedBox(height: S.x2),
              Text(
                'After you actually use this route, save a sorting action. Each material counts once toward your local practice total.',
                style: T.body,
              ),
              const SizedBox(height: S.x3),
              PillButton(
                label: _saving
                    ? 'Saving…'
                    : applied
                    ? 'Sorting action saved'
                    : 'I used this disposal route',
                onTap: _saving || applied || progress == null
                    ? null
                    : () => _apply(item),
              ),
              const SizedBox(height: S.x2),
              if (learning.hasError)
                Text(
                  'Local learning is unavailable. Open the sorting challenge to retry or recover your record.',
                  style: T.small.copyWith(color: C.clay),
                ),
              Text(
                'Self-reported practice, saved on this device. No compost weight or game XP is added.',
                style: T.small,
              ),
              if (_error != null)
                Text(_error!, style: T.body.copyWith(color: C.clay)),
              if (food != null) ...[
                const SectionBreak(),
                Text('Using your Calmpost compost bin?', style: T.heading),
                const SizedBox(height: S.x2),
                Text(
                  'It has different rules. Check its current readings before adding anything.',
                  style: T.small,
                ),
                const SizedBox(height: S.x3),
                PillButton(
                  label: 'Check my compost bin',
                  onTap: () {
                    Routes.compostAdvice(context, food);
                  },
                ),
              ],
              const SectionBreak(),
              Text('Guidance checked ${d.reviewedAt}.', style: T.small),
              TorontoSourceLink(d.sources[item.source]!),
              const SizedBox(height: S.x3),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('City data behind this answer', style: T.small),
                children: [
                  Text(
                    'Waste Wizard ${item.id} · ${item.sourceItem}\nPublished category: ${item.sourceCategory}\nDataset refreshed December 2023; reviewed guidance above takes priority.',
                    style: T.small,
                  ),
                  const SizedBox(height: S.x2),
                  SelectableText(
                    d.provenance['catalogue_url'] as String,
                    style: T.small,
                  ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
