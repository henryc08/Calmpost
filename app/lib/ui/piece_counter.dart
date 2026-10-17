import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'components.dart';
import 'tokens.dart';
import 'type.dart';

/// A reviewed count of pieces, or portions for loose material. Weight is the
/// total for the row, so changing this does not silently multiply its mass.
class PieceCounter extends StatelessWidget {
  const PieceCounter({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('PIECES / PORTIONS', style: T.caps.copyWith(fontSize: 10.5)),
      const SizedBox(height: S.x2),
      Row(
        children: [
          IconButton(
            tooltip: 'Fewer pieces',
            onPressed: onChanged == null || value <= 1 ? null : () => onChanged!(value - 1),
            icon: const Icon(PhosphorIconsRegular.minus, color: C.ink2),
          ),
          Semantics(liveRegion: true, child: Text('$value', style: T.value)),
          IconButton(
            tooltip: 'More pieces',
            onPressed: onChanged == null || value >= 999 ? null : () => onChanged!(value + 1),
            icon: const Icon(PhosphorIconsRegular.plus, color: C.ink2),
          ),
        ],
      ),
      Text('Count whole scraps; use portions for loose material. Weight below is the total.', style: T.small),
    ],
  );
}

/// Exact total weight can be corrected without committing an invalid field.
Future<double?> editCompostWeight(BuildContext context, double initial) async {
  final controller = TextEditingController(text: initial.round().toString());
  final result = await showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final grams = int.tryParse(controller.text);
        final valid = grams != null && grams >= 1 && grams <= 5000;
        return AlertDialog(
          backgroundColor: C.paper,
          title: Text('Total estimated weight', style: T.heading),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: T.body,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Grams for all pieces', labelStyle: T.small, errorText: valid ? null : 'Enter 1–5000 g', border: const UnderlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: T.button),
            ),
            PillButton(label: 'Use weight', dense: true, onTap: valid ? () => Navigator.pop(context, grams.toDouble()) : null),
          ],
        );
      },
    ),
  );
  // The dialog's route transition may still reference its controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
