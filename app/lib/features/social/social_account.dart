part of 'social_screen.dart';

class SocialWelcome extends ConsumerStatefulWidget {
  const SocialWelcome({super.key});
  @override
  ConsumerState<SocialWelcome> createState() => _SocialWelcomeState();
}

class _SocialWelcomeState extends ConsumerState<SocialWelcome>
    with SocialActions {
  final handle = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final server = TextEditingController(
    text: const String.fromEnvironment('API_URL'),
  );
  bool register = true;
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in [handle, password, name, server]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BrandPage(
    title: 'Better together',
    subtitle: 'Find your people. Grow a good habit.',
    hero: const Icon(PhosphorIconsRegular.plant, size: 64, color: C.onBrand),
    children: [
      Text('Your own compost community', style: T.title),
      const SizedBox(height: S.x3),
      Text(
        'Follow your friends’ progress, cheer their care streaks and start a private leaderboard.',
        style: T.body,
      ),
      const SizedBox(height: S.x5),
      Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (register)
              SocialField(
                controller: name,
                label: 'Display name',
                maxLength: 48,
              ),
            SocialField(
              controller: handle,
              label: 'Username',
              hint: '3–24 letters, numbers or underscores',
              maxLength: 24,
              validator: (v) =>
                  RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Use 3–24 letters, numbers or underscores',
            ),
            SocialField(
              controller: password,
              label: 'Password',
              secret: true,
              validator: (v) =>
                  (v?.length ?? 0) >= 10 ? null : 'Use at least 10 characters',
            ),
            if (const String.fromEnvironment('API_URL') == '')
              SocialField(
                controller: server,
                label: 'Community server',
                hint: 'The server address shared by your host',
              ),
            const SizedBox(height: S.x3),
            status(),
            PillButton(
              label: register ? 'Create account' : 'Sign in',
              onTap: busy
                  ? null
                  : () => run(() async {
                      if (!form.currentState!.validate()) return;
                      await ref
                          .read(socialSessionProvider.notifier)
                          .signIn(
                            server.text,
                            handle.text,
                            password.text,
                            name: register ? name.text : null,
                          );
                    }),
            ),
            const SizedBox(height: S.x3),
            smallAction(
              register
                  ? 'Already a member? Sign in'
                  : 'New here? Create an account',
              busy ? null : () => setState(() => register = !register),
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x4),
      Text(
        'Your profile starts private. Approve followers before they can see your care history.',
        style: T.small,
      ),
      const SectionBreak(),
      smallAction(
        'Explore the demo league',
        () => openSocial(context, const DemoLeagueScreen()),
      ),
    ],
  );
}
