import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/shared/widgets/app_widgets.dart';
import 'package:quirzy/shared/widgets/motion.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduced), child: c!),
  home: Scaffold(body: Center(child: child)),
);

double _opacityOf(WidgetTester tester, Finder child) =>
    tester.widget<Opacity>(find.ancestor(of: child, matching: find.byType(Opacity)).first).opacity;

void main() {
  group('CountUp', () {
    testWidgets('rolls up and lands exactly on the value', (tester) async {
      await tester.pumpWidget(_app(const CountUp(value: 42)));
      expect(find.text('0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('42'), findsNothing, reason: 'still rolling');
      await tester.pump(CountUp.duration);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('screen readers hear the real number while it rolls', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(CountUp(value: 7, format: (v) => '$v / 10')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('7 / 10'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('shows the value at once with animations off', (tester) async {
      await tester.pumpWidget(_app(const CountUp(value: 42), reduced: true));
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('Stagger', () {
    testWidgets('items arrive one after another', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              Stagger(index: 0, child: Text('first')),
              Stagger(index: 3, child: Text('fourth')),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacityOf(tester, find.text('first')), greaterThan(0));
      expect(_opacityOf(tester, find.text('fourth')), 0, reason: 'its turn has not come yet');
      await tester.pump(const Duration(milliseconds: 200)); // its turn starts
      await tester.pump(const Duration(seconds: 1));
      expect(_opacityOf(tester, find.text('first')), 1);
      expect(_opacityOf(tester, find.text('fourth')), 1);
    });

    testWidgets('items far down the list just appear', (tester) async {
      await tester.pumpWidget(_app(const Stagger(index: 20, child: Text('late'))));
      expect(_opacityOf(tester, find.text('late')), 1);
    });

    testWidgets('no animation with animations off', (tester) async {
      await tester.pumpWidget(_app(const Stagger(index: 2, child: Text('x')), reduced: true));
      expect(find.ancestor(of: find.text('x'), matching: find.byType(Opacity)), findsNothing);
    });
  });

  group('PressScale', () {
    testWidgets('a button shrinks while pressed and springs back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(AppButton(label: 'Go', onPressed: () => taps++, expanded: false)));
      double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      expect(scale(), 1);

      final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(scale(), lessThan(1));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(scale(), 1);
      expect(taps, 1);
    });

    testWidgets('a disabled button does not react', (tester) async {
      await tester.pumpWidget(_app(const AppButton(label: 'Go', onPressed: null, expanded: false)));
      expect(find.byType(AnimatedScale), findsNothing);
    });
  });

  group('SkeletonList', () {
    testWidgets('pulses while loading, and holds still with animations off', (tester) async {
      await tester.pumpWidget(_app(const SizedBox(height: 400, child: SkeletonList(count: 2))));
      double opacity() => tester
          .widget<FadeTransition>(find.descendant(of: find.byType(SkeletonList), matching: find.byType(FadeTransition)))
          .opacity
          .value;
      final a = opacity();
      await tester.pump(const Duration(milliseconds: 450));
      expect(opacity(), isNot(a));

      await tester.pumpWidget(_app(const SizedBox(height: 400, child: SkeletonList(count: 2)), reduced: true));
      await tester.pump(const Duration(milliseconds: 450));
      expect(opacity(), 1);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
  });

  group('GrowBar', () {
    testWidgets('fills from empty to its value', (tester) async {
      await tester.pumpWidget(_app(const SizedBox(width: 200, child: GrowBar(value: 0.6))));
      double value() => tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;
      expect(value(), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(value(), closeTo(0.6, 0.001));
    });
  });
}
