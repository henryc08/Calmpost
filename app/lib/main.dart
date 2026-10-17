import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'app/dev_hooks.dart';
import 'app/shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'ui/sfx.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: C.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  Sfx.preload();
  var onboarded = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    onboarded = prefs.getBool(_onboardedKey) ?? false;
  } catch (_) {}
  if (kIsWeb) onboarded = Uri.base.queryParameters['onboarding'] != '1';
  if (kIsWeb && Uri.base.queryParameters['icon'] == '1') return runApp(const IconArt());
  runApp(ProviderScope(child: CalmpostApp(onboarded: onboarded)));
}

const _onboardedKey = 'onboarded';

class CalmpostApp extends StatefulWidget {
  const CalmpostApp({super.key, required this.onboarded});
  final bool onboarded;

  @override
  State<CalmpostApp> createState() => _CalmpostAppState();
}

class _CalmpostAppState extends State<CalmpostApp> {
  late bool _onboarded = widget.onboarded;

  Future<void> _finishOnboarding() async {
    setState(() => _onboarded = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardedKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calmpost',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // On the web preview, show the app at phone size so judges see what Android sees.
      builder: kIsWeb ? (context, child) => _PhoneFrame(child: child!) : null,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _onboarded ? const AppShell() : OnboardingScreen(onDone: _finishOnboarding),
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= 500) return child;
    final size = Size(412, mq.size.height);
    return ColoredBox(
      color: C.bgDeep,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: mq.copyWith(size: size),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
