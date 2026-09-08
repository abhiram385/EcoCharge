import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/station_provider.dart';
import 'providers/session_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/swap_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  // Make build/runtime failures visible on screen instead of a blank freeze —
  // this app gets demoed on devices we can't attach a debugger to.
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: const Color(0xFF0B1B2B),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              'EcoCharge hit an error:\n\n${details.exceptionAsString()}\n\n${details.stack}',
              style: const TextStyle(color: Color(0xFFFFB4B4), fontSize: 12),
            ),
          ),
        ),
      );

  runZonedGuarded(() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };
    runApp(const EcoChargeApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class EcoChargeApp extends StatelessWidget {
  const EcoChargeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => StationProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => SwapProvider()),
      ],
      child: MaterialApp(
        title: 'EcoCharge',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}
