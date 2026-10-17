part of 'social_screen.dart';

mixin SocialActions<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  bool busy = false;
  String? error;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is SocialFailure
              ? e.message
              : 'Something went wrong. Please try again',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget status() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        const LinearProgressIndicator(color: C.forest, backgroundColor: C.sunk),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Text(error!, style: T.body.copyWith(color: C.clay)),
        ),
    ],
  );
}

class SocialData extends ConsumerWidget {
  const SocialData({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(dynamic) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(socialDataProvider(path))
      .when(
        data: (data) => data == null ? const SizedBox.shrink() : builder(data),
        loading: () => const Padding(
          padding: EdgeInsets.all(S.x5),
          child: Center(child: CircularProgressIndicator(color: C.forest)),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error is SocialFailure
                    ? error.message
                    : 'Could not load this yet',
                style: T.body.copyWith(color: C.clay),
              ),
              smallAction(
                'Try again',
                () => ref.invalidate(socialDataProvider(path)),
              ),
              if (error is SocialFailure && error.status == 401)
                smallAction('Sign in again', () async {
                  await ref.read(socialSessionProvider.notifier).signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                }),
            ],
          ),
        ),
      );
}

String activityLabel(String kind) => switch (kind) {
  'check_in' => 'Checked on their compost',
  'followed_suggestion' => 'Followed their bin’s next best action',
  'avoided_bad_add' => 'Kept a harmful item out',
  'harvest' => 'Harvested finished compost',
  'healthy_layer_day' => 'Kept a layer in its healthy range',
  'weekly_balance' => 'Kept greens and browns balanced',
  'daily_quest' => 'Completed a daily quest',
  _ => 'Cared for their compost',
};
String relativeTime(String value) {
  final d = DateTime.now().difference(DateTime.parse(value));
  return d.inMinutes < 1
      ? 'Just now'
      : d.inHours < 1
      ? '${d.inMinutes}m ago'
      : d.inDays < 1
      ? '${d.inHours}h ago'
      : '${d.inDays}d ago';
}

Widget stat(String value, String label) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(value, style: T.value),
    Text(label, style: T.small),
  ],
);
Widget heroStat(String value, String label) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(value, style: T.value.copyWith(color: C.onBrand)),
    Text(label, style: T.small.copyWith(color: C.onBrandMuted)),
  ],
);
Widget smallAction(String label, VoidCallback? action) => TextButton(
  style: TextButton.styleFrom(
    foregroundColor: C.forest,
    textStyle: T.button,
    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x2),
  ),
  onPressed: action,
  child: Text(label),
);
Widget emptyNote(String title, String body) => Padding(
  padding: const EdgeInsets.symmetric(vertical: S.x6),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: T.heading),
      const SizedBox(height: S.x2),
      Text(body, style: T.body),
    ],
  ),
);
Widget personRow(
  BuildContext context,
  Json p, {
  String? subtitle,
  Widget? actions,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: S.x3),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Pressable(
        onTap: () => openSocial(context, PersonScreen(id: p['user_id'])),
        child: Row(
          children: [
            Avatar(p['display_name'], size: 36),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['display_name'],
                    style: T.heading,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(subtitle ?? '@${p['handle']}', style: T.small),
                ],
              ),
            ),
            const Icon(
              PhosphorIconsRegular.caretRight,
              color: C.muted,
              size: 18,
            ),
          ],
        ),
      ),
      if (actions != null)
        Padding(
          padding: const EdgeInsets.only(top: S.x2),
          child: actions,
        ),
    ],
  ),
);

void openSocial(BuildContext context, Widget page) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: C.paper,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: BackButton(color: C.forest),
                ),
                Expanded(child: page),
              ],
            ),
          ),
        ),
      ),
    );

class SocialField extends StatelessWidget {
  const SocialField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.secret = false,
    this.maxLength,
    this.validator,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool secret;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: S.x2),
    child: TextFormField(
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      maxLength: maxLength,
      style: T.body,
      validator:
          validator ??
          (v) => (v?.trim().isEmpty ?? true) ? 'Enter $label' : null,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: T.small,
        hintStyle: T.small,
        filled: true,
        fillColor: C.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.chip),
          borderSide: const BorderSide(color: C.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.chip),
          borderSide: const BorderSide(color: C.forest),
        ),
        contentPadding: const EdgeInsets.all(S.x4),
      ),
    ),
  );
}

Future<String?> askText(
  BuildContext context,
  String title,
  String label, {
  String? hint,
  bool secret = false,
  int maxLength = 100,
}) async {
  final controller = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.paper,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        S.gutter,
        S.x6,
        S.gutter,
        MediaQuery.viewInsetsOf(context).bottom + S.x6,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: T.title),
            SocialField(
              controller: controller,
              label: label,
              hint: hint,
              secret: secret,
              maxLength: maxLength,
            ),
            const SizedBox(height: S.x4),
            PillButton(
              label: 'Continue',
              onTap: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
  // Bottom-sheet reverse animation still uses the controller after pop.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  controller.dispose();
  return result;
}

Future<void> showInvite(
  BuildContext context,
  String code,
  bool group,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: C.paper,
  builder: (context) => Padding(
    padding: const EdgeInsets.all(S.x6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(group ? 'Your group invite' : 'Invite a friend', style: T.title),
        const SizedBox(height: S.x3),
        Text(
          group
              ? 'Share this code with your group. Joining shares compost XP and estimated amounts on the private leaderboard.'
              : 'Share this code with a friend. Using it lets you both follow each other and see private progress.',
          style: T.body,
        ),
        const SizedBox(height: S.x5),
        SelectableText(code, style: T.heading),
        const SizedBox(height: S.x3),
        Text(
          'Valid for 7 days. Creating another invite replaces this one.',
          style: T.small,
        ),
        const SizedBox(height: S.x5),
        PillButton(
          label: 'Copy invite code',
          icon: PhosphorIconsRegular.copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
  ),
);
Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.paper,
        title: Text(title, style: T.title),
        content: Text(body, style: T.body),
        actions: [
          smallAction('Cancel', () => Navigator.pop(context, false)),
          smallAction('Confirm', () => Navigator.pop(context, true)),
        ],
      ),
    ) ??
    false;
Future<Json?> editProfile(BuildContext context, Json profile) async {
  final name = TextEditingController(text: profile['display_name']),
      bio = TextEditingController(text: profile['bio']);
  var private = profile['is_private'] as bool;
  final result = await showModalBottomSheet<Json>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.paper,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => Padding(
        padding: EdgeInsets.fromLTRB(
          S.gutter,
          S.x5,
          S.gutter,
          MediaQuery.viewInsetsOf(context).bottom + S.x5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your growing space', style: T.title),
              SocialField(
                controller: name,
                label: 'Display name',
                maxLength: 48,
              ),
              SocialField(controller: bio, label: 'Bio', maxLength: 160),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: C.forest,
                title: Text('Private profile', style: T.heading),
                subtitle: Text(
                  'Only approved followers see your progress.',
                  style: T.small,
                ),
                value: private,
                onChanged: (v) => set(() => private = v),
              ),
              Text(
                'Your name and username can be found in search.',
                style: T.small,
              ),
              const SizedBox(height: S.x4),
              PillButton(
                label: 'Save profile',
                onTap: () {
                  if (name.text.trim().isNotEmpty) {
                    Navigator.pop(context, {
                      'display_name': name.text.trim(),
                      'bio': bio.text.trim(),
                      'is_private': private,
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  name.dispose();
  bio.dispose();
  return result;
}
