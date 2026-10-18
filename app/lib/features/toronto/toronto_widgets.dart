import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/routes.dart';
import '../../domain/toronto.dart';
import '../../state/toronto.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

Color routeColor(TorontoRoute route) => switch (route) {
  TorontoRoute.green => C.leaf,
  TorontoRoute.recycling => C.water,
  TorontoRoute.garbage => C.clay,
  _ => C.loam,
};

Future<void> copyTorontoText(
  BuildContext context,
  String text,
  String label,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label copied')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy. Select the text to copy it.'),
        ),
      );
    }
  }
}

class TorontoSourceLink extends StatelessWidget {
  const TorontoSourceLink(this.source, {super.key});
  final TorontoSource source;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () => copyTorontoText(context, source.url, 'Source link'),
        icon: const Icon(PhosphorIconsRegular.copy, size: 16),
        label: Text(source.title, style: T.small),
      ),
      SelectableText(source.url, style: T.small.copyWith(fontSize: 11)),
    ],
  );
}

class TorontoEntry extends StatelessWidget {
  const TorontoEntry({super.key});
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: () => Routes.toronto(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.buildings, color: C.forest, size: 27),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Toronto Challenge', style: T.heading),
                const SizedBox(height: 3),
                Text('Know where it goes. Grow the habit.', style: T.small),
              ],
            ),
          ),
          const Icon(
            PhosphorIconsRegular.arrowRight,
            color: C.forest,
            size: 19,
          ),
        ],
      ),
    ),
  );
}

/// Available even when bin readings fail. Never changes a home-compost verdict.
class TorontoDestination extends ConsumerWidget {
  const TorontoDestination({super.key, required this.catalogId});
  final String catalogId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(torontoDataProvider).valueOrNull;
    final item = data?.forCatalog(catalogId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('TORONTO DISPOSAL'),
        const SizedBox(height: S.x2),
        Text(
          item == null
              ? 'Check the City’s guidance for this material.'
              : '${item.route.label} · ${item.action}',
          style: T.small,
        ),
        TextButton.icon(
          onPressed: () => Routes.torontoItem(context, catalogId: catalogId),
          icon: const Icon(PhosphorIconsRegular.arrowRight, size: 15),
          label: const Text('Toronto instructions & source'),
        ),
      ],
    );
  }
}
