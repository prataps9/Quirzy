import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/feed_models.dart';

/// Read-aloud and answer sounds for the practice feed. Every call is
/// fire-and-forget: audio failing (no TTS engine, muted device) must never
/// break the feed.
class FeedAudio {
  FlutterTts? _tts;
  AudioPlayer? _player;
  bool _ttsReady = false;

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (!_ttsReady) {
      _ttsReady = true;
      await tts.setSpeechRate(0.5);
      await tts.awaitSpeakCompletion(false);
    }
    return tts;
  }

  /// What read-aloud says for [card].
  static String script(FeedCardState card) {
    final q = card.question;
    const labels = ['A', 'B', 'C', 'D', 'E', 'F'];
    switch (card.kind) {
      case FeedCardKind.question:
        final options = [
          for (var i = 0; i < q.options.length; i++) '${labels[i % labels.length]}. ${q.options[i]}.',
        ].join(' ');
        return '${q.questionText} $options';
      case FeedCardKind.trueFalse:
        return '${q.questionText} Is the answer: ${q.options[card.tfShownOption!]}? True or false?';
      case FeedCardKind.fact:
        return 'Remember this? ${q.questionText} The answer is ${q.options[q.correctIndex]}. ${q.explanation}';
      case FeedCardKind.flashcard:
        return card.flipped ? card.flashcard!.back : card.flashcard!.front;
    }
  }

  Future<void> speak(FeedCardState card) async {
    try {
      final tts = await _engine();
      await tts.stop();
      await tts.speak(script(card));
    } catch (e) {
      debugPrint('FeedAudio: speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (e) {
      debugPrint('FeedAudio: stop failed: $e');
    }
  }

  Future<void> playAnswer({required bool correct}) async {
    try {
      final player = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(AssetSource(correct ? 'sounds/correct.wav' : 'sounds/wrong.wav'), volume: 0.6);
    } catch (e) {
      debugPrint('FeedAudio: sound failed: $e');
    }
  }

  void dispose() {
    _tts?.stop();
    _player?.dispose();
  }
}

final feedAudioProvider = Provider<FeedAudio>((ref) {
  final audio = FeedAudio();
  ref.onDispose(audio.dispose);
  return audio;
});
