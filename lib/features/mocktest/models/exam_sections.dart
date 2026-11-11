import '../../content/services/exam_bank_service.dart';

/// One section of a real exam (for example CAT's VARC), as the topics a
/// section test is built from.
class ExamSection {
  final String name;
  final List<String> topics;

  const ExamSection(this.name, this.topics);

  /// The section's topics the learner has questions in.
  List<String> available(Map<String, int> poolCounts) => [
    for (final t in topics)
      if ((poolCounts[t] ?? 0) > 0) t,
  ];

  /// How many questions a test of this section could draw on.
  int questionCount(Map<String, int> poolCounts) => available(poolCounts).fold(0, (sum, t) => sum + poolCounts[t]!);
}

/// The sections of the exams with bundled practice, used to start a
/// section test in one tap.
class ExamSections {
  static const _verbal = ['Vocabulary', 'Grammar & Usage', 'Reading Comprehension'];

  static const _byExam = <String, List<ExamSection>>{
    'sat': [
      ExamSection('Reading & Writing', _verbal),
      ExamSection('Math', ['Algebra', 'Arithmetic', 'Geometry', 'Data Interpretation']),
    ],
    'gmat': [
      ExamSection('Quantitative', ['Arithmetic', 'Algebra', 'Number Systems', 'Geometry']),
      ExamSection('Verbal', ['Grammar & Usage', 'Reading Comprehension', 'Critical Reasoning']),
      ExamSection('Data Insights', ['Data Sufficiency', 'Data Interpretation']),
    ],
    'cat': [
      ExamSection('VARC', ['Reading Comprehension', 'Grammar & Usage', 'Vocabulary']),
      ExamSection('DILR', ['Data Interpretation', 'Logical Reasoning']),
      ExamSection('QA', ['Arithmetic', 'Algebra', 'Number Systems', 'Geometry']),
    ],
    'gre': [
      ExamSection('Verbal', _verbal),
      ExamSection('Quant', ['Arithmetic', 'Algebra', 'Data Interpretation']),
    ],
  };

  /// [exam]'s sections (MBA shares CAT's), or none.
  static List<ExamSection> forExam(String? exam) {
    if (exam == null || exam.isEmpty) return const [];
    return _byExam[ExamBankService.examKey(exam)] ?? const [];
  }

  /// The sections that have questions in [poolCounts].
  static List<ExamSection> withQuestions(String? exam, Map<String, int> poolCounts) => [
    for (final s in forExam(exam))
      if (s.questionCount(poolCounts) > 0) s,
  ];
}
