import 'dart:async';
import 'package:calmpost/data/mock_repository.dart';
import 'package:calmpost/domain/models.dart';
import 'package:calmpost/features/trunc/trunc_screen.dart';
import 'package:calmpost/state/providers.dart';
import 'package:calmpost/state/trunc_chat.dart';
import 'package:calmpost/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const answer = TruncReply(reply: 'Try dry browns.', model: 'rules-fallback', onTopic: true, usedReadings: false, context: TruncContext());

class ChatRepo extends MockRepository {
  ChatRepo() : super(Scenario.healthy);
  final calls = <(String, List<TruncTurn>, bool)>[];
  Completer<TruncReply>? pending;
  bool fail = false;
  @override
  Future<TruncReply> askTrunc(String message, {List<TruncTurn> history = const [], bool includePhotos = true}) async {
    calls.add((message, history, includePhotos));
    if (fail) throw Exception('network');
    return pending == null ? answer : pending!.future;
  }
}

void main() {
  test('chat bounds history, excludes current question, retries once and isolates account changes', () async {
    final repo = ChatRepo();
    final c = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final chat = c.read(truncChatProvider.notifier);
    for (var i = 0; i < 12; i++) {
      await chat.send('Question $i');
    }
    expect(repo.calls.last.$2.length, 20);
    expect(repo.calls.last.$2.first.text, 'Question 1');
    expect(repo.calls.last.$2.last.text, answer.reply);
    expect(repo.calls.last.$3, false);
    chat.includePhotos(true);
    repo.fail = true;
    await chat.send('Failed question');
    expect(c.read(truncChatProvider).failed, true);
    repo.fail = false;
    await chat.retry();
    expect(c.read(truncChatProvider).exchanges.length, 13);
    expect(repo.calls.last.$2.any((t) => t.text == 'Failed question'), false);
    expect(repo.calls.last.$3, true);
    repo.pending = Completer();
    final sending = chat.send('Old account');
    final other = ChatRepo();
    c.updateOverrides([repositoryProvider.overrideWithValue(other)]);
    await c.pump();
    expect(c.read(truncChatProvider).exchanges, isEmpty);
    repo.pending!.complete(answer);
    await sending;
    expect(c.read(truncChatProvider).exchanges, isEmpty);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('chat waiting, fallback context and retry at $width', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = ChatRepo()..pending = Completer();
      await t.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo), binProvider.overrideWith((ref) => const Stream.empty())],
          child: MaterialApp(theme: buildTheme(), home: const TruncScreen()),
        ),
      );
      await t.enterText(find.byKey(const ValueKey('trunc-input')), 'What are browns?');
      await t.pump();
      await t.tap(find.text('Send'));
      await t.pump();
      expect(find.text('Thinking…'), findsOneWidget);
      repo.pending!.complete(answer);
      await t.pumpAndSettle();
      expect(find.text(answer.reply), findsOneWidget);
      expect(find.textContaining('General guidance'), findsOneWidget);
      expect(find.text('Retry question'), findsNothing);
      repo.pending = null;
      repo.fail = true;
      await t.enterText(find.byKey(const ValueKey('trunc-input')), 'Why does it smell?');
      await t.pump();
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      expect(find.text('Retry question'), findsOneWidget);
      repo.fail = false;
      await t.ensureVisible(find.text('Retry question'));
      await t.tap(find.text('Retry question'));
      await t.pumpAndSettle();
      expect(find.text('Retry question'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
