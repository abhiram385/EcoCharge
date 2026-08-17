import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../home/home_shell.dart';
import '../swap/battery_swap_home_screen.dart';
import '../vehicles/manage_vehicles_screen.dart';

/// The screen shown right after login: a hub with three destinations —
/// charging, battery swap, and vehicle management — rather than dropping
/// straight into the charging dashboard.
class LandingHubScreen extends StatelessWidget {
  const LandingHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final greetingName = (user?.name?.isNotEmpty ?? false) ? user!.name! : (user?.phone ?? 'there');

    return Scaffold(
      body: AeroBackground(
        bubbleCount: 7,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hey $greetingName',
                  style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'What do you need today?',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 32),
                _HubOptionCard(
                  icon: Icons.ev_station_rounded,
                  gradient: AppColors.orbGradient,
                  glow: AppColors.skyBlue,
                  title: 'Charge Up',
                  subtitle: 'Find a charging station near you',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HomeShell()),
                  ),
                ),
                const SizedBox(height: 16),
                _HubOptionCard(
                  icon: Icons.battery_charging_full_rounded,
                  gradient: AppColors.orbGradientGreen,
                  glow: AppColors.leafGreen,
                  title: 'Battery Swap',
                  subtitle: 'Swap your pack, skip the wait',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BatterySwapHomeScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                _HubOptionCard(
                  icon: Icons.directions_car_filled_rounded,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD873), AppColors.sunGlow, Color(0xFFE69500)],
                  ),
                  glow: AppColors.sunGlow,
                  title: 'My Vehicles',
                  subtitle: 'View, manage & track your rides',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ManageVehiclesScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubOptionCard extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  final Color glow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubOptionCard({
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: GlassPanel(
        radius: 26,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
                boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 1)],
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
