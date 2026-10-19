import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quirzy/shared/theme/app_theme.dart';
import 'package:quirzy/shared/utils/user_messages.dart';
import 'package:quirzy/shared/widgets/generation_loading.dart';

void main() {
  group('friendlyError', () {
    test('never shows raw exception text', () {
      final errors = <Object>[
        Exception('Failed to generate: Appwrite 500 internal'),
        StateError('bad state'),
        const FormatException('Unexpected character'),
        AppwriteException('Server down', 503),
        AppwriteException('Rate limit', 429),
        AppwriteException('Unauthorized', 401),
        TimeoutException('slow'),
        Exception('SocketException: Failed host lookup: cloud.appwrite.io'),
      ];
      for (final e in errors) {
        final message = friendlyError(e);
        expect(message, isNot(contains('Exception')), reason: '$e');
        expect(message, isNot(contains('Appwrite')), reason: '$e');
        expect(message.endsWith('.'), isTrue, reason: message);
      }
    });

    test('maps the common cases to specific, actionable copy', () {
      expect(friendlyError(TimeoutException('x')), contains('took too long'));
      expect(friendlyError(Exception('SocketException: Failed host lookup')), contains('offline'));
      expect(friendlyError(AppwriteException('x', 429)), contains('Too many requests'));
      expect(friendlyError(AppwriteException('x', 401)), contains('sign in'));
      expect(friendlyError(const UserFacingException('No questions came back.')), 'No questions came back.');
    });

    test('closing the Google picker counts as a cancellation, not an error', () {
      expect(isCancellation(Exception('GoogleSignInException(code GoogleSignInExceptionCode.canceled)')), isTrue);
      expect(isCancellation(Exception('sign_in_canceled')), isTrue);
      expect(isCancellation(Exception('network_error')), isFalse);
    });
  });

  testWidgets('the loading screen only ever removes itself', (tester) async {
    late BuildContext homeContext;
    final task = Completer<int>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(builder: (context) {
        homeContext = context;
        return const Scaffold(body: Text('home'));
      }),
    ));

    final result = runWithLoadingScreen(
      homeContext,
      title: 'Building',
      subtitle: 'Please wait',
      task: () => task.future,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Building'), findsOneWidget);

    // Back is blocked while it runs.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Building'), findsOneWidget);

    // Something else is opened on top while generation runs.
    Navigator.of(homeContext).push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('other page'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    task.complete(7);
    expect(await result, 7);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('other page'), findsOneWidget, reason: 'the page opened on top stays');
    expect(find.text('Building'), findsNothing);

    Navigator.of(homeContext).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a task that hangs times out instead of trapping the user', (tester) async {
    late BuildContext homeContext;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(builder: (context) {
        homeContext = context;
        return const Scaffold(body: Text('home'));
      }),
    ));
    Object? error;
    runWithLoadingScreen<void>(
      homeContext,
      title: 'Building',
      subtitle: 'Please wait',
      timeout: const Duration(seconds: 5),
      task: () => Completer<void>().future,
    ).catchError((Object e) => error = e);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(error, isA<TimeoutException>());
    expect(find.text('home'), findsOneWidget);
  });
}
