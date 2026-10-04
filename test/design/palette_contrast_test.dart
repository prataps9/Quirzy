import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/shared/theme/app_palette.dart';

double _channel(double value) =>
    value <= 0.03928 ? value / 12.92 : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const minimum = 4.5;

  final palettes = {'dark': AppPalette.dark, 'light': AppPalette.light};

  for (final entry in palettes.entries) {
    final name = entry.key;
    final p = entry.value;

    group('$name palette', () {
      test('body text is readable on every surface', () {
        for (final background in [p.bg, p.surface, p.surfaceHigh]) {
          expect(contrast(p.text, background), greaterThanOrEqualTo(minimum));
        }
      });

      test('muted text is readable on every surface', () {
        for (final background in [p.bg, p.surface, p.surfaceHigh]) {
          expect(
            contrast(p.textMuted, background),
            greaterThanOrEqualTo(minimum),
            reason: 'textMuted on $background',
          );
        }
      });

      test('text on an accent fill is readable', () {
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(minimum));
      });

      test('the accent as text is readable on every surface', () {
        for (final background in [p.bg, p.surface, p.surfaceHigh]) {
          expect(
            contrast(p.accentText, background),
            greaterThanOrEqualTo(minimum),
            reason: 'accentText on $background',
          );
        }
      });

      test('status colours are readable as text on surfaces', () {
        final statuses = {
          'success': p.success,
          'danger': p.danger,
          'streak': p.streak,
          'like': p.like,
        };
        for (final status in statuses.entries) {
          for (final background in [p.bg, p.surface]) {
            expect(
              contrast(status.value, background),
              greaterThanOrEqualTo(minimum),
              reason: '${status.key} on $background',
            );
          }
        }
      });
    });
  }

  test('white text would not be readable on the lime accent', () {
    expect(contrast(Colors.white, AppPalette.dark.accent), lessThan(minimum));
  });
}
