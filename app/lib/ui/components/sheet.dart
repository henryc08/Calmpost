import 'package:flutter/material.dart';

import '../tokens.dart';

/// Opens a cream bottom sheet with a grabber. All sheets in the app use this.
Future<T?> showCalmSheet<T>(BuildContext context, {required WidgetBuilder builder, Color color = C.bg, bool scroll = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: color,
    barrierColor: C.ink.withValues(alpha: 0.45),
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
    builder: (context) {
      final body = Padding(padding: EdgeInsets.fromLTRB(S.gutter, 0, S.gutter, S.x6 + MediaQuery.viewInsetsOf(context).bottom), child: builder(context));
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: S.x3, bottom: S.x4),
            width: 44,
            height: 5,
            decoration: BoxDecoration(color: C.borderDark, borderRadius: BorderRadius.circular(5)),
          ),
          Flexible(child: scroll ? SingleChildScrollView(child: body) : body),
        ],
      );
    },
  );
}
