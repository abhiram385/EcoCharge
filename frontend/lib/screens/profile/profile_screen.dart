import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../auth/phone_entry_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  List<Vehicle> _vehicles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.getVehicles();
      setState(() => _vehicles = raw.map((v) => Vehicle.fromJson(v)).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addVehicleSheet() async {
    final makeCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String connectorType = 'CCS2';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final canSave = makeCtrl.text.trim().isNotEmpty && modelCtrl.text.trim().isNotEmpty;
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.chromeMist,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: makeCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(hintText: 'Make (e.g. Tata) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(hintText: 'Model (e.g. Nexon EV) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: regCtrl, decoration: const InputDecoration(hintText: 'Registration number (optional)')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['CCS2', 'CHAdeMO', 'Type2', 'GBT'].map((type) {
                      final sel = connectorType == type;
                      return ChoiceChip(
                        label: Text(type),
                        selected: sel,
                        onSelected: (_) => setSheetState(() => connectorType = type),
                        selectedColor: AppColors.skyBlue,
                        labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                        backgroundColor: Colors.white,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('* Make and model are required', style: GoogleFonts.nunitoSans(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  EnergyOrbButton(
                    label: 'Save vehicle',
                    icon: Icons.directions_car_filled_rounded,
                    green: true,
                    width: double.infinity,
                    onPressed: !canSave
                        ? null
                        : () async {
                            final make = makeCtrl.text.trim();
                            final model = modelCtrl.text.trim();
                            final regNumber = regCtrl.text.trim();
                            Navigator.pop(ctx);
                            try {
                              await _api.addVehicle(
                                make: make,
                                model: model,
                                connectorType: connectorType,
                                regNumber: regNumber.isEmpty ? null : regNumber,
                              );
                              _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not save vehicle: $e')),
                              );
                            }
                          },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _api.clearToken();
    if (!mounted) return;
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('My vehicles', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
                TextButton.icon(
                  onPressed: _addVehicleSheet,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.skyBlue)))
            else if (_vehicles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No vehicles added yet', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              )
            else
              ..._vehicles.map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassPanel(
                      padding: EdgeInsets.zero,
                      radius: 20,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                        title: Text(v.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                        subtitle: Text('${v.connectorType}${v.regNumber != null ? ' • ${v.regNumber}' : ''}'),
                        trailing: v.isDefault
                            ? const Chip(label: Text('Default', style: TextStyle(fontSize: 11)))
                            : IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                                onPressed: () async {
                                  await _api.deleteVehicle(v.id);
                                  _load();
                                },
                              ),
                      ),
                    ),
                  )),
            const SizedBox(height: 28),
            GlassPanel(
              padding: EdgeInsets.zero,
              radius: 20,
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: Text('Log out', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, color: AppColors.error)),
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
