import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
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
    final provider = context.read<SessionProvider>();
    provider.startPolling();
    provider.addListener(_onProviderChange);
  }

  @override
  void dispose() {
    final provider = context.read<SessionProvider>();
    provider.removeListener(_onProviderChange);
    provider.stopPolling();
    super.dispose();
  }

  void _onProviderChange() {
    final provider = context.read<SessionProvider>();
    if (provider.activeSession == null && provider.autoStopMessage != null) {
      final message = provider.autoStopMessage!;
      provider.clearAutoStopMessage();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (provider.autoStopBlockedMessage != null) {
      final message = provider.autoStopBlockedMessage!;
      provider.clearAutoStopBlockedMessage();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
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

    final progress = (session.batteryPct / 100).clamp(0.0, 1.0);

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
                        const Icon(Icons.battery_charging_full_rounded, color: Colors.white, size: 32),
                        const SizedBox(height: 6),
                        Text('${session.batteryPct.toStringAsFixed(0)}%',
                            style: GoogleFonts.baloo2(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        Text('battery', style: GoogleFonts.nunitoSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
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
                      const SizedBox(height: 16),
                      _AutoStopControl(session: session),
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

class _AutoStopControl extends StatefulWidget {
  final ChargingSession session;
  const _AutoStopControl({required this.session});

  @override
  State<_AutoStopControl> createState() => _AutoStopControlState();
}

class _AutoStopControlState extends State<_AutoStopControl> {
  late int _selected = widget.session.autoStopPct ?? 100;

  @override
  void didUpdateWidget(covariant _AutoStopControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync if another source (e.g. a fresh poll) changed the target.
    final serverValue = widget.session.autoStopPct ?? 100;
    if (serverValue != _selected) _selected = serverValue;
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_circle_rounded, color: AppColors.skyBlue, size: 20),
              const SizedBox(width: 8),
              Text('Auto Stop at $_selected%',
                  style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, color: AppColors.deepAzure)),
            ],
          ),
          Slider(
            value: _selected.toDouble(),
            min: 10,
            max: 100,
            divisions: 9,
            activeColor: AppColors.skyBlue,
            label: '$_selected%',
            onChanged: (v) => setState(() => _selected = v.round()),
            onChangeEnd: (v) {
              final pct = v.round();
              context.read<SessionProvider>().updateAutoStop(pct == 100 ? null : pct);
            },
          ),
        ],
      ),
    );
  }
}
