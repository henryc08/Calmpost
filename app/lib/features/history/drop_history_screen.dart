import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/calmpost_repository.dart';
import '../../domain/drop_history.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

final dropPhotoProvider = FutureProvider.autoDispose.family<Uint8List?, int>((ref, id) => ref.watch(repositoryProvider).dropPhoto(id));

String _date(DateTime time) => '${time.month}/${time.day}/${time.year} · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class DropHistoryScreen extends ConsumerStatefulWidget {
  const DropHistoryScreen({super.key});
  @override
  ConsumerState<DropHistoryScreen> createState() => _DropHistoryScreenState();
}

class _DropHistoryScreenState extends ConsumerState<DropHistoryScreen> {
  List<PastDrop> _drops = [];
  String? _next;
  bool _busy = false, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy && !reset) return;
    final repo = ref.read(repositoryProvider);
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      if (reset) {
        _drops = [];
        _next = null;
      }
    });
    try {
      final page = await repo.dropHistory(before: _next);
      if (!mounted || generation != _generation) return;
      setState(() {
        final byId = {
          for (final d in _drops) d.id: d,
          for (final d in page.drops)
            if (d.status != DropStatus.pending) d.id: d,
        };
        _drops = byId.values.toList();
        _next = page.nextBefore;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(repositoryProvider, (_, _) => _load(reset: true));
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Past drops',
        subtitle: 'What was seen. What you confirmed.',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: [
          Text(
            'Confirmed and dismissed camera drops and phone photos. Pending additions stay in the review flow. Photos may expire after 30 days.',
            style: T.body,
          ),
          const SizedBox(height: S.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : () => _load(reset: true),
              child: Text('Refresh history', style: T.button),
            ),
          ),
          const SectionBreak(),
          if (_drops.isEmpty && !_busy && !_failed)
            Text(
              _next == null ? 'No past drops yet. Confirm or dismiss an addition to see it here.' : 'No resolved drops on this page. Load older drops below.',
              style: T.body,
            ),
          for (final d in _drops) ...[
            Pressable(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _DropDetails(drop: d, repository: ref.read(repositoryProvider)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x4),
                child: Row(
                  children: [
                    Icon(d.source == 'photo' ? PhosphorIconsRegular.image : PhosphorIconsRegular.camera, color: C.forest),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.status == DropStatus.dismissed
                                ? 'Nothing was added'
                                : d.items.map((i) => i.label).join(', ').isEmpty
                                ? 'Confirmed drop'
                                : d.items.map((i) => i.label).join(', '),
                            style: T.heading,
                          ),
                          Text('${d.source == 'photo' ? 'Phone photo' : 'Bin camera'} · ${_date(d.time)}', style: T.small),
                          Text('${d.status.name}${d.corrected ? ' · corrected' : ''}${d.hasPhoto ? ' · photo' : ''}', style: T.small),
                        ],
                      ),
                    ),
                    const Icon(PhosphorIconsRegular.caretRight, size: 18, color: C.muted),
                  ],
                ),
              ),
            ),
            const Hairline(),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(S.x4),
              child: Center(child: CircularProgressIndicator(color: C.forest)),
            ),
          if (_failed) ...[
            Text('Could not load history. Check your connection and paired bin.', style: T.body),
            PillButton(label: 'Retry history', onTap: () => _load()),
          ],
          if (_next != null && !_failed) ...[const SizedBox(height: S.x4), PillButton(label: 'Load older drops', onTap: _busy ? null : () => _load())],
        ],
      ),
    );
  }
}

class _DropDetails extends ConsumerWidget {
  const _DropDetails({required this.drop, required this.repository});
  final PastDrop drop;
  final CalmpostRepository repository;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sameAccount = identical(ref.watch(repositoryProvider), repository);
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Drop details',
        subtitle: sameAccount ? _date(drop.time) : 'Account changed',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: !sameAccount
            ? [Text('Reopen history for the current bin.', style: T.body)]
            : [
                Text('${drop.source == 'photo' ? 'Phone photo' : 'Bin camera'} · ${drop.status.name}', style: T.label),
                const SizedBox(height: S.x4),
                if (drop.hasPhoto)
                  ref
                      .watch(dropPhotoProvider(drop.id))
                      .when(
                        loading: () => const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator(color: C.forest)),
                        ),
                        error: (_, _) => Column(
                          children: [
                            Text('Could not load the photo.', style: T.body),
                            PillButton(label: 'Retry photo', onTap: () => ref.invalidate(dropPhotoProvider(drop.id))),
                          ],
                        ),
                        data: (bytes) => bytes == null
                            ? Text('Photo no longer available.', style: T.small)
                            : Image.memory(
                                bytes,
                                height: 260,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Text('This stored photo could not be displayed.', style: T.small),
                              ),
                      )
                else
                  Text('No photo was stored for this drop.', style: T.small),
                const SectionBreak(),
                const SectionLabel('ORIGINAL GUESS'),
                const SizedBox(height: S.x3),
                Text(drop.guesses.isEmpty ? 'Identification could not name an item.' : drop.guesses.join(', '), style: T.body),
                const SectionBreak(),
                const SectionLabel('WHAT YOU CONFIRMED'),
                const SizedBox(height: S.x3),
                if (drop.status == DropStatus.dismissed) Text('Nothing was added. This detection did not log compost.', style: T.body),
                if (drop.status != DropStatus.dismissed && drop.items.isEmpty) Text('No item details were stored.', style: T.body),
                for (final i in drop.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.label, style: T.heading),
                        Text(
                          '${i.removed
                              ? 'Kept out / removed'
                              : i.category == 'avoid'
                              ? 'Keep out'
                              : i.category}${i.pieces == null ? '' : ' · ${i.pieces} pieces'}${i.grams == null ? '' : ' · ${i.grams!.round()} g'}',
                          style: T.small,
                        ),
                      ],
                    ),
                  ),
                Text('This is a read-only record; viewing it does not log anything or award XP.', style: T.small),
              ],
      ),
    );
  }
}
