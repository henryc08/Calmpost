import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/api_repository.dart';
import '../../domain/calibration.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/brand.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../ui/type.dart';

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});
  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  final _dry = TextEditingController(), _wet = TextEditingController();
  int _probe = 1, _generation = 0;
  bool _busy = false, _backfill = false;
  String? _error;
  CalibrationResult? _saved;

  @override
  void dispose() {
    _dry.dispose();
    _wet.dispose();
    super.dispose();
  }

  void _select(int probe) {
    if (_busy) return;
    setState(() {
      _probe = probe;
      _dry.clear();
      _wet.clear();
      _error = null;
      _saved = null;
      _backfill = false;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final dry = int.tryParse(_dry.text), wet = int.tryParse(_wet.text);
    final error = calibrationError(_probe, dry, wet);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    FocusScope.of(context).unfocus();
    final repo = ref.read(repositoryProvider);
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
      _saved = null;
    });
    try {
      final result = await repo.calibrateProbe(probe: _probe, dry: dry!, wet: wet!, backfill: _backfill);
      if (!mounted || generation != _generation) return;
      ref.invalidate(binProvider);
      ref.invalidate(trendProvider);
      setState(() => _saved = result);
    } on ApiException catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = switch (e.statusCode) {
            401 || 403 => 'Only the account paired to this bin can calibrate it. Sign in and check your bin connection.',
            422 => 'The server rejected these counts. Check both raw references and try again.',
            _ => 'Could not save calibration. Check your connection and paired bin, then retry.',
          },
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Could not save calibration. Your inputs are kept; check the connection and retry.');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController controller, int? raw, bool usable) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: ValueKey(label),
        controller: controller,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        maxLength: 5,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: T.body,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Raw ADC count, not %',
          filled: true,
          fillColor: C.surface,
          border: const OutlineInputBorder(borderSide: BorderSide(color: C.line)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: C.forest)),
        ),
        onChanged: (_) => setState(() {
          _saved = null;
          _error = null;
        }),
      ),
      if (usable && raw != null)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  controller.text = '$raw';
                  _saved = null;
                  _error = null;
                }),
          child: Text('Use current count for $label', style: T.small),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(repositoryProvider, (_, _) {
      _generation++;
      setState(() {
        _busy = false;
        _probe = 1;
        _dry.clear();
        _wet.clear();
        _error = null;
        _saved = null;
        _backfill = false;
      });
    });
    final repo = ref.watch(repositoryProvider);
    final live = ref.watch(binProvider);
    final snapshot = live.valueOrNull;
    final raw = _probe == 1 ? snapshot?.topMoistureRaw : snapshot?.bottomMoistureRaw;
    final usable = !live.hasError && snapshot != null && !snapshot.readingsStale;
    final calibrated = snapshot?.calibrated(_probe == 1 ? Zone.top : Zone.bottom);
    return Scaffold(
      backgroundColor: C.paper,
      body: BrandPage(
        title: 'Calibrate probes',
        subtitle: 'Two sensors. Two separate references.',
        trailing: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: C.onBrand),
        ),
        children: [
          PaperSegments<int>(values: const [1, 2], selected: _probe, label: (p) => p == 1 ? 'Probe 1 · Top' : 'Probe 2 · Bottom', onChanged: _select),
          const SizedBox(height: S.x4),
          Text(
            !repo.serverGame
                ? 'Demo mode: calibration is simulated in this session; no hardware is changed.'
                : 'This changes only probe $_probe. The other probe keeps its own calibration.',
            style: T.body,
          ),
          const SizedBox(height: S.x3),
          Text(
            calibrated == null
                ? 'Calibration status unavailable until the bin reports.'
                : calibrated
                ? 'This probe has a calibration.'
                : 'This probe is uncalibrated; its percentage is approximate.',
            style: T.small,
          ),
          Text(usable && raw != null ? 'Current raw count: $raw' : 'No fresh raw count available. You can enter recorded references below.', style: T.small),
          const SectionBreak(),
          const SectionLabel('RECORD TWO REFERENCES'),
          const SizedBox(height: S.x3),
          Text(
            '1. Follow your probe’s hardware instructions to record a stable dry reference. Enter its raw count below.\n\n2. Record a stable wet reference from the same probe. Keep the board and electronics dry; do not immerse them.\n\nUse raw counts from the live reading or serial output, not moisture percentages. Dry is usually the higher count; the two values must differ.',
            style: T.body,
          ),
          const SizedBox(height: S.x4),
          _field('Dry reference', _dry, raw, usable),
          const SizedBox(height: S.x3),
          _field('Wet reference', _wet, raw, usable),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: C.forest,
            value: _backfill,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _backfill = v ?? false;
                    _saved = null;
                  }),
            title: Text('Recalculate this probe’s stored readings', style: T.label),
            subtitle: Text(
              'Optional: changes historical percentages. Charts may take time to refresh. Leave off to apply to new readings only.',
              style: T.small,
            ),
          ),
          const SizedBox(height: S.x4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x3),
              child: Text(_error!, style: T.body.copyWith(color: C.clay)),
            ),
          PillButton(label: _busy ? 'Saving calibration…' : 'Save probe $_probe calibration', onTap: _busy ? null : _save),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: S.x3),
              child: LinearProgressIndicator(color: C.forest, backgroundColor: C.sunk),
            ),
          if (_saved case final result?) ...[
            const SectionBreak(),
            Text('Probe ${result.probe} calibration saved', style: T.heading),
            Text(
              'Dry ${result.dry} · wet ${result.wet}. ${result.readingsRecomputed} stored readings recalculated. The other probe was not changed.',
              style: T.body,
            ),
            Text(
              repo.serverGame ? 'Return the probe to the bin and wait for the next sensor reading.' : 'Demo sensor values remain simulated.',
              style: T.small,
            ),
          ],
        ],
      ),
    );
  }
}
