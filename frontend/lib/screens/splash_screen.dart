import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/aero/aero_background.dart';
import 'auth/phone_entry_screen.dart';
import 'home/home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1100));
    final api = ApiService();
    final loggedIn = await api.isLoggedIn;
    if (!mounted) return;
    if (loggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AeroBackground(
        bubbleCount: 9,
        child: Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.orbGradient,
                    boxShadow: [
                      BoxShadow(color: AppColors.skyBlue.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 4),
                      const BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 10,
                        left: 18,
                        right: 18,
                        height: 34,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0.0)],
                            ),
                          ),
                        ),
                      ),
                      const Icon(Icons.bolt_rounded, color: Colors.white, size: 54),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'EcoCharge',
                  style: GoogleFonts.baloo2(
                    color: AppColors.deepAzure,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Charge clean. Drive further.',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
