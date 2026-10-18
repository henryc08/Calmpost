part of 'social_screen.dart';

String _exchangeRequestId() =>
    'exchange-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';

/// An authenticated, group-scoped board. Every write crosses SocialRepository.
class ExchangeScreen extends ConsumerStatefulWidget {
  const ExchangeScreen({super.key, required this.circleId});
  final String circleId;
  @override
  ConsumerState<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends ConsumerState<ExchangeScreen>
    with SocialActions {
  String _view = 'active';
  int? _before;
  final _pages = <int?>[];
  final _claims = <int, Json>{};
  String? _notice;
  SocialSession? _account;
  @override
  void initState() {
    super.initState();
    _account = ref.read(socialSessionProvider).valueOrNull;
  }

  String get _base => '/circles/${widget.circleId}/exchange';
  String get _path =>
      '$_base?view=$_view${_before == null ? '' : '&before=$_before'}';

  Future<void> _action(Json post, String action, Json body) =>
      run(() => _execute(post, action, body));

  Future<void> _execute(Json post, String action, Json body) async {
    final account = ref.read(socialSessionProvider).valueOrNull;
    if (account?.token != _account?.token ||
        account?.userId != _account?.userId) {
      throw const SocialFailure(
        'Your account changed. Reopen this group to continue.',
      );
    }
    Json result;
    try {
      result =
          await socialWrite(ref, 'POST', '$_base/${post['id']}/$action', body)
              as Json;
    } on SocialFailure catch (e) {
      if (e.status == 409) {
        _claims.remove(post['id']);
        ref.invalidate(socialDataProvider(_path));
      }
      rethrow;
    }
    _claims.remove(post['id']);
    if (!mounted) return;
    setState(
      () => _notice = result['status'] == 'completed'
          ? 'Exchange completed. Your saved reward: ${result['creator']['user_id'] == account?.userId ? result['creator_xp'] : result['responder_xp']} XP.'
          : action == 'confirm'
          ? 'Your confirmation is saved.'
          : 'Exchange updated.',
    );
    if (result['status'] == 'completed') {
      await ref.read(gameProvider.notifier).refreshLive();
    }
  }

  Future<void> _claim(Json post) async {
    // A failed request keeps its original reservation intent for safe retries.
    final id = post['id'] as int;
    var body = _claims[id];
    if (body == null) {
      final note = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: C.paper,
        builder: (_) => const _ExchangeNoteSheet(
          title: 'Arrange the handoff',
          initial: '',
          button: 'Reserve',
          explanation:
              'Optional: suggest when and where. Only you and the person who posted can read these notes.',
        ),
      );
      if (note == null || !mounted) return;
      body = _claims[id] = {
        'version': post['version'],
        'request_id': _exchangeRequestId(),
        'note': note,
      };
    }
    await _action(post, 'claim', body);
  }

