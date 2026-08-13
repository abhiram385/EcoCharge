import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../home/home_shell.dart';

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SessionProvider>().startPolling();
  }

  @override
  void dispose() {
    context.read<SessionProvider>().stopPolling();
    super.dispose();
  }

  Future<void> _stop() async {
    final provider = context.read<SessionProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Stop charging?'),
        content: const Text('This will end your session and deduct the cost from your wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop')),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await provider.stopCharging();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Charging session complete. Thanks for going green! 🌱')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Could not stop session')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSession;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Charging session')),
        body: const Center(child: Text('No active charging session')),
      );
    }

    final progress = (session.energyKwh / 40).clamp(0.0, 1.0); // visual progress toward ~40kWh full charge

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.orbGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  title: Text('Charging in progress', style: GoogleFonts.baloo2(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.sunGlow.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 4)],
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 14,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(AppColors.sunGlow),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
                        const SizedBox(height: 6),
                        Text('${session.energyKwh.toStringAsFixed(1)} kWh',
                            style: GoogleFonts.baloo2(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        Text('delivered', style: GoogleFonts.nunitoSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.chromeMist,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.stationName, style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                      const SizedBox(height: 4),
                      Text('Started at ${_formatTime(session.startedAt)}',
                          style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard('Power', '${session.powerKw?.toStringAsFixed(0) ?? '-'} kW', Icons.flash_on_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard('Cost so far', '₹${session.cost.toStringAsFixed(0)}', Icons.currency_rupee_rounded),
                          ),
                        ],
                      ),
                      const Spacer(),
                      EnergyOrbButton(
                        label: 'Stop charging',
                        icon: Icons.stop_circle_rounded,
                        onPressed: _stop,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  Widget _statCard(String label, String value, IconData icon) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.skyBlue, size: 20),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.deepAzure)),
          Text(label, style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
