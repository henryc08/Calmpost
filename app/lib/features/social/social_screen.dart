import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/social_repository.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';
import 'demo_league_screen.dart';

part 'social_account.dart';
part 'social_profile.dart';
part 'social_group.dart';
part 'social_activity.dart';
part 'social_widgets.dart';

// All network and persistence work crosses the repository/provider boundary.
class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});
  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen>
    with SocialActions {
  int view = 0;
  final search = TextEditingController();
  String query = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> invite([String? circle]) => run(() async {
    final result =
        await socialWrite(
              ref,
              'POST',
              circle == null ? '/invites' : '/circles/$circle/invite',
            )
            as Json;
    if (!mounted) return;
    await showInvite(context, result['code'] as String, circle != null);
  });

  Future<void> join() => run(() async {
    final value = await askText(
      context,
      'Join your people',
      'Paste an invite code',
      hint: 'A friend or private group code',
    );
    if (value == null || !mounted) return;
    final code = Uri.tryParse(value)?.queryParameters['code'] ?? value.trim();
    final result =
        await socialWrite(ref, 'POST', '/join', {'code': code}) as Json;
    if (!mounted) return;
    if (result['circle_id'] != null) {
      openSocial(context, CircleScreen(id: result['circle_id']));
    } else {
      openSocial(context, PersonScreen(id: result['user_id']));
    }
  });

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(socialSessionProvider);
    if (account.isLoading) {
      return const Center(child: CircularProgressIndicator(color: C.forest));
    }
    if (account.hasError) {
      return BrandPage(
        title: 'Social',
        children: [
          Text('Could not restore your account.', style: T.body),
          PillButton(
            label: 'Try again',
            onTap: () => ref.invalidate(socialSessionProvider),
          ),
        ],
      );
    }
    final session = account.valueOrNull;
    if (session == null) return const SocialWelcome();
    return BrandPage(
      title: 'Grow together',
      subtitle: 'A little care. A shared habit.',
      trailing: IconButton(
        tooltip: 'Your social profile',
        onPressed: () => openSocial(context, PersonScreen(id: session.userId)),
        icon: const Icon(PhosphorIconsRegular.userCircle, color: C.onBrand),
      ),
      hero: SocialData(
        path: '/me',
        builder: (data) {
          final p = data['progress'] as Json;
          return Wrap(
            spacing: S.x5,
            runSpacing: S.x3,
            children: [
              heroStat('${p['week_xp']}', 'care XP this week'),
              heroStat('${p['streak']}', 'day streak'),
            ],
          );
        },
      ),
      children: [
        status(),
        Wrap(
          spacing: S.x2,
          runSpacing: S.x2,
          children: [
            PillButton(
              label: 'Invite a friend',
              icon: PhosphorIconsRegular.userPlus,
              onTap: busy ? null : () => invite(),
            ),
            PillButton(
              label: 'Join with a code',
              color: C.sunk,
              textColor: C.ink,
              onTap: busy ? null : join,
            ),
          ],
        ),
        const SizedBox(height: S.x5),
        Wrap(
          spacing: S.x2,
          runSpacing: S.x2,
          children: [
            for (final entry in [
              'Activity',
              'People',
              'Groups',
            ].asMap().entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: view == entry.key,
                selectedColor: C.forest,
                backgroundColor: C.paper,
                labelStyle: T.button.copyWith(
                  color: view == entry.key ? C.onForest : C.ink,
                ),
                onSelected: (_) => setState(() => view = entry.key),
              ),
            IconButton(
              tooltip: 'Refresh social',
              onPressed: () => ref.invalidate(socialDataProvider),
              icon: const Icon(
                PhosphorIconsRegular.arrowClockwise,
                color: C.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x5),
        if (view == 0) ...[
          const SectionLabel('YOUR CIRCLE, IN MOTION'),
          const SizedBox(height: S.x3),
          Text(
            'Care activity from you and the people you follow.',
            style: T.small,
          ),
          const ActivityList(),
        ],
        if (view == 1) ...[
          SocialField(
            controller: search,
            label: 'Find a username',
            onSubmitted: (v) => setState(() => query = v.trim()),
          ),
          const SizedBox(height: S.x2),
          PillButton(
            label: 'Find people',
            onTap: () => setState(() => query = search.text.trim()),
          ),
          if (query.isNotEmpty)
            SocialData(
              path: '/people?q=${Uri.encodeQueryComponent(query)}',
              builder: (data) => peopleList(
                data as List,
                empty: 'No usernames found. Try at least two letters.',
              ),
            ),
          const SectionBreak(),
          const SectionLabel('FOLLOW REQUESTS & CONNECTIONS'),
          SocialData(
            path: '/connections',
            builder: (data) {
              final rows = (data as List).cast<Json>();
              if (rows.isEmpty) {
                return emptyNote(
                  'Your people belong here',
                  'Invite a friend or search their username to start following their progress.',
                );
              }
              return Column(
                children: [
                  for (final p in rows)
                    personRow(
                      context,
                      p,
                      subtitle: p['incoming'] == true
                          ? (p['accepted'] == true
                                ? 'Follows you'
                                : 'Wants to follow you')
                          : (p['accepted'] == true
                                ? 'Following'
                                : 'Request sent'),
                      actions: p['incoming'] == true
                          ? Wrap(
                              spacing: S.x2,
                              children: [
                                if (p['accepted'] != true)
                                  smallAction(
                                    'Accept',
                                    () => run(() async {
                                      await socialWrite(
                                        ref,
                                        'POST',
                                        '/requests/${p['user_id']}',
                                        {'accept': true},
                                      );
                                    }),
                                  ),
                                smallAction(
                                  p['accepted'] == true ? 'Remove' : 'Decline',
                                  () => run(() async {
                                    await socialWrite(
                                      ref,
                                      'DELETE',
                                      '/followers/${p['user_id']}',
                                    );
                                  }),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
        ],
        if (view == 2) ...[
          const SectionLabel('PRIVATE LEADERBOARDS'),
          const SizedBox(height: S.x3),
          Text(
            'A friendly weekly race for your household, friends or campus. Only invited members see the board.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          PillButton(
            label: 'Create a group',
            icon: PhosphorIconsRegular.usersThree,
            onTap: busy
                ? null
                : () => run(() async {
                    final name = await askText(
                      context,
                      'Your new group',
                      'Group name',
                      hint: 'e.g. The balcony growers',
                      maxLength: 48,
                    );
                    if (name == null || !mounted) return;
                    final result =
                        await socialWrite(ref, 'POST', '/circles', {
                              'name': name,
                            })
                            as Json;
                    if (context.mounted) {
                      openSocial(context, CircleScreen(id: result['id']));
                    }
                  }),
          ),
          SocialData(
            path: '/circles',
            builder: (data) {
              final rows = data as List;
              if (rows.isEmpty) {
                return emptyNote(
                  'Make it your own',
                  'Create a private group, then share its invite code with your people.',
                );
              }
              return Column(
                children: [
                  for (final p in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x4),
                      child: Pressable(
                        onTap: () =>
                            openSocial(context, CircleScreen(id: p['id'])),
                        child: Row(
                          children: [
                            const Icon(
                              PhosphorIconsRegular.lockKey,
                              color: C.forest,
                            ),
                            const SizedBox(width: S.x3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'], style: T.heading),
                                  Text(
                                    '${p['members']} members · invite only',
                                    style: T.small,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              PhosphorIconsRegular.arrowRight,
                              color: C.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SectionBreak(),
        Text(
          'Rankings reward care, never the amount of food added. Weekly boards reset Sunday at 00:00 UTC.',
          style: T.small,
        ),
      ],
    );
  }

  Widget peopleList(List rows, {required String empty}) => rows.isEmpty
      ? Padding(
          padding: const EdgeInsets.all(S.x4),
          child: Text(empty, style: T.body),
        )
      : Column(children: [for (final p in rows) personRow(context, p as Json)]);
}
