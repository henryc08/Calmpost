import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'providers.dart';

class TruncExchange {
  const TruncExchange(this.question, [this.answer]);
  final String question;
  final TruncReply? answer;
}

class TruncChat {
  const TruncChat({this.exchanges = const [], this.waiting = false, this.failed = false, this.includePhotos = false});
  final List<TruncExchange> exchanges;
  final bool waiting, failed, includePhotos;
}

final truncChatProvider = NotifierProvider<TruncChatController, TruncChat>(TruncChatController.new);

class TruncChatController extends Notifier<TruncChat> {
  int _generation = 0;

  @override
  TruncChat build() {
    // The repository changes on sign-out, account/bin changes and mock switches.
    ref.watch(repositoryProvider);
    _generation++;
    ref.onDispose(() => _generation++);
    return const TruncChat();
  }

  void clear() {
    _generation++;
    state = const TruncChat();
  }

  void includePhotos(bool value) {
    if (state.waiting) return;
    state = TruncChat(exchanges: state.exchanges, failed: state.failed, includePhotos: value);
  }

  Future<void> send(String text, {bool retry = false}) async {
    final question = text.trim();
    if (state.waiting || question.isEmpty || question.length > 1000 || (state.failed && !retry)) return;
    final previous = retry ? state.exchanges.where((e) => e.answer != null).toList() : state.exchanges;
    final history = previous
        .skip(previous.length > 10 ? previous.length - 10 : 0)
        .expand(
          (e) => [
            TruncTurn(role: TruncRole.user, text: e.question),
            TruncTurn(role: TruncRole.assistant, text: e.answer!.reply.length > 2000 ? e.answer!.reply.substring(0, 2000) : e.answer!.reply),
          ],
        )
        .toList();
    final repo = ref.read(repositoryProvider);
    final generation = _generation;
    final photos = state.includePhotos;
    final exchanges = [...previous, TruncExchange(question)];
    state = TruncChat(exchanges: exchanges, waiting: true, includePhotos: photos);
    try {
      final answer = await repo.askTrunc(question, history: history, includePhotos: photos);
      if (generation != _generation) return;
      state = TruncChat(exchanges: [...previous, TruncExchange(question, answer)], includePhotos: photos);
    } catch (_) {
      if (generation != _generation) return;
      state = TruncChat(exchanges: exchanges, failed: true, includePhotos: photos);
    }
  }

  Future<void> retry() => state.failed ? send(state.exchanges.last.question, retry: true) : Future.value();
}
