import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'home_screen.dart';
import '../history/history_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      HistoryScreen(isActive: _index == 1),
      const WalletScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glassHighlight,
              border: Border(top: BorderSide(color: AppColors.dewWhite.withValues(alpha: 0.9), width: 1.5)),
              boxShadow: [
                BoxShadow(color: AppColors.skyBlue.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, -6)),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppColors.deepAzure,
              unselectedItemColor: AppColors.textMuted,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map_rounded), label: 'Explore'),
                BottomNavigationBarItem(icon: Icon(Icons.history_outlined), activeIcon: Icon(Icons.history_rounded), label: 'History'),
                BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
                BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
