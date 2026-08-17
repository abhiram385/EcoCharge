import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../data/vehicle_catalog.dart';
import '../services/api_service.dart';
import 'aero/glass_panel.dart';
import 'aero/energy_orb_button.dart';

/// Bottom sheet for adding a vehicle: pick from the catalog or enter one
/// manually, with an optional plate number either way. Pops `true` if a
/// vehicle was saved.
class AddVehicleSheet extends StatefulWidget {
  const AddVehicleSheet({super.key});

  @override
  State<AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<AddVehicleSheet> {
  final _api = ApiService();
  bool _showManualForm = false;
  bool _saving = false;

  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  String _manualConnectorType = 'CCS2';
  bool _manualSwapCapable = false;

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _capacityCtrl.dispose();
    _regCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCatalogEntry(VehicleCatalogEntry entry, String? regNumber) async {
    setState(() => _saving = true);
    try {
      await _api.addVehicle(
        make: entry.make,
        model: entry.model,
        connectorType: entry.connectorType,
        batteryCapacityKwh: entry.capacityKwh,
        regNumber: regNumber,
        swapCapable: entry.swapCapable,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save vehicle: $e')));
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
        regNumber: _regCtrl.text.trim().isEmpty ? null : _regCtrl.text.trim(),
        swapCapable: _manualSwapCapable,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save vehicle: $e')));
    }
  }

  Future<void> _promptRegAndSave(VehicleCatalogEntry entry) async {
    final regCtrl = TextEditingController();
    final reg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add ${entry.displayName}'),
        content: TextField(
          controller: regCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Number plate (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
          TextButton(onPressed: () => Navigator.pop(ctx, regCtrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    await _saveCatalogEntry(entry, (reg == null || reg.isEmpty) ? null : reg);
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
          'Pick your EV — swap-capable ones are marked.',
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
                    leading: Icon(
                      entry.swapCapable ? Icons.battery_charging_full_rounded : Icons.directions_car_filled_rounded,
                      color: entry.swapCapable ? AppColors.leafGreen : AppColors.skyBlue,
                    ),
                    title: Text(entry.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${entry.connectorType} • ${entry.capacityKwh.toStringAsFixed(1)} kWh${entry.swapCapable ? ' • Swap-capable' : ''}',
                    ),
                    onTap: _saving ? null : () => _promptRegAndSave(entry),
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
        return SingleChildScrollView(
          child: Column(
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
              TextField(
                controller: _regCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'Number plate (optional)'),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _manualSwapCapable,
                onChanged: (v) => setSheetState(() => _manualSwapCapable = v),
                activeThumbColor: AppColors.leafGreen,
                title: Text('Swap-capable', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                subtitle: const Text('This vehicle can use battery swap points'),
              ),
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
          ),
        );
      },
    );
  }
}
