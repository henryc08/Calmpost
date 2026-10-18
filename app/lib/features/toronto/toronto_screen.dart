import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/routes.dart';
import '../../domain/toronto.dart';
import '../../state/toronto.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'toronto_widgets.dart';

class TorontoScreen extends ConsumerWidget {
  const TorontoScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: C.paper,
    body: ref
        .watch(torontoDataProvider)
        .when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: C.forest)),
          error: (_, _) => BrandPage(
            title: 'Toronto',
            trailing: _back(context),
            children: [
              Text(
                'The Toronto guide could not load. Your bin and saved learning progress are unchanged.',
                style: T.body,
              ),
              PillButton(
                label: 'Try again',
                onTap: () => ref.invalidate(torontoDataProvider),
              ),
            ],
          ),
          data: (data) => _page(context, ref, data),
        ),
  );

  Widget _page(BuildContext context, WidgetRef ref, TorontoData data) {
    final stats = data.stats;
    final learning = ref.watch(torontoProgressProvider);
    final progress = learning.valueOrNull;
    final apartments = stats['multi_residential_diversion_pct'] as num;
    final houses = stats['single_family_diversion_pct'] as num;
    return BrandPage(
      title: 'Toronto Challenge',
      subtitle: 'Know where it goes. Grow the habit.',
      trailing: _back(context),
      hero: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT ${stats['green_bin_share_of_garbage_pct']}%',
            style: T.display.copyWith(color: C.onBrand, fontSize: 48),
          ),
          Text(
            'of Toronto’s garbage could go in the Green Bin.',
            style: T.heading.copyWith(color: C.onBrand),
          ),
          const SizedBox(height: S.x2),
          Text(
            'City of Toronto · Green Bin guide\nA citywide estimate, not your household’s waste.',
            style: T.small.copyWith(color: C.onBrandMuted),
          ),
        ],
      ),
      children: [
        const SectionLabel('A CITY PROBLEM. AN EVERYDAY ACTION.'),
        const SizedBox(height: S.x3),
        Text('Food scraps have somewhere better to go.', style: T.title),
        const SizedBox(height: S.x2),
        Text(
          'Learn Toronto’s sorting rules, check a scrap, then put that knowledge into practice. Use this guide with your building’s organics service or alongside your Calmpost compost bin.',
          style: T.body,
        ),
        const SizedBox(height: S.x4),
        PillButton(
          label: 'Check a Toronto item',
          icon: PhosphorIconsRegular.magnifyingGlass,
          onTap: () => Routes.torontoSort(context),
        ),
        const SizedBox(height: S.x3),
        PillButton(
          label: progress?.complete == true
              ? 'View my learning badge'
              : 'Try the sorting challenge',
          icon: PhosphorIconsRegular.plant,
          color: C.brandDeep,
          onTap: () => Routes.torontoLearning(context),
        ),
        const SizedBox(height: S.x2),
        Text(
          'No hardware needed · works offline · local learning progress',
          style: T.small,
        ),
        const SectionBreak(),
        SectionLabel('THE DIVERSION GAP · ${stats['year']}'),
        const SizedBox(height: S.x4),
        _Rate(
          label: 'Apartments, condos & co-ops',
          value: apartments,
          color: C.clay,
        ),
        const SizedBox(height: S.x4),
        _Rate(label: 'Single-family homes', value: houses, color: C.leaf),
        const SizedBox(height: S.x3),
        Text(
          'Waste diversion means material kept out of landfill through recycling, organics and other programs. These are overall rates, not composting rates.',
          style: T.body,
        ),
        const SizedBox(height: S.x2),
        Text(
          '${stats['scope']} Knowledge, convenience and access can all matter.',
          style: T.small,
        ),
        TorontoSourceLink(data.sources['reports']!),
        const SectionBreak(),
        const SectionLabel('YOUR SMALL STEPS'),
        const SizedBox(height: S.x3),
        if (progress == null)
          Text(
            learning.hasError
                ? 'Local learning could not be restored. Open the sorting challenge to recover it.'
                : 'Restoring local learning…',
            style: T.small,
          ),
        if (progress != null) ...[
          Text(
            '${progress.learned.length} / 3 lessons explored',
            style: T.heading,
          ),
          const SizedBox(height: S.x2),
          ThinBar(
            value: progress.learned.length / 3,
            color: C.leaf,
            track: C.sunk,
            height: 5,
          ),
          const SizedBox(height: S.x3),
          Text(
            '${progress.applied.length} different materials put into practice',
            style: T.heading,
          ),
          const SizedBox(height: S.x2),
        ],
        Text(
          'Actions are self-reported and saved on this device for this account, or for the signed-out guest. They do not measure waste weight or Toronto’s diversion rate.',
          style: T.small,
        ),
        const SectionBreak(),
        const SectionLabel('MAKE THE INFORMATION ACTIONABLE'),
        const SizedBox(height: S.x3),
        Text('Can’t find your building’s organics bin?', style: T.heading),
        const SizedBox(height: S.x2),
        Text(
          'Ask your property manager or superintendent where organics are collected and which sorting instructions apply. If there is no service, ask what options are available.',
          style: T.body,
        ),
        const SizedBox(height: S.x3),
        PillButton(
          label: 'Copy a building request',
          icon: PhosphorIconsRegular.copy,
          onTap: () => copyTorontoText(
            context,
            'Hello, could you let residents know where our building collects food scraps and share the current sorting instructions? If organics collection is not available, could you explain the options for introducing it? Thank you.\n\nToronto collection information: ${data.sources['apartments']!.url}',
            'Building request',
          ),
        ),
        const SectionBreak(),
        const SectionLabel('TORONTO’S 2026 MUNICIPAL ELECTION'),
        const SizedBox(height: S.x3),
        Text('Bring a useful question to the conversation.', style: T.title),
        const SizedBox(height: S.x2),
        Text(
          'Toronto’s waste strategy identifies barriers in multi-residential buildings. Residents can ask how future City decisions will make organics sorting easier to use.',
          style: T.body,
        ),
        const SizedBox(height: S.x3),
        SelectableText(
          '“What will make organics sorting easier for apartment residents, and how should Toronto measure improvement?”',
          style: T.heading,
        ),
        const SizedBox(height: S.x3),
        PillButton(
          label: 'Copy question & city sources',
          icon: PhosphorIconsRegular.copy,
          onTap: () => copyTorontoText(
            context,
            'What will make organics sorting easier for apartment residents, and how should Toronto measure improvement?\n\nToronto’s ${stats['year']} overall waste diversion rates: apartments, condos and co-ops $apartments%; single-family homes $houses%. These are not composting rates.\n${data.sources['reports']!.url}\n\nCity Waste Strategy: ${data.sources['strategy']!.url}',
            'Civic question',
          ),
        ),
        TorontoSourceLink(data.sources['election']!),
        const SectionBreak(),
        const SectionLabel('WHERE THE ANSWERS COME FROM'),
        const SizedBox(height: S.x3),
        Text(
          '${data.items.length} reviewed items from ${data.provenance['source_records']} Waste Wizard records.',
          style: T.heading,
        ),
        const SizedBox(height: S.x2),
        Text(
          'The downloadable City dataset was last refreshed in December 2023. Our selected guidance was checked against current City pages and the residential recycling provider on ${data.reviewedAt}. This is a bundled snapshot, not a live City feed.',
          style: T.small,
        ),
        const SizedBox(height: S.x2),
        Text(
          'Toronto’s Green Bin rules and your small compost bin’s rules differ. Unknown items stay unknown; check Waste Wizard rather than guessing.',
          style: T.small,
        ),
        for (final key in [
          'green',
          'wizard',
          'recycling',
          'yard',
          'strategy',
          'apartments',
        ]) ...[
          const SizedBox(height: S.x3),
          TorontoSourceLink(data.sources[key]!),
        ],
        const SizedBox(height: S.x3),
        SelectableText(
          data.provenance['catalogue_url'] as String,
          style: T.small,
        ),
        const SizedBox(height: S.x2),
        Text(
          'Data: City of Toronto, Waste Wizard. Catalogue licence field: ${data.provenance['license']}. Guidance summaries and learning design: Calmpost.',
          style: T.small,
        ),
      ],
    );
  }
}

