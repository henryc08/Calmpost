import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
import '../../domain/trunc_guidance.dart';
import '../../app/routes.dart';
import '../../state/providers.dart';
import '../../state/trunc_chat.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class TruncScreen extends ConsumerStatefulWidget {
  const TruncScreen({super.key});
  @override
  ConsumerState<TruncScreen> createState() => _TruncScreenState();
}

class _TruncScreenState extends ConsumerState<TruncScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? prompt]) {
    final text = (prompt ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    ref.read(truncChatProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(truncChatProvider);
    final snapshot = ref.watch(binProvider).valueOrNull;
    final guidance = snapshot == null ? null : guidanceFor(snapshot);
    final asked = {for (final e in chat.exchanges) e.question};
    final replies = [for (final q in _quickReplies(guidance)) if (!asked.contains(q)) q].take(4).toList();
    Widget quickReplies() => Wrap(
      spacing: S.x2,
      runSpacing: S.x2,
      children: [for (final q in replies) PillButton(label: q, dense: true, color: C.sunk, textColor: C.ink, onTap: () => _send(q))],
    );
    ref.listen(repositoryProvider, (_, _) => _input.clear());
    ref.listen(truncChatProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && next.exchanges.isNotEmpty) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    });
    return Scaffold(
      backgroundColor: C.paper,
      body: Column(
        children: [
          Expanded(
            child: BrandPage(
              controller: _scroll,
              title: 'Trunc',
              subtitle: 'Advice for your bin’s current state',
              trailing: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
              ),
              children: [
                // Open with what the bin needs, so nobody has to think of a question first.
                const SectionLabel('TRUNC'),
                const SizedBox(height: S.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    guidance?.action ?? 'Ask me anything about your compost: what to add, smells, moisture or when it is ready.',
                    style: T.body,
                  ),
                ),
                if (chat.exchanges.isEmpty) ...[const SizedBox(height: S.x4), quickReplies()],
                const SizedBox(height: S.x3),
                Row(
                  children: [
                    Checkbox(
                      value: chat.includePhotos,
                      activeColor: C.forest,
                      onChanged: chat.waiting ? null : (v) => ref.read(truncChatProvider.notifier).includePhotos(v!),
                    ),
                    Expanded(child: Text('Include recent bin photos with my questions', style: T.small)),
                  ],
                ),
                for (final exchange in chat.exchanges) ...[
                  const SectionBreak(),
                  const SectionLabel('YOU'),
                  const SizedBox(height: S.x2),
                  SelectableText(exchange.question, style: T.body),
                  const SizedBox(height: S.x5),
                  const SectionLabel('TRUNC'),
                  const SizedBox(height: S.x2),
                  if (exchange.answer case final answer?) ...[
                    SelectableText(answer.reply, style: T.body),
                    const SizedBox(height: S.x3),
                    Text(_context(answer), style: T.small),
                    if (identical(exchange, chat.exchanges.last) && !chat.waiting && replies.isNotEmpty) ...[
                      const SizedBox(height: S.x4),
                      quickReplies(),
                    ],
                  ],
                ],
                if (chat.waiting)
                  Semantics(
                    liveRegion: true,
                    child: const Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.forest)),
                        SizedBox(width: S.x3),
                        Text('Thinking…'),
                      ],
                    ),
                  ),
                if (chat.failed) ...[
                  Text(
                    'Could not reach Trunc. Your question is kept here; retry when connected. Trunc needs a bin linked to this account.',
                    style: T.small.copyWith(color: C.clay),
                  ),
                  const SizedBox(height: S.x3),
                  if (ref.watch(needsBinProvider)) PillButton(label: 'Connect bin', onTap: () => Routes.connectBin(context)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PillButton(label: 'Retry question', onTap: () => ref.read(truncChatProvider.notifier).retry()),
                  ),
                ],
                if (chat.exchanges.isNotEmpty) ...[
                  const SizedBox(height: S.x5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PillButton(
                      label: 'Clear conversation',
                      dense: true,
                      color: C.sunk,
                      textColor: C.ink,
                      onTap: () {
                        _input.clear();
                        ref.read(truncChatProvider.notifier).clear();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('trunc-input'),
                      controller: _input,
                      enabled: !chat.waiting && !chat.failed,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 1000,
                      style: T.body,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Ask Trunc anything about your bin',
                        hintStyle: T.small,
                        filled: true,
                        fillColor: C.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.tile),
                          borderSide: const BorderSide(color: C.line),
                        ),
                        contentPadding: const EdgeInsets.all(S.x3),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, value, _) =>
                        PillButton(label: 'Send', dense: true, onTap: chat.waiting || chat.failed || value.text.trim().isEmpty ? null : () => _send()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Follow-ups worth one tap, led by whatever the bin needs right now.
  static List<String> _quickReplies(TruncGuidance? g) => [
    'What should I add right now?',
    if (g?.status == 'inspect') 'Why is the bottom different from the top?',
    if (g?.need == BinNeed.browns) 'What counts as a brown?',
    if (g?.need == BinNeed.greens) 'What counts as a green?',
    if (g?.need == BinNeed.water) 'How much water should I add?',
    'Why does my bin smell?',
    'Can I add banana peels?',
    'Is my compost ready yet?',
  ];

  String _context(TruncReply reply) {
    final c = reply.context;
    final time = c.readingsAt?.toLocal();
    return [
      if (reply.model.startsWith('rules')) 'Rule-based reply.',
      if (c.readingsStale || (time != null && DateTime.now().difference(time) > const Duration(minutes: 2))) 'These readings are stale.',
      time == null
          ? 'General guidance · no sensor readings available.'
          : 'Readings available: ${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}.',
      '${c.recentAdds} recent additions · ${c.photos} photos provided.',
      if (reply.usedReadings) 'This answer used your readings.',
    ].join(' ');
  }
}
