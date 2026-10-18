part of 'social_screen.dart';

class ActivityList extends ConsumerStatefulWidget {
  const ActivityList({super.key, this.target});
  final String? target;
  @override
  ConsumerState<ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends ConsumerState<ActivityList>
    with SocialActions {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      status(),
      SocialData(
        path: widget.target == null ? '/feed' : '/feed?target=${widget.target}',
        builder: (data) {
          final rows = data as List;
          final uid = ref.watch(socialSessionProvider).valueOrNull?.userId;
          if (rows.isEmpty) {
            return emptyNote(
              'Small steps start here',
              'Check on your compost, then invite a friend to share the habit.',
            );
          }
          return Column(
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      personRow(
                        context,
                        row as Json,
                        subtitle: relativeTime(row['time']),
                      ),
                      Text(activityLabel(row['kind']), style: T.heading),
                      const SizedBox(height: S.x2),
                      Row(
                        children: [
                          PinkPill('+${row['xp']} XP'),
                          const Spacer(),
                          if (row['user_id'] != uid)
                            smallAction(
                              row['cheered'] == true
                                  ? 'Cheered · ${row['cheers']}'
                                  : 'Cheer · ${row['cheers']}',
                              busy || row['cheered'] == true
                                  ? null
                                  : () => run(() async {
                                      await socialWrite(
                                        ref,
                                        'POST',
                                        '/events/${row['id']}/cheer',
                                      );
                                    }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
