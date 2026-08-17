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
  runApp(const EcoChargeApp());
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