  Future<void> _note(Json post, bool creator) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.paper,
      builder: (_) => _ExchangeNoteSheet(
        title: 'Your handoff note',
        initial:
            post[creator ? 'creator_note' : 'responder_note'] as String? ?? '',
        button: 'Save note',
        explanation:
            'Only the two participants can read these notes. You can suggest a time, place or what help is needed.',
      ),
    );
    if (value != null && mounted) {
      await _action(post, 'note', {
        'reservation_id': post['reservation_id'],
        'note': value,
      });
    }
  }

  Future<void> _newPost(List<Json> materials) async {
    final result = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: C.paper,
      builder: (_) =>
          _ExchangeComposer(circleId: widget.circleId, materials: materials),
    );
    if (result != null && mounted) {
      setState(() {
        _view = 'active';
        _before = null;
        _pages.clear();
        _notice = 'Your post is ready for the group.';
      });
    }
  }

  void _rules() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: C.paper,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.all(S.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Useful sharing, rewarded', style: T.title),
          const SizedBox(height: S.x4),
          Text(
            'Both people can earn ${Xp.exchangeCompleted} XP after they each confirm the handoff or help is complete. Posting and reserving earn no XP.',
            style: T.body,
          ),
          const SizedBox(height: S.x3),
          Text(
            'Up to ${Xp.exchangeDailyCap} exchange XP per person per UTC day. The same pair can earn rewards once per UTC day, across all groups. Exchange rewards also share the ${Xp.dailyActionCap} XP daily action cap. You can still complete an exchange after a cap is reached.',
            style: T.body,
          ),
          const SizedBox(height: S.x3),
          Text(
            'Confirmation records what you both report; the app cannot verify a physical handoff. Received material enters compost inventory only when you log it in your bin.',
            style: T.small,
          ),
          const SizedBox(height: S.x4),
          PillButton(label: 'Got it', onTap: () => Navigator.pop(context)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SocialData(
    path: _path,
    builder: (data) {
      final board = data as Json;
      final session = ref.watch(socialSessionProvider).valueOrNull;
      _account ??= session;
      final uid = session?.userId;
      final posts = (board['posts'] as List).cast<Json>();
      return BrandPage(
        title: 'Materials & help',
        subtitle: '${board['name']} · members only',
        hero: Text(
          'Share what someone needs.',
          style: T.heading.copyWith(color: C.onBrand),
        ),
        children: [
          status(),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x3),
              child: Text(_notice!, style: T.body.copyWith(color: C.leaf)),
            ),
          Wrap(
            spacing: S.x3,
            runSpacing: S.x2,
            children: [
              PillButton(
                label: 'Make a request or offer',
                icon: PhosphorIconsRegular.plus,
                onTap: busy
                    ? null
                    : () => _newPost((board['materials'] as List).cast<Json>()),
              ),
              smallAction('How XP works', _rules),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            'Request scraps, offer spare browns or lend a hand. Both people confirm completion before any XP is awarded.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final view in ['active', 'mine', 'history'])
                ChoiceChip(
                  label: Text(switch (view) {
                    'active' => 'Active',
                    'mine' => 'My exchanges',
                    _ => 'History',
                  }),
                  selected: _view == view,
                  selectedColor: C.forest,
                  backgroundColor: C.paper,
                  labelStyle: T.button.copyWith(
                    color: _view == view ? C.onForest : C.ink,
                  ),
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          _view = view;
                          _before = null;
                          _pages.clear();
                          _notice = null;
                        }),
                ),
              IconButton(
                tooltip: 'Refresh exchanges',
                onPressed: busy
                    ? null
                    : () => ref.invalidate(socialDataProvider(_path)),
                icon: const Icon(
                  PhosphorIconsRegular.arrowClockwise,
                  color: C.ink,
                ),
              ),
            ],
          ),
          const SectionBreak(),
          if (posts.isEmpty)
            emptyNote(
              'Nothing here yet',
              _view == 'active'
                  ? 'Post something your bin needs, or offer material you can spare.'
                  : 'Your completed, closed and expired posts will appear here.',
            ),
          for (final post in posts) ...[
            _post(post, uid, board['owner_id'] as String),
            const Hairline(),
          ],
          if (_pages.isNotEmpty || board['next_before'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x4),
              child: Wrap(
                spacing: S.x3,
                children: [
                  if (_pages.isNotEmpty)
                    PillButton(
                      label: 'Newer posts',
                      dense: true,
                      onTap: busy
                          ? null
                          : () => setState(() => _before = _pages.removeLast()),
                    ),
                  if (board['next_before'] != null)
                    PillButton(
                      label: 'Older posts',
                      dense: true,
                      onTap: busy
                          ? null
                          : () => setState(() {
                              _pages.add(_before);
                              _before = board['next_before'] as int;
                            }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: S.x4),
          Text(
            'Open posts and reservations expire after 7 days. Sharing materials does not automatically log them as compost.',
            style: T.small,
          ),
        ],
      );
    },
  );

  Widget _post(Json p, String? uid, String ownerId) {
    final creator = p['creator'] as Json;
    final responder = p['responder'] as Json?;
    final isCreator = creator['user_id'] == uid;
    final isResponder = responder?['user_id'] == uid;
    final participant = isCreator || isResponder;
    final status = p['status'] as String;
    final confirmed =
        p[isCreator ? 'creator_confirmed' : 'responder_confirmed'] == true;
    final anyConfirmed =
        p['creator_confirmed'] == true || p['responder_confirmed'] == true;
    final material = p['material'] as Json;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              Badge2(
                p['kind'] == 'request' ? 'REQUEST' : 'OFFER',
                color: C.forest,
                background: C.sunk,
              ),
              Text(switch (status) {
                'open' => 'Open',
                'reserved' => 'Reserved',
                'completed' => 'Completed',
                'cancelled' => 'Closed',
                _ => 'Expired',
              }, style: T.caps.copyWith(color: C.muted)),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            material['name'] as String,
            style: T.title.copyWith(fontSize: 25),
          ),
          Text(p['quantity'] as String, style: T.heading),
          const SizedBox(height: S.x2),
          if ((p['details'] as String).isNotEmpty)
            Text(p['details'] as String, style: T.body),
          Text(
            'Posted by ${isCreator ? 'you' : creator['display_name']} · ${relativeTime(p['created_at'] as String)}',
            style: T.small,
          ),
          if ((material['note'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.x2),
              child: Text(material['note'] as String, style: T.small),
            ),
          if (status == 'open' && !isCreator) ...[
            const SizedBox(height: S.x3),
            PillButton(
              label: _claims.containsKey(p['id'])
                  ? 'Retry reservation'
                  : p['kind'] == 'request'
                  ? 'I can help with this'
                  : 'Reserve this offer',
              dense: true,
              onTap: busy ? null : () => _claim(p),
            ),
          ],
          if (status == 'reserved') ...[
            const SizedBox(height: S.x3),
            Text(
              participant
                  ? 'Reserved with ${isCreator ? responder!['display_name'] : creator['display_name']}'
                  : 'Reserved by ${responder!['display_name']}',
              style: T.heading,
            ),
            Text(
              '${p['creator_confirmed'] == true ? 'Poster confirmed' : 'Waiting for poster'} · ${p['responder_confirmed'] == true ? 'Responder confirmed' : 'Waiting for responder'}',
              style: T.small,
            ),
            if (participant) ...[
              const SizedBox(height: S.x3),
              Text('PRIVATE HANDOFF NOTES', style: T.caps),
              Text(
                '${creator['display_name']}: ${(p['creator_note'] as String?)?.isNotEmpty == true ? p['creator_note'] : 'No note yet.'}',
                style: T.body,
              ),
              Text(
                '${responder!['display_name']}: ${(p['responder_note'] as String?)?.isNotEmpty == true ? p['responder_note'] : 'No note yet.'}',
                style: T.body,
              ),
              smallAction(
                'Edit your note',
                busy ? null : () => _note(p, isCreator),
              ),
              const SizedBox(height: S.x2),
              if (!confirmed)
                PillButton(
                  label: 'Confirm completed handoff',
                  dense: true,
                  onTap: busy
                      ? null
                      : () async {
                          if (!await confirmAction(
                            context,
                            'Has this exchange happened?',
                            'Only confirm after the material was handed over or the help was completed. Both people must confirm before rewards are saved.',
                          )) {
                            return;
                          }
                          if (mounted) {
                            await _action(p, 'confirm', {
                              'reservation_id': p['reservation_id'],
                            });
                          }
                        },
                )
              else
                Text(
                  'You confirmed. Waiting for the other person.',
                  style: T.small.copyWith(color: C.leaf),
                ),
              if (isResponder && !anyConfirmed)
                smallAction(
                  'Release reservation',
                  busy
                      ? null
                      : () => _action(p, 'release', {
                          'reservation_id': p['reservation_id'],
                        }),
                ),
            ],
          ],
          if (status == 'completed') ...[
            const SizedBox(height: S.x3),
            Text(
              '${creator['display_name']}: ${p['creator_xp']} XP · ${responder!['display_name']}: ${p['responder_xp']} XP',
              style: T.small,
            ),
            Text(
              'Rewards are saved once. Daily and same-person limits may reduce XP.',
              style: T.small,
            ),
          ],
          if (['open', 'reserved', 'expired'].contains(status) &&
              (participant || uid == ownerId))
            smallAction(
              'Close this post',
              busy
                  ? null
                  : () async {
                      if (await confirmAction(
                        context,
                        'Close this exchange?',
                        'No exchange XP is awarded for a closed post.',
                      )) {
                        if (mounted) {
                          await _action(p, 'cancel', {'version': p['version']});
                        }
                      }
                    },
            ),
        ],
      ),
    );
  }
}

