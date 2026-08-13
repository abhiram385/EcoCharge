import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../data/vehicle_catalog.dart';
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
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const _AddVehicleSheetContent(),
    );
    if (added == true) _load();
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
                        subtitle: Text(
                          '${v.connectorType} • ${v.batteryCapacityKwh.toStringAsFixed(1)} kWh${v.regNumber != null ? ' • ${v.regNumber}' : ''}',
                        ),
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

class _AddVehicleSheetContent extends StatefulWidget {
  const _AddVehicleSheetContent();

  @override
  State<_AddVehicleSheetContent> createState() => _AddVehicleSheetContentState();
}

class _AddVehicleSheetContentState extends State<_AddVehicleSheetContent> {
  final _api = ApiService();
  bool _showManualForm = false;
  bool _saving = false;

  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  String _manualConnectorType = 'CCS2';

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCatalogEntry(VehicleCatalogEntry entry) async {
    setState(() => _saving = true);
    try {
      await _api.addVehicle(
        make: entry.make,
        model: entry.model,
        connectorType: entry.connectorType,
        batteryCapacityKwh: entry.capacityKwh,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vehicle: $e')),
      );
    }
  }

  Future<void> _saveManualEntry() async {
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final capacity = double.tryParse(_capacityCtrl.text.trim());
    if (make.isEmpty || model.isEmpty || capacity == null || capacity <= 0) return;

    setState(() => _saving = true);
    try {
      await _api.addVehicle(
        make: make,
        model: model,
        connectorType: _manualConnectorType,
        batteryCapacityKwh: capacity,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vehicle: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.chromeMist,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: _showManualForm ? _manualForm() : _catalogList(),
      ),
    );
  }

  Widget _catalogList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add a vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
        const SizedBox(height: 4),
        Text(
          'Pick your EV so we can size Auto Stop correctly.',
          style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: kVehicleCatalog.length + 1,
            itemBuilder: (context, i) {
              if (i == kVehicleCatalog.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    radius: 16,
                    child: ListTile(
                      leading: const Icon(Icons.edit_note_rounded, color: AppColors.skyBlue),
                      title: Text('Other / not listed', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                      onTap: _saving ? null : () => setState(() => _showManualForm = true),
                    ),
                  ),
                );
              }
              final entry = kVehicleCatalog[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  radius: 16,
                  child: ListTile(
                    leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                    title: Text(entry.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                    subtitle: Text('${entry.connectorType} • ${entry.capacityKwh.toStringAsFixed(1)} kWh'),
                    onTap: _saving ? null : () => _saveCatalogEntry(entry),
                  ),
                ),
              );
            },
          ),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator(color: AppColors.skyBlue)),
          ),
      ],
    );
  }

  Widget _manualForm() {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        final canSave = _makeCtrl.text.trim().isNotEmpty &&
            _modelCtrl.text.trim().isNotEmpty &&
            (double.tryParse(_capacityCtrl.text.trim()) ?? 0) > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.deepAzure),
                  onPressed: () => setState(() => _showManualForm = false),
                ),
                Text('Add your vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _makeCtrl,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Make (e.g. Tata) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtrl,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Model (e.g. Nexon EV) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacityCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Battery capacity in kWh (e.g. 40) *'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['CCS2', 'Type2'].map((type) {
                final sel = _manualConnectorType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: sel,
                  onSelected: (_) => setSheetState(() => _manualConnectorType = type),
                  selectedColor: AppColors.skyBlue,
                  labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                  backgroundColor: Colors.white,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text('* Make, model, and capacity are required', style: GoogleFonts.nunitoSans(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            EnergyOrbButton(
              label: 'Save vehicle',
              icon: Icons.directions_car_filled_rounded,
              green: true,
              width: double.infinity,
              loading: _saving,
              onPressed: !canSave || _saving ? null : _saveManualEntry,
            ),
          ],
        );
      },
    );
  }
}
