import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../domain/inventory.dart';
import '../../app/routes.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _period = 'all';
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(inventoryProvider(_period));
    final inventory = data.asData?.value;
    final live = ref.watch(dataSourceProvider) == DataSource.live;
    final needsBin = live && ref.watch(socialSessionProvider).valueOrNull?.binId == null && ref.watch(socialSessionProvider).valueOrNull != null;
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Your compost',
        subtitle: live ? 'Confirmed additions' : 'Demo · confirmed additions',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inventory == null ? '—' : compostMass(inventory.grams), style: T.display.copyWith(color: C.onBrand)),
            Text('estimated material added', style: T.body.copyWith(color: C.onBrand)),
            if (inventory != null)
              Text('${inventory.pieces} counted pieces / portions · ${inventory.entries} additions', style: T.small.copyWith(color: C.onBrand)),
          ],
        ),
        children: [
          PaperSegments<String>(
            values: const ['all', 'week'],
            selected: _period,
            label: (p) => p == 'all' ? 'All time' : 'This week',
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: S.x3),
          Text('Confirmed inputs, including material already broken down or harvested. Counts and weights are estimates.', style: T.small),
          if (_period == 'week') Text('Weeks begin Sunday at 00:00 UTC.', style: T.small),
          const SizedBox(height: S.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(label: 'Refresh', dense: true, onTap: () => ref.invalidate(inventoryProvider(_period))),
          ),
          if (needsBin) ...[
            const SectionBreak(),
            Text('Connect a bin to this account to track your compost.', style: T.body),
            const SizedBox(height: S.x3),
            PillButton(label: 'Connect bin', onTap: () => Routes.connectBin(context)),
          ] else ...[
            if (data.isLoading && inventory == null)
              const Padding(
                padding: EdgeInsets.all(S.x4),
                child: LinearProgressIndicator(color: C.brand, backgroundColor: C.sunk),
              ),
            if (data.hasError) ...[const SectionBreak(), Text('Could not load your compost. Try refreshing.', style: T.body.copyWith(color: C.clay))],
            if (inventory != null) ..._content(inventory),
          ],
        ],
      ),
    );
  }

  List<Widget> _content(CompostInventory inventory) {
    final items = inventory.items.where((i) => i.label.toLowerCase().contains(_query.trim().toLowerCase())).toList();
    return [
      const SectionBreak(),
      const SectionLabel('WHAT YOU’VE COMPOSTED'),
      const SizedBox(height: S.x3),
      Wrap(
        spacing: S.x4,
        runSpacing: S.x2,
        children: [
          Text('${compostMass(inventory.gramsFor('green'))} greens', style: T.heading),
          Text('${compostMass(inventory.gramsFor('brown'))} browns', style: T.heading),
        ],
      ),
      if (inventory.uncountedEntries > 0) ...[
        const SizedBox(height: S.x2),
        Text('${inventory.uncountedEntries} older additions have no piece count. Their recorded weight is included.', style: T.small),
      ],
      const SizedBox(height: S.x4),
      if (inventory.items.isEmpty)
        Text(
          'Nothing confirmed yet. Review a camera drop or log an item to start your inventory. Keep-out items and dismissed detections are excluded.',
          style: T.body,
        )
      else ...[
        TextField(
          controller: _search,
          style: T.body,
          decoration: InputDecoration(
            hintText: 'Find an item',
            hintStyle: T.small,
            prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, color: C.muted),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: C.line)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: C.forest)),
          ),
          onChanged: (q) => setState(() => _query = q),
        ),
        const SizedBox(height: S.x2),
        if (items.isEmpty) Text('No items match your search.', style: T.small),
        for (final item in items) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.category == 'green' ? PhosphorIconsRegular.leaf : PhosphorIconsRegular.stack, color: C.ink2, size: 22),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.pieces > 0 ? '${item.pieces} × ${item.label}' : item.label, style: T.heading),
                      Text('${item.entries} additions · ${item.category == 'green' ? 'Green' : 'Brown'}', style: T.small),
                      if (item.visionEntries > 0) Text('${item.visionEntries} from camera / photo, confirmed by you', style: T.small),
                      if (item.uncountedEntries > 0) Text('Plus ${item.uncountedEntries} additions without a count', style: T.small),
                      Text('Last added ${MaterialLocalizations.of(context).formatCompactDate(item.lastAddedAt)}', style: T.small),
                    ],
                  ),
                ),
                const SizedBox(width: S.x2),
                Text('≈ ${compostMass(item.grams)}', style: T.num),
              ],
            ),
          ),
          const Hairline(),
        ],
      ],
      if (inventory.totalXp != null) ...[
        const SectionBreak(),
        const SectionLabel('COMPOST SCORE'),
        const SizedBox(height: S.x3),
        Text('${inventory.totalXp} XP', style: T.stat),
        Text('${inventory.volumeXp} from composting amount + ${inventory.careXp} from care and rewards', style: T.body),
        const SizedBox(height: S.x2),
        Text(
          '1 XP per 20 g of confirmed greens and browns, rounded across each day. Amount and care actions share a 60 XP daily cap. Count alone earns no XP; bin health is measured separately.',
          style: T.small,
        ),
      ],
    ];
  }
}
