import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ecocharge/providers/auth_provider.dart';
import 'package:ecocharge/screens/splash_screen.dart';
import 'package:ecocharge/screens/auth/phone_entry_screen.dart';

Widget _app({Future<bool> Function()? sessionCheck}) => ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(home: SplashScreen(sessionCheck: sessionCheck)),
    );

/// Pump past the 1.1s delay, the 3s session-check timeout, the 5s backstop and
/// the route transition — without pumpAndSettle (the background never settles).
Future<void> _advancePastBackstop(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(seconds: 5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('reaches the login screen when the session check throws', (tester) async {
    await tester.pumpWidget(_app(sessionCheck: () async => throw Exception('keystore boom')));
    await _advancePastBackstop(tester);

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  testWidgets('reaches the login screen when the session check hangs forever', (tester) async {
    await tester.pumpWidget(_app(sessionCheck: () => Completer<bool>().future));
    await _advancePastBackstop(tester);

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  testWidgets('surfaces the failure on screen before the backstop moves on', (tester) async {
    await tester.pumpWidget(_app(sessionCheck: () async => throw Exception('keystore boom')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('keystore boom'), findsOneWidget);

    // Drain timers: let the backstop navigate so nothing outlives the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('goes to login when not logged in', (tester) async {
    await tester.pumpWidget(_app(sessionCheck: () async => false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  testWidgets('shows a heartbeat once startup passes 3s', (tester) async {
    await tester.pumpWidget(_app(sessionCheck: () => Completer<bool>().future));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('starting'), findsOneWidget);

    // Let the backstop navigate away so no timers outlive the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
