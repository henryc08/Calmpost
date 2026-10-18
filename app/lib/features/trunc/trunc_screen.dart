import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models.dart';
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
                Text(
                  'Each question uses the latest available bin readings and confirmed additions. Missing or stale readings limit what Trunc can recommend. Conversation stays in app memory.',
                  style: T.small,
                ),
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
                if (chat.exchanges.isEmpty) ...[
                  const SectionBreak(),
                  Text('What does your bin need?', style: T.heading),
                  const SizedBox(height: S.x3),
                  for (final prompt in ['Should I add more apples to this compost?', 'Why does my bin smell?', 'What should I do next?']) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PillButton(label: prompt, dense: true, onTap: () => _send(prompt)),
                    ),
                    const SizedBox(height: S.x2),
                  ],
                ],
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
                        hintText: 'Should I add apples right now?',
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
