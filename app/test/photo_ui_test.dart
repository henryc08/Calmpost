import 'dart:typed_data';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/data/photo_input.dart';
import 'package:calmpost/domain/drop.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/photo/photo_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class FakePicker extends PhotoInput {
  Uint8List? bytes;
  bool fail = false;
  @override
  Future<Uint8List?> pick({required bool camera}) async {
    if (fail) throw Exception('unavailable');
    return bytes;
  }
}

class PhotoRepo extends MockRepository {
  PhotoRepo() : super(Scenario.healthy);
  int uploads = 0;
  int arms = 0;
  @override
  Future<CameraDrop> submitPhoto(Uint8List jpeg) {
    uploads++;
    return super.submitPhoto(jpeg);
  }

  @override
  Future<DropSession> startDropSession() {
    arms++;
    return super.startDropSession();
  }

  @override
  Stream<BinSnapshot> watchBin() => Stream.fromFuture(super.watchBin().first);
}

void main() {
  test('photos become bounded JPEGs, reject invalid input and preserve aspect ratio', () {
    final bytes = preparePhoto(img.encodePng(img.Image(width: 2400, height: 1200)));
    final decoded = img.decodeJpg(bytes)!;
    expect((decoded.width, decoded.height), (1024, 512));
    expect(bytes.length, lessThan(1400000));
    expect(() => preparePhoto(Uint8List(0)), throwsFormatException);
    expect(() => preparePhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('failed identification converts into the existing manual-review tier', () async {
    final repo = PhotoRepo();
    final drop = Drop.fromCamera(await repo.submitPhoto(Uint8List(0)));
    expect(drop.fromPhoto, true);
    expect(drop.geminiOk, false);
    expect(tierOf(drop, {}), DropTier.unclear);
    expect((await repo.pendingDrop())!.id, drop.id);
    await repo.dismissReviewedDrop(drop);
    expect(await repo.pendingDrop(), isNull);
  });

  testWidgets('cancel, pick, review and confirm a photo without arming webcam', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final picker = FakePicker();
    final repo = PhotoRepo();
    await t.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo), photoInputProvider.overrideWithValue(picker)],
        child: MaterialApp(theme: buildTheme(), home: const PhotoScreen()),
      ),
    );
    await t.tap(find.text('Choose photo'));
    await t.pumpAndSettle();
    expect(find.text('Identify and review'), findsNothing);
    picker.fail = true;
    await t.tap(find.text('Take photo'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not read that photo'), findsOneWidget);
    picker.fail = false;
    picker.bytes = preparePhoto(img.encodePng(img.Image(width: 20, height: 20)));
    await t.tap(find.text('Choose photo'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Identify and review'));
    await t.pumpAndSettle();
    await t.tap(find.text('Identify and review'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('PHOTO REVIEW'), findsOneWidget);
    expect(repo.arms, 0);
    expect(repo.uploads, 1);
    await t.ensureVisible(find.text("Yes, that's right"));
    await t.pumpAndSettle();
    await t.tap(find.text("Yes, that's right"));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect((await repo.inventory()).items, hasLength(1));
    expect(await repo.pendingDrop(), isNull);
    expect(t.takeException(), isNull);
  });
}
