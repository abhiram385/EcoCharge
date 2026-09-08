import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/aero/aero_background.dart';
import 'auth/phone_entry_screen.dart';
import 'hub/landing_hub_screen.dart';

class SplashScreen extends StatefulWidget {
  /// Overridable so tests can drive the slow / failing paths without a
  /// platform channel. Defaults to the real token-store check.
  final Future<bool> Function()? sessionCheck;

  const SplashScreen({super.key, this.sessionCheck});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  bool _navigated = false;
  String? _error;
  int _elapsed = 0;
  Timer? _backstop;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _init();
    // Hard backstop: whatever goes wrong in _init (a plugin call that hangs,
    // an exception we didn't anticipate), never trap the user on the splash.
    _backstop = Timer(const Duration(seconds: 4), () => _goNext(loggedIn: false));
    // Heartbeat: if this counter climbs but the screen never advances, the
    // Dart isolate is alive and something else is wedged (render/navigation).
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  Future<void> _init() async {
    // The session check races its own 2s cap; the splash shows for at least
    // 1.4s regardless. Navigation never waits on anything longer than that.
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 1400));
    bool loggedIn = false;
    try {
      final check = widget.sessionCheck ?? () => ApiService().isLoggedIn;
      loggedIn = await check().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('SplashScreen: session check failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
    await minSplash;
    _goNext(loggedIn: loggedIn);
  }

  void _goNext({required bool loggedIn}) {
    if (!mounted || _navigated) return;
    _navigated = true;
    _backstop?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => loggedIn ? const LandingHubScreen() : const PhoneEntryScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _backstop?.cancel();
    _heartbeat?.cancel();
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
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunitoSans(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (_elapsed >= 3) ...[
                  const SizedBox(height: 24),
                  Text(
                    'starting… ${_elapsed}s',
                    style: GoogleFonts.nunitoSans(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
