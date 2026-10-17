import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'verdict_sheet.dart';

/// Log tab: search or pick an item, then get a verdict from the live readings.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIntent());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _consumeIntent() {
    if (!mounted) return;
    final item = ref.read(logIntentProvider);
    if (item == null || ref.read(tabProvider) != AppTab.log) return;
    ref.read(logIntentProvider.notifier).state = null;
    showVerdictSheet(context, item);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(logIntentProvider, (_, next) {
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIntent());
    });
    ref.listen(tabProvider, (_, next) {
      if (next == AppTab.log) WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIntent());
    });

    final repo = ref.watch(repositoryProvider);
    final suggestion = ref.watch(suggestionProvider);
    final results = repo.searchFoods(_query);
    final tips = suggestion?.add.map((f) => f.id).toSet() ?? const <String>{};

    final groups = [
      ('GREENS', 'Wet, nitrogen-rich scraps', FoodCategory.green, C.leaf),
      ('BROWNS', 'Dry, carbon-rich material', FoodCategory.brown, C.loam),
      ('KEEP OUT', 'Never goes in the bin', FoodCategory.avoid, C.clay),
    ];

    return BrandPage(
      title: 'Log',
      subtitle: 'What\'s going in the bin?',
      trailing: Pressable(
        onTap: () => Routes.drop(context),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: C.onBrand, shape: BoxShape.circle),
          child: const Icon(PhosphorIconsRegular.camera, color: C.brandDeep, size: 22),
        ),
      ),
      hero: _SearchField(controller: _search, onChanged: (q) => setState(() => _query = q)),
      children: [
        if (_query.isEmpty && suggestion != null) ...[
          const SectionLabel('RECOMMENDED NOW', trailing: PinkPill('+15 XP each')),
          const SizedBox(height: S.x2),
          for (final (i, f) in suggestion.add.indexed) ...[
            if (i > 0) const Hairline(),
            _ItemRow(item: f, color: f.category == FoodCategory.brown ? C.loam : C.leaf, tip: true, onTap: () => showVerdictSheet(context, f)),
          ],
          const SectionBreak(),
        ],
        for (final (label, sub, cat, color) in groups)
          if (results.any((f) => f.category == cat)) ...[
            SectionLabel(label, trailing: Text(sub, style: T.small.copyWith(fontSize: 11))),
            const SizedBox(height: S.x2),
            for (final (i, f) in results.where((f) => f.category == cat).indexed) ...[
              if (i > 0) const Hairline(),
              _ItemRow(item: f, color: color, tip: tips.contains(f.id), onTap: () => showVerdictSheet(context, f)),
            ],
            const SizedBox(height: S.x6),
          ],
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x8),
            child: Column(
              children: [
                const Icon(PhosphorIconsRegular.magnifyingGlass, size: 28, color: C.faint),
                const SizedBox(height: S.x3),
                Text('Nothing called "$_query" yet', style: T.heading),
                const SizedBox(height: S.x1),
                Text('Try a simpler word, or log it as mixed food scraps.', style: T.small, textAlign: TextAlign.center),
              ],
            ),
          ),
      ].animate(interval: 30.ms).fadeIn(duration: 300.ms, curve: M.ease),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      decoration: BoxDecoration(color: C.onBrand, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: C.muted),
          const SizedBox(width: S.x3),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: T.heading.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Banana peel, cardboard, coffee…',
                hintStyle: T.body.copyWith(color: C.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.color, required this.tip, required this.onTap});
  final FoodItem item;
  final Color color;
  final bool tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: C.surface,
                shape: BoxShape.circle,
                border: Border.all(color: C.line),
              ),
              child: Icon(item.icon, size: 19, color: color),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item.name, style: T.heading.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (tip) ...[const SizedBox(width: S.x2), const PinkPill('TIP')],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            const Icon(PhosphorIconsRegular.caretRight, size: 16, color: C.faint),
          ],
        ),
      ),
    );
  }
}
