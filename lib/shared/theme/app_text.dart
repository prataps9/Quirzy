import 'package:flutter/material.dart';

/// Named text roles on top of the Material type scale, for the few places
/// that need a size the scale doesn't have. Screens use these instead of
/// writing `fontSize:` themselves, so every size lives in the theme.
extension AppTextRoles on TextTheme {
  /// A question on a feed card — readable at arm's length while scrolling.
  TextStyle get question => titleMedium!.copyWith(fontSize: 19, height: 1.4);

  /// An answer option.
  TextStyle get option => bodyLarge!.copyWith(fontSize: 15);

  /// Secondary lines inside cards (captions, explanation peeks).
  TextStyle get caption => bodyMedium!.copyWith(fontSize: 13);

  /// Tiny labels: chart axes, badges, the number inside the goal ring.
  TextStyle get micro => labelSmall!.copyWith(fontSize: 10, fontWeight: FontWeight.w800);

  /// The Quirzy wordmark on the welcome screen.
  TextStyle get wordmark => displayLarge!.copyWith(fontSize: 44);

  /// The hero number on a shared image card.
  TextStyle get shareHero => displayLarge!.copyWith(fontSize: 88, height: 1);

  /// A question on a shared image card, smaller when it is long.
  TextStyle shareQuestion({required bool long}) =>
      titleLarge!.copyWith(fontSize: long ? 17 : 20, height: 1.35);
}
