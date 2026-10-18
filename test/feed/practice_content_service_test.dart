import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/features/feed/services/practice_content_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('questions that cannot be answered correctly are left out of the pool', () async {
    Map<String, dynamic> q(String id, {Object? correct = 1, List<String> options = const ['A', 'B', 'C']}) =>
        {'id': id, 'questionText': 'Question $id', 'options': options, 'correctIndex': correct};

    SharedPreferences.setMockInitialValues({
      PracticeContentKeys.topicsStore: jsonEncode({
        'topics': {
          'Physics': {
            'questions': [
              q('ok'),
              q('string-index', correct: '2'),
              q('out-of-range', correct: 7),
              q('negative', correct: -1),
              q('one-option', options: ['Only']),
              {'id': 'no-text', 'questionText': '  ', 'options': ['A', 'B'], 'correctIndex': 0},
            ],
            'lastUpdated': '2026-10-01T00:00:00.000',
          },
        },
        'downloaded': <String>[],
      }),
    });

    final pool = await PracticeContentService.instance.getQuestionPool();
    expect(pool.map((q) => q.id), ['ok', 'string-index']);
    expect(pool.last.correctIndex, 2);
  });
}
