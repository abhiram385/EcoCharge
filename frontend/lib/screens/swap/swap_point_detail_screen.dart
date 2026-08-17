import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../models/swap.dart';
import '../../providers/swap_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../vehicles/manage_vehicles_screen.dart';

class SwapPointDetailScreen extends StatefulWidget {
  final String swapPointId;
  const SwapPointDetailScreen({super.key, required this.swapPointId});

  @override
  State<SwapPointDetailScreen> createState() => _SwapPointDetailScreenState();
}

class _SwapPointDetailScreenState extends State<SwapPointDetailScreen> {
  bool _swapping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SwapProvider>().loadSwapPointDetail(widget.swapPointId);
    });
  }

  Future<void> _swapNow(SwapPack pack) async {
    final api = ApiService();
    final rawVehicles = await api.getVehicles();
    final vehicles = rawVehicles.map((v) => Vehicle.fromJson(v)).toList();
    final compatible = vehicles.where((v) => v.swapCapable && v.connectorType == pack.packType).toList();

    if (!mounted) return;

    if (compatible.isEmpty) {
      final wantsToAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add a swap-capable vehicle'),
          content: const Text('You need a saved vehicle marked as swap-capable before swapping here.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add vehicle')),
          ],
        ),
      );
      if (wantsToAdd != true || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageVehiclesScreen()));
      if (!mounted) return;
      return _swapNow(pack);
    }

    final vehicle = await _pickVehicle(compatible);
    if (vehicle == null || !mounted) return;

    setState(() => _swapping = true);
    try {
      await api.redeemSwap(widget.swapPointId, pack.id, vehicleId: vehicle.id);
      if (!mounted) return;
      await context.read<SwapProvider>().loadSwapPointDetail(widget.swapPointId);
      if (!mounted) return;
      await context.read<WalletProvider>().load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swapped! ${vehicle.displayName} is now fully charged.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Swap failed: $e')));
    } finally {
      if (mounted) setState(() => _swapping = false);
    }
  }

  Future<Vehicle?> _pickVehicle(List<Vehicle> compatible) {
    if (compatible.length == 1) return Future.value(compatible.first);
    return showModalBottomSheet<Vehicle>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.chromeMist,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which vehicle?', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
            const SizedBox(height: 12),
            ...compatible.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    radius: 16,
                    child: ListTile(
                      leading: const Icon(Icons.two_wheeler_rounded, color: AppColors.leafGreen),
                      title: Text(v.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                      subtitle: Text('Battery now: ${v.batteryLevelPct}%'),
                      onTap: () => Navigator.pop(ctx, v),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SwapProvider>();
    final point = provider.selectedPoint;

    return Scaffold(
      appBar: AppBar(title: const Text('Swap point')),
      body: AeroBackground(
        bubbleCount: 3,
        child: provider.isLoadingDetail || point == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.leafGreen))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(point.name,
                      style: GoogleFonts.baloo2(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                  const SizedBox(height: 6),
                  Text(point.address ?? '',
                      style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _infoChip(Icons.star_rounded, '${point.rating} rating', AppColors.sunGlow, AppColors.sunPale),
                      const SizedBox(width: 10),
                      _infoChip(
                        Icons.access_time_filled_rounded,
                        point.isOpen24h ? 'Open 24/7' : 'Limited hours',
                        AppColors.leafDark,
                        AppColors.leafPale,
                      ),
                    ],
                  ),
                  if (point.amenities.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('Amenities', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: point.amenities
                          .map((a) => Chip(label: Text(a), avatar: const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.leafDark)))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Available packs', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
                  const SizedBox(height: 10),
                  ...provider.selectedPointPacks.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PackTile(pack: p, swapping: _swapping, onSwap: () => _swapNow(p)),
                      )),
                ],
              ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.nunitoSans(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  final SwapPack pack;
  final bool swapping;
  final VoidCallback onSwap;

  const _PackTile({required this.pack, required this.swapping, required this.onSwap});

  @override
  Widget build(BuildContext context) {
    final inStock = pack.inStock;
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: inStock ? AppColors.statusAvailable : AppColors.statusOffline,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: (inStock ? AppColors.statusAvailable : AppColors.statusOffline).withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(pack.packType, style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.deepAzure)),
              const Spacer(),
              Text(
                inStock ? '${pack.availableCount} in stock' : 'Out of stock',
                style: GoogleFonts.nunitoSans(
                  color: inStock ? AppColors.statusAvailable : AppColors.error,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.battery_full_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text('${pack.capacityKwh.toStringAsFixed(1)} kWh pack', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              const Icon(Icons.currency_rupee_rounded, size: 16, color: AppColors.textSecondary),
              Text('${pack.pricePerSwap.toStringAsFixed(0)} / swap', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          EnergyOrbButton(
            label: 'Swap now',
            icon: Icons.battery_charging_full_rounded,
            green: true,
            width: double.infinity,
            loading: swapping,
            onPressed: inStock && !swapping ? onSwap : null,
          ),
        ],
      ),
    );
  }
}
