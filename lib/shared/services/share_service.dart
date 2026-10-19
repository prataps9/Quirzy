import 'package:share_plus/share_plus.dart';

/// Builds the text Quirzy shares to other apps (the image cards live in
/// ShareCardService).
class ShareService {
  /// Shares a practice streak.
  static Future<void> shareStreak({required int days}) async {
    final text =
        '''
🔥 $days-day practice streak on Quirzy!

Can you beat it? #Quirzy #Streak
''';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'My $days-day Quirzy streak'),
    );
  }

  /// Shares hitting the daily question goal.
  static Future<void> shareDailyGoal({required int questions}) async {
    final text =
        '''
🎯 $questions questions done today on Quirzy!

Daily goal smashed. #Quirzy
''';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'I hit my Quirzy goal today'),
    );
  }

  /// Shares a practice session's numbers.
  static Future<void> shareSession({required int answered, required int accuracy, required int xp}) async {
    final text =
        '''
⚡ Just practised $answered questions on Quirzy — $accuracy% right, +$xp XP.

Your turn? #Quirzy
''';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'My Quirzy practice session'),
    );
  }

  /// Shares a practice question as a challenge, without revealing the
  /// answer.
  static Future<void> shareQuestion({
    required String topic,
    required String questionText,
    required List<String> options,
  }) async {
    const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    final optionLines = [
      for (var i = 0; i < options.length; i++)
        '${letters[i % letters.length]}) ${options[i]}',
    ].join('\n');
    final text =
        '''
🧠 Can you answer this? ($topic)

$questionText

$optionLines

Practice more on Quirzy #Quirzy
''';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'A $topic question for you'),
    );
  }
}
