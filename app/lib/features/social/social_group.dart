part of 'social_screen.dart';

class CircleScreen extends ConsumerStatefulWidget {
  const CircleScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends ConsumerState<CircleScreen>
    with SocialActions {
  String period = 'week';
  @override
  Widget build(BuildContext context) => SocialData(
    path: '/circles/${widget.id}?period=$period',
    builder: (data) {
      final group = data as Json;
      final uid = ref.watch(socialSessionProvider).valueOrNull?.userId;
      final owner = group['owner_id'] == uid;
      return BrandPage(
        title: group['name'],
        subtitle:
            'Private group · ${(group['members'] as List).length} growers',
        hero: heroStat('${group['team_xp']}', 'care XP together'),
        children: [
          status(),
          if (owner)
            PillButton(
              label: 'Invite to this group',
              icon: PhosphorIconsRegular.link,
              onTap: busy
                  ? null
                  : () => run(() async {
                      final result =
                          await socialWrite(
                                ref,
                                'POST',
                                '/circles/${widget.id}/invite',
                              )
                              as Json;
                      if (context.mounted) {
                        await showInvite(context, result['code'], true);
                      }
                    }),
            ),
          const SizedBox(height: S.x4),
          Text(
            'A little friendly motivation. Every care action helps the whole group grow.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          Wrap(
            spacing: S.x2,
            children: [
              for (final p in ['week', 'all'])
                ChoiceChip(
                  label: Text(p == 'week' ? 'This week' : 'All time'),
                  selected: period == p,
                  selectedColor: C.forest,
                  backgroundColor: C.paper,
                  labelStyle: T.button.copyWith(
                    color: period == p ? C.onForest : C.ink,
                  ),
                  onSelected: (_) => setState(() => period = p),
                ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            'Weekly reset: Sunday 00:00 UTC. Equal XP shares a rank.',
            style: T.small,
          ),
          const SectionBreak(),
          const SectionLabel('YOUR LEADERBOARD'),
          for (final row in group['members'] as List)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '#${row['rank']}',
                          style: T.heading.copyWith(color: C.leaf),
                        ),
                      ),
                      Expanded(
                        child: Pressable(
                          onTap: () => openSocial(
                            context,
                            PersonScreen(id: row['user_id']),
                          ),
                          child: Row(
                            children: [
                              Avatar(row['display_name'], size: 36),
                              const SizedBox(width: S.x3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['display_name'],
                                      style: T.heading,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      row['is_you'] == true
                                          ? 'You'
                                          : '@${row['handle']}',
                                      style: T.small,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      PinkPill('${row['xp']} XP'),
                    ],
                  ),
                  if (owner && row['user_id'] != uid)
                    Align(
                      alignment: Alignment.centerRight,
                      child: smallAction(
                        'Remove member',
                        busy
                            ? null
                            : () => run(() async {
                                if (await confirmAction(
                                  context,
                                  'Remove ${row['display_name']}?',
                                  'They will lose access to this group. Existing invite codes will stop working.',
                                )) {
                                  if (mounted) {
                                    await socialWrite(
                                      ref,
                                      'DELETE',
                                      '/circles/${widget.id}/members/${row['user_id']}',
                                    );
                                  }
                                }
                              }),
                      ),
                    ),
                ],
              ),
            ),
          const SectionBreak(),
          Text(
            'Group membership shares leaderboard scores. Private care histories still require an approved follow.',
            style: T.small,
          ),
          const SizedBox(height: S.x4),
          smallAction(
            owner ? 'Delete group' : 'Leave group',
            busy
                ? null
                : () => run(() async {
                    if (!await confirmAction(
                      context,
                      owner ? 'Delete this group?' : 'Leave this group?',
                      owner
                          ? 'The private leaderboard and invitations will be removed. Everyone keeps their own care progress.'
                          : 'You will need a new invite to rejoin.',
                    )) {
                      return;
                    }
                    if (!mounted) return;
                    await socialWrite(
                      ref,
                      'DELETE',
                      owner
                          ? '/circles/${widget.id}'
                          : '/circles/${widget.id}/members/$uid',
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  }),
          ),
        ],
      );
    },
  );
}
