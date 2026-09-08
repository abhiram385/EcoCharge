import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ecocharge/providers/auth_provider.dart';
import 'package:ecocharge/screens/splash_screen.dart';
import 'package:ecocharge/screens/auth/phone_entry_screen.dart';

const _secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Widget _app() => ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const MaterialApp(home: SplashScreen()),
    );

void _mockSecureStorage(Future<Object?> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, handler);
}

/// Pump past the 1.1s delay, the 3s session-check timeout and the 5s backstop,
/// without pumpAndSettle (the background animation never settles).
Future<void> _advancePastBackstop(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(seconds: 5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500)); // route transition
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('reaches the login screen when secure storage throws', (tester) async {
    _mockSecureStorage((call) async {
      throw PlatformException(code: 'KeystoreException', message: 'boom');
    });

    await tester.pumpWidget(_app());
    await _advancePastBackstop(tester);

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  testWidgets('reaches the login screen when secure storage hangs forever', (tester) async {
    _mockSecureStorage((call) async {
      await Completer<void>().future; // never completes
      return null;
    });

    await tester.pumpWidget(_app());
    await _advancePastBackstop(tester);

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });

  testWidgets('surfaces the failure on screen before moving on', (tester) async {
    _mockSecureStorage((call) async {
      throw PlatformException(code: 'KeystoreException', message: 'boom');
    });

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.textContaining('KeystoreException'), findsOneWidget);
  });

  testWidgets('goes straight to login on a fresh install (no stored token)', (tester) async {
    _mockSecureStorage((call) async => null);

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PhoneEntryScreen), findsOneWidget);
  });
}