Widget _back(BuildContext context) => IconButton(
  tooltip: 'Back',
  onPressed: () => Navigator.pop(context),
  icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
);

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.value, required this.color});
  final String label;
  final num value;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value percent diverted in 2025',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value%', style: T.stat.copyWith(fontSize: 38, color: color)),
        Text(label, style: T.body),
        const SizedBox(height: S.x2),
        ThinBar(value: value / 100, color: color, track: C.sunk, height: 7),
      ],
    ),
  );
}

class TorontoSortScreen extends ConsumerStatefulWidget {
  const TorontoSortScreen({super.key});
  @override
  ConsumerState<TorontoSortScreen> createState() => _TorontoSortScreenState();
}

class _TorontoSortScreenState extends ConsumerState<TorontoSortScreen> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.paper,
    body: BrandPage(
      title: 'Where does it go?',
      subtitle: 'Toronto’s routes, explained simply',
      trailing: _back(context),
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search Toronto items',
            hintText: 'Cheese, bones, compostable cup…',
            prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
          ),
        ),
        const SizedBox(height: S.x3),
        Text(
          'Check the material, condition and packaging. These are Toronto disposal instructions; your compost bin’s care advice stays separate.',
          style: T.small,
        ),
        const SizedBox(height: S.x4),
        ...ref
            .watch(torontoDataProvider)
            .when(
              loading: () => [const CircularProgressIndicator(color: C.forest)],
              error: (_, _) => [
                Text('The Toronto guide could not load.', style: T.body),
                PillButton(
                  label: 'Try again',
                  onTap: () => ref.invalidate(torontoDataProvider),
                ),
              ],
              data: (d) {
                final results = d.search(_search.text);
                return [
                  if (results.isEmpty) ...[
                    Text('Outside our reviewed subset', style: T.heading),
                    const SizedBox(height: S.x2),
                    Text(
                      'No confirmed match. Try a simpler name or check the City’s Waste Wizard. We do not guess from a similar word.',
                      style: T.body,
                    ),
                    TorontoSourceLink(d.sources['wizard']!),
                  ],
                  for (final item in results) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name, style: T.heading),
                      subtitle: Text(
                        item.route.label,
                        style: T.small.copyWith(color: routeColor(item.route)),
                      ),
                      trailing: const Icon(
                        PhosphorIconsRegular.caretRight,
                        size: 18,
                      ),
                      onTap: () => Routes.torontoItem(context, itemId: item.id),
                    ),
                    const Hairline(),
                  ],
                ];
              },
            ),
      ],
    ),
  );
}
