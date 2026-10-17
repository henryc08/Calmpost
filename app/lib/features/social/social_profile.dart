part of 'social_screen.dart';

class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen>
    with SocialActions {
  @override
  Widget build(BuildContext context) => SocialData(
    path: '/people/${widget.id}',
    builder: (data) {
      final p = data as Json;
      final mine = p['is_self'] == true;
      final progress = p['progress'] as Json?;
      return BrandPage(
        title: p['display_name'],
        subtitle: '@${p['handle']}',
        hero: Avatar(p['display_name'], size: 64),
        children: [
          status(),
          if ((p['bio'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x4),
              child: Text(p['bio'], style: T.body),
            ),
          if (!mine)
            PillButton(
              label: switch (p['relationship']) {
                'following' => 'Unfollow',
                'requested' => 'Cancel request',
                _ => p['is_private'] == true ? 'Request to follow' : 'Follow',
              },
              onTap: busy
                  ? null
                  : () => run(() async {
                      await socialWrite(
                        ref,
                        p['relationship'] == 'none' ? 'POST' : 'DELETE',
                        '/people/${widget.id}/follow',
                      );
                    }),
            ),
          if (mine)
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                PillButton(
                  label: 'Edit profile',
                  onTap: busy
                      ? null
                      : () => run(() async {
                          final updated = await editProfile(context, p);
                          if (updated != null && mounted) {
                            await socialWrite(ref, 'PATCH', '/me', updated);
                          }
                        }),
                ),
                PillButton(
                  label: 'Connect my bin',
                  color: C.sunk,
                  textColor: C.ink,
                  onTap: busy
                      ? null
                      : () => run(() async {
                          final token = await askText(
                            context,
                            'Connect your bin',
                            'Device token',
                            hint: 'Use the token from your bin setup',
                            secret: true,
                            maxLength: 200,
                          );
                          if (token != null && mounted) {
                            await ref
                                .read(socialSessionProvider.notifier)
                                .pair(token);
                          }
                        }),
                ),
              ],
            ),
          if (progress == null)
            emptyNote(
              'A private growing space',
              'Follow this person to request access to their progress and activity.',
            ),
          if (progress != null) ...[
            const SectionBreak(),
            const SectionLabel('CARE PROGRESS'),
            const SizedBox(height: S.x4),
            Wrap(
              spacing: S.x6,
              runSpacing: S.x5,
              children: [
                stat('${progress['level']}', 'level'),
                stat('${progress['total_xp']}', 'total care XP'),
                stat('${progress['week_xp']}', 'this week'),
                stat('${progress['streak']} days', 'current streak'),
                stat('${progress['best_streak']} days', 'best streak'),
                stat('${progress['harvests']}', 'harvests'),
              ],
            ),
            const SizedBox(height: S.x5),
            Text(
              '${p['followers']} followers · ${p['following']} following',
              style: T.small,
            ),
            const SectionBreak(),
            const SectionLabel('LAST 6 WEEKS'),
            const SizedBox(height: S.x4),
            CareCalendar(days: (progress['care_days'] as List).cast<String>()),
            const SizedBox(height: S.x2),
            Text(
              'Filled days mark care actions. Dates use UTC.',
              style: T.small,
            ),
            if (mine) ...[
              const SizedBox(height: S.x5),
              PillButton(
                label: progress['checked_in_today'] == true
                    ? 'Checked in today'
                    : 'I checked on my compost',
                onTap: busy || progress['checked_in_today'] == true
                    ? null
                    : () => run(() async {
                        await socialWrite(ref, 'POST', '/check-in');
                      }),
              ),
              const SizedBox(height: S.x3),
              Text(
                'One check-in earns 5 care XP a day. Connected-bin care is saved here too.',
                style: T.small,
              ),
            ],
            const SectionBreak(),
            const SectionLabel('RECENT CARE'),
            ActivityList(target: widget.id),
          ],
          if (mine) ...[
            const SectionBreak(),
            smallAction(
              'Sign out',
              busy
                  ? null
                  : () => run(() async {
                      await ref.read(socialSessionProvider.notifier).signOut();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }),
            ),
          ],
        ],
      );
    },
  );
}

class CareCalendar extends StatelessWidget {
  const CareCalendar({super.key, required this.days});
  final List<String> days;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: S.x1,
        runSpacing: S.x1,
        children: [
          for (var i = 41; i >= 0; i--)
            Builder(
              builder: (_) {
                final d = today
                    .subtract(Duration(days: i))
                    .toIso8601String()
                    .substring(0, 10);
                final cared = days.contains(d);
                return Semantics(
                  label: '$d: ${cared ? 'care recorded' : 'no care recorded'}',
                  child: Tooltip(
                    message: d,
                    child: Container(
                      width: (box.maxWidth - S.x1 * 13) / 14,
                      height: S.x4,
                      decoration: BoxDecoration(
                        color: cared ? C.forest : C.sunk,
                        borderRadius: BorderRadius.circular(S.x1),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