class _ExchangeComposer extends ConsumerStatefulWidget {
  const _ExchangeComposer({required this.circleId, required this.materials});
  final String circleId;
  final List<Json> materials;
  @override
  ConsumerState<_ExchangeComposer> createState() => _ExchangeComposerState();
}

class _ExchangeComposerState extends ConsumerState<_ExchangeComposer> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController(), _details = TextEditingController();
  final _requestId = _exchangeRequestId();
  String _kind = 'request';
  late String _material = widget.materials.first['id'] as String;
  bool _saving = false;
  String? _error;
  Json? _submitted;
  SocialSession? _account;
  @override
  void initState() {
    super.initState();
    _account = ref.read(socialSessionProvider).valueOrNull;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) {
      return;
    }
    final account = ref.read(socialSessionProvider).valueOrNull;
    if (account?.token != _account?.token ||
        account?.userId != _account?.userId) {
      setState(
        () => _error = 'Your account changed. Close this form and try again.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = _submitted ??= {
      'kind': _kind,
      'material_id': _material,
      'quantity': _quantity.text.trim(),
      'details': _details.text.trim(),
      'request_id': _requestId,
    };
    try {
      final result =
          await socialWrite(
                ref,
                'POST',
                '/circles/${widget.circleId}/exchange',
                body,
              )
              as Json;
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is SocialFailure
              ? e.message
              : 'Save was not confirmed. Retry this same post.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      S.gutter,
      S.x5,
      S.gutter,
      S.x5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Share with your group', style: T.title),
          const SizedBox(height: S.x3),
          Text(
            'Post a request for what you need, or offer something you can spare. The description is visible to your group.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          PaperSegments<String>(
            values: const ['request', 'offer'],
            selected: _kind,
            label: (v) => v == 'request' ? 'I need' : 'I can offer',
            onChanged: (v) {
              if (_submitted == null && !_saving) {
                setState(() => _kind = v);
              }
            },
          ),
          const SizedBox(height: S.x4),
          DropdownButtonFormField<String>(
            initialValue: _material,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Material or help',
              labelStyle: T.small,
            ),
            items: [
              for (final m in widget.materials)
                DropdownMenuItem(
                  value: m['id'] as String,
                  child: Text(
                    m['name'] as String,
                    style: T.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _saving || _submitted != null
                ? null
                : (v) => setState(() => _material = v!),
          ),
          SocialField(
            controller: _quantity,
            enabled: !_saving && _submitted == null,
            label: 'Amount or help needed',
            hint: 'e.g. one bag, two handfuls, or 20 minutes',
            maxLength: 80,
          ),
          SocialField(
            controller: _details,
            enabled: !_saving && _submitted == null,
            label: 'Details (optional, group visible)',
            hint: 'What you need or can offer',
            maxLength: 500,
            validator: (_) => null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Text(_error!, style: T.body.copyWith(color: C.clay)),
            ),
          if (_submitted != null && !_saving)
            Text(
              'A save was attempted. Retry the same post, or close and check the board before posting again.',
              style: T.small,
            ),
          const SizedBox(height: S.x3),
          Text(
            'Posts expire in 7 days. Posting earns no XP; both people confirm completion first.',
            style: T.small,
          ),
          const SizedBox(height: S.x4),
          PillButton(
            label: _saving
                ? 'Saving…'
                : _submitted != null
                ? 'Retry same post'
                : 'Post to group',
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    ),
  );
}

class _ExchangeNoteSheet extends StatefulWidget {
  const _ExchangeNoteSheet({
    required this.title,
    required this.initial,
    required this.button,
    required this.explanation,
  });
  final String title, initial, button, explanation;
  @override
  State<_ExchangeNoteSheet> createState() => _ExchangeNoteSheetState();
}

class _ExchangeNoteSheetState extends State<_ExchangeNoteSheet> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      S.gutter,
      S.x5,
      S.gutter,
      S.x5 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: T.title),
        const SizedBox(height: S.x3),
        Text(widget.explanation, style: T.body),
        SocialField(
          controller: _text,
          label: 'Your note (optional)',
          maxLength: 500,
          validator: (_) => null,
        ),
        const SizedBox(height: S.x4),
        PillButton(
          label: widget.button,
          onTap: () => Navigator.pop(context, _text.text.trim()),
        ),
      ],
    ),
  );
}
