import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/social_repository.dart';
import '../../state/social.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class BinConnectionScreen extends ConsumerStatefulWidget {
  const BinConnectionScreen({super.key});
  @override
  ConsumerState<BinConnectionScreen> createState() => _BinConnectionScreenState();
}

class _BinConnectionScreenState extends ConsumerState<BinConnectionScreen> {
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _run({bool pair = false}) async {
    if (_busy) return;
    if (pair && _token.text.trim().isEmpty) {
      setState(() => _error = 'Enter the device token from the bin setup.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = ref.read(socialSessionProvider.notifier);
      if (pair) {
        await account.pair(_token.text.trim());
      } else {
        await account.refreshBin();
      }
      if (!mounted) return;
      _token.clear();
      if (ref.read(socialSessionProvider).valueOrNull?.binId != null) {
        Navigator.pop(context);
      } else {
        setState(() => _error = 'No bin is linked to this account yet. Connect it with its device token below.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is SocialFailure ? e.message : 'Could not connect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(socialSessionProvider).valueOrNull;
    ref.listen(socialSessionProvider.select((s) => s.valueOrNull?.userId), (_, _) => _token.clear());
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Your bin',
        subtitle: 'Connect readings, graphs and camera',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: [
          if (session == null)
            Text('Sign in to your account from Social, then connect your bin here.', style: T.body)
          else ...[
            Text(session.binId == null ? 'Your account has no connected bin' : 'Connected to ${session.binId}', style: T.heading),
            const SizedBox(height: S.x3),
            Text('Signing in does not automatically claim the demo bin. Adding a friend does not connect or disconnect hardware.', style: T.body),
            const SizedBox(height: S.x4),
            PillButton(label: 'Check saved connection', onTap: _busy ? null : () => _run()),
            if (session.binId == null) ...[
              const SectionBreak(),
              const SectionLabel('CONNECT THIS ACCOUNT'),
              const SizedBox(height: S.x3),
              Text(
                'Use the device token supplied during bin setup (DEVICE_TOKEN on the laptop running the bridge). This is not a friend invite code. A bin already owned by another account cannot be claimed here.',
                style: T.body,
              ),
              const SizedBox(height: S.x4),
              TextField(
                controller: _token,
                obscureText: true,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autocorrect: false,
                maxLength: 200,
                style: T.body,
                decoration: InputDecoration(
                  labelText: 'Device token',
                  labelStyle: T.small,
                  filled: true,
                  fillColor: C.surface,
                  contentPadding: const EdgeInsets.all(S.x4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.chip),
                    borderSide: const BorderSide(color: C.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.chip),
                    borderSide: const BorderSide(color: C.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.chip),
                    borderSide: const BorderSide(color: C.forest),
                  ),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: S.x3),
              PillButton(label: 'Connect bin', onTap: _busy ? null : () => _run(pair: true)),
            ],
            if (_busy) ...[const SizedBox(height: S.x4), const LinearProgressIndicator(color: C.forest, backgroundColor: C.sunk)],
            if (_error != null) ...[const SizedBox(height: S.x4), Text(_error!, style: T.body.copyWith(color: C.clay))],
          ],
        ],
      ),
    );
  }
}
