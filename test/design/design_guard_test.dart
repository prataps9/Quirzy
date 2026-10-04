import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the old purple / gradient / glass look from creeping back, and
/// keeps colours flowing through the palette instead of ad-hoc literals.
void main() {
  final libDir = Directory('lib');
  final sources = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('/l10n/'))
      .toList();

  Iterable<String> offenders(RegExp pattern, {Set<String> allow = const {}}) sync* {
    for (final file in sources) {
      if (allow.any(file.path.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) yield '${file.path}:${i + 1}: ${lines[i].trim()}';
      }
    }
  }

  test('the app has source files to scan', () {
    expect(sources.length, greaterThan(50));
  });

  test('no old purple palette values', () {
    final purple = RegExp(
      r'0xFF(5B13EC|6200EA|7C4DFF|9333EA|8B5CF6|A78BFA|7C3AED|6366F1|EFE9FD|664C9A|2D2540|1E1730|1E1B4B|5015E9|F5F3FF|A855F7|C084FC)',
      caseSensitive: false,
    );
    expect(offenders(purple), isEmpty);
  });

  test('no gradients, backdrop blur or glass', () {
    final decoration = RegExp(r'LinearGradient|RadialGradient|SweepGradient|BackdropFilter|ImageFilter');
    expect(offenders(decoration), isEmpty);
  });

  test('colours come from the palette, not literals', () {
    final literal = RegExp(r'Color\(\s*0x[0-9A-Fa-f]{8}\s*\)');
    expect(offenders(literal, allow: {'shared/theme/app_palette.dart'}), isEmpty);
  });

  test('no hard-coded dark or light page backgrounds', () {
    final backgrounds = RegExp(r'0xFF(0F0F0F|1A1A1A|F9F8FC|171717|1E293B|0F172A|F8FAFC|120D1B|120E1A|1E1E2E)', caseSensitive: false);
    expect(offenders(backgrounds), isEmpty);
  });

  test('white is never drawn on the accent fill', () {
    // `accent` fills must carry `onAccent`; flag Colors.white on the same
    // line as an accent fill.
    final whiteOnAccent = RegExp(r'p\.accent\b(?!Text|Soft).*Colors\.white|Colors\.white.*p\.accent\b(?!Text|Soft)');
    expect(offenders(whiteOnAccent), isEmpty);
  });

  test('no deprecated withOpacity', () {
    expect(offenders(RegExp(r'\.withOpacity\(')), isEmpty);
  });
}
