import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/game.dart';

import 'app/shell.dart';
import 'features/tutorial/tutorial_screen.dart';
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
  final storage = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [gameStorageProvider.overrideWithValue(storage)], child: const CalmpostApp()));
}

class CalmpostApp extends StatelessWidget {
  const CalmpostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calmpost',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // On a wide browser window, show the app at phone size.
      builder: kIsWeb ? (context, child) => _PhoneFrame(child: child!) : null,
      home: const TutorialGate(child: AppShell()),
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
      color: C.sunk,
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
