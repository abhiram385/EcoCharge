import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../auth/phone_entry_screen.dart';
import '../vehicles/manage_vehicles_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await ApiService().clearToken();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AeroBackground(
        bubbleCount: 3,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppColors.orbGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.skyBlue.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your account', style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                      const SizedBox(height: 4),
                      Text('Manage vehicles & preferences', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            GlassPanel(
              padding: EdgeInsets.zero,
              radius: 20,
              child: ListTile(
                leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                title: Text('My vehicles', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                subtitle: const Text('Battery level, plate number, swap-capable vehicles'),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManageVehiclesScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GlassPanel(
              padding: EdgeInsets.zero,
              radius: 20,
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: Text('Log out', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, color: AppColors.error)),
                onTap: () => _logout(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
