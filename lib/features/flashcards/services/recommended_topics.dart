/// Suggested flashcard topics per exam. Tapping one generates a real set.
const Map<String, List<String>> recommendedTopicsByExam = {
  'jee': [
    'Kinematics',
    'Laws of Motion',
    'Thermodynamics',
    'Chemical Bonding',
    'Organic Reaction Mechanisms',
    'Limits and Derivatives',
  ],
  'neet': [
    'Cell Structure and Function',
    'Human Physiology',
    'Genetics and Evolution',
    'Plant Physiology',
    'Chemical Bonding',
    'Laws of Motion',
  ],
  'cat': [
    'Percentages and Profit & Loss',
    'Time, Speed and Distance',
    'Ratio and Proportion',
    'Reading Comprehension Strategies',
    'Para Jumbles',
    'Data Interpretation',
  ],
  'mba': [
    'Percentages and Profit & Loss',
    'Time, Speed and Distance',
    'Ratio and Proportion',
    'Reading Comprehension Strategies',
    'Para Jumbles',
    'Data Interpretation',
  ],
  'cuet': [
    'English Grammar Essentials',
    'Quantitative Reasoning',
    'Logical Reasoning',
    'Indian Polity Basics',
    'Basics of Accountancy',
    'Business Studies Concepts',
  ],
  '10th': [
    'Chemical Reactions and Equations',
    'Light: Reflection and Refraction',
    'Life Processes',
    'Quadratic Equations',
    'Introduction to Trigonometry',
    'Nationalism in India',
  ],
  '12th': [
    'Electrostatics',
    'Electrochemistry',
    'Molecular Basis of Inheritance',
    'Integrals',
    'Probability',
    'Introductory Macroeconomics',
  ],
  'ielts': [
    'Academic Vocabulary',
    'Linking Words for Writing',
    'Describing Graphs (Task 1)',
    'Common Speaking Topics',
    'English Collocations',
    'Listening Spelling Traps',
  ],
  'gre': [
    'High-Frequency GRE Vocabulary',
    'Text Completion Strategies',
    'Number Properties',
    'Geometry Formulas',
    'Data Analysis and Statistics',
    'Analytical Writing: Issue Essay',
  ],
  'gmat': [
    'Critical Reasoning Argument Types',
    'Data Sufficiency',
    'Number Properties',
    'Word Problems',
    'Reading Comprehension Strategies',
    'Probability and Combinatorics',
  ],
  'upsc': [
    'Indian Constitution',
    'Modern Indian History',
    'Indian Geography',
    'Indian Economy Basics',
    'Environment and Ecology',
    'Art and Culture of India',
  ],
  'ssc': [
    'Number Series',
    'Simplification',
    'Synonyms and Antonyms',
    'Idioms and Phrases',
    'Indian Polity',
    'General Science',
  ],
  'gate': [
    'Engineering Mathematics',
    'Linear Algebra',
    'Probability and Statistics',
    'Data Structures',
    'Digital Logic',
    'General Aptitude',
  ],
};

/// Used when no exam is selected or the exam has no list of its own.
const List<String> genericRecommendedTopics = [
  'Periodic Table',
  'Photosynthesis',
  'Human Body Systems',
  'World War II',
  'Basic Statistics',
  'Common English Idioms',
];

List<String> recommendedTopicsFor(String? exam) {
  if (exam == null) return genericRecommendedTopics;
  return recommendedTopicsByExam[exam.toLowerCase()] ??
      genericRecommendedTopics;
}

/// Short label for an exam id, e.g. 'jee' -> 'JEE', '10th' -> '10th Board'.
String examLabel(String exam) {
  switch (exam.toLowerCase()) {
    case '10th':
      return '10th Board';
    case '12th':
      return '12th Board';
    default:
      return exam.toUpperCase();
  }
}
