import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/services.dart';

/// Provider for [ContentService] singleton
final contentServiceProvider = Provider<ContentService>((ref) {
  return ContentService();
});

final studyQuizServiceProvider = Provider<StudyQuizService>((ref) => StudyQuizService());
final studyMaterialServiceProvider = Provider<StudyMaterialService>((ref) => StudyMaterialService());

final studyMaterialHistoryProvider = FutureProvider<List<StudyMaterial>>((ref) async {
  return ref.read(studyMaterialServiceProvider).getStudyHistory();
});
