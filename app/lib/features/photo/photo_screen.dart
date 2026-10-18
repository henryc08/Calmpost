import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/routes.dart';
import '../../data/api_repository.dart';
import '../../data/photo_input.dart';
import '../../domain/drop.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class PhotoScreen extends ConsumerStatefulWidget {
  const PhotoScreen({super.key, this.recovered});
  final Uint8List? recovered;
  @override
  ConsumerState<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends ConsumerState<PhotoScreen> {
  Uint8List? _jpeg;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _jpeg = widget.recovered;
  }

  Future<void> _pick(bool camera) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final generation = _generation;
    try {
      final bytes = await ref.read(photoInputProvider).pick(camera: camera);
      if (mounted && generation == _generation && bytes != null) setState(() => _jpeg = bytes);
    } on PlatformException {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Camera or photo access is unavailable. Check app permissions in Android Settings, or choose another photo.');
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Could not read that photo. Choose a JPEG or PNG under 20 MB, or take a new photo.');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _identify() async {
    if (_busy || _jpeg == null) return;
    final repo = ref.read(repositoryProvider);
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Recover an existing pending result before retrying an uncertain upload.
      // This also avoids starting a second review over an unconfirmed bin drop.
      final pending = await repo.pendingDrop();
      if (!mounted || generation != _generation) return;
      final drop = pending ?? Drop.fromCamera(await repo.submitPhoto(_jpeg!));
      if (!mounted || generation != _generation) return;
      setState(() => _busy = false);
      await Routes.review(context, drop);
      if (mounted && generation == _generation) setState(() => _jpeg = null);
    } on ApiException catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e.statusCode == 413
              ? 'The server could not accept that photo size. Choose a smaller photo.'
              : 'Could not submit the photo. Check your connection and paired bin, then retry.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Could not submit the photo. Check your connection, then retry.');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(repositoryProvider, (_, _) {
      _generation++;
      setState(() {
        _jpeg = null;
        _busy = false;
        _error = null;
      });
    });
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Check a photo',
        subtitle: 'Your phone camera, your confirmation',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: [
          if (ref.watch(needsBinProvider)) ...[
            Text('Connect a bin to this account before submitting a photo.', style: T.body),
            const SizedBox(height: S.x3),
            PillButton(label: 'Connect bin', onTap: () => Routes.connectBin(context)),
            const SectionBreak(),
          ],
          Text(
            'Take or choose a photo of the scraps. We resize it before sending it to the server for identification. Nothing counts as compost until you confirm what was actually added.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          Wrap(
            spacing: S.x3,
            runSpacing: S.x3,
            children: [
              PillButton(label: 'Take photo', icon: PhosphorIconsRegular.camera, onTap: _busy || ref.watch(needsBinProvider) ? null : () => _pick(true)),
              PillButton(label: 'Choose photo', icon: PhosphorIconsRegular.image, onTap: _busy || ref.watch(needsBinProvider) ? null : () => _pick(false)),
            ],
          ),
          if (_jpeg != null) ...[
            const SectionBreak(),
            Image.memory(
              _jpeg!,
              height: 250,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text('Photo preview unavailable', style: T.small),
            ),
            const SizedBox(height: S.x3),
            Text(
              'At most 1024 px · resized JPEG. Gemini can be wrong; the next screen lets you correct it. Any pending addition will be reviewed first.',
              style: T.small,
            ),
            const SizedBox(height: S.x4),
            PillButton(label: 'Identify and review', onTap: _busy || ref.watch(needsBinProvider) ? null : _identify),
          ],
          if (_busy) ...[
            const SizedBox(height: S.x4),
            const LinearProgressIndicator(color: C.forest, backgroundColor: C.sunk),
            const SizedBox(height: S.x2),
            Text('Preparing your photo or waiting for identification…', style: T.small),
          ],
          if (_error != null) ...[const SizedBox(height: S.x4), Text(_error!, style: T.body.copyWith(color: C.clay))],
        ],
      ),
    );
  }
}
