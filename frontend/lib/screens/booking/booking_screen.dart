import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/station.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';

class BookingScreen extends StatefulWidget {
  final Station station;
  final Connector connector;
  const BookingScreen({super.key, required this.station, required this.connector});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30)));
  int _durationMinutes = 30;
  bool _submitting = false;

  final _api = ApiService();

  DateTime get _slotStart => DateTime(_date.year, _date.month, _date.day, _startTime.hour, _startTime.minute);
  DateTime get _slotEnd => _slotStart.add(Duration(minutes: _durationMinutes));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _confirmBooking() async {
    setState(() => _submitting = true);
    try {
      await _api.createBooking(
        stationId: widget.station.id,
        connectorId: widget.connector.id,
        slotStart: _slotStart,
        slotEnd: _slotEnd,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success),
              SizedBox(width: 10),
              Text('Slot booked!'),
            ],
          ),
          content: Text(
            '${widget.station.name}\n${DateFormat('MMM d, h:mm a').format(_slotStart)} – ${DateFormat('h:mm a').format(_slotEnd)}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimatedKwh = (widget.connector.powerKw * _durationMinutes / 60);
    final estimatedCost = estimatedKwh * widget.connector.pricePerKwh;

    return Scaffold(
      appBar: AppBar(title: const Text('Book a slot')),
      body: AeroBackground(
        bubbleCount: 3,
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassPanel(
              padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(gradient: AppColors.orbGradient, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.ev_station_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.station.name, style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.deepAzure)),
                          Text('${widget.connector.connectorType} • ${widget.connector.powerKw.toStringAsFixed(0)} kW',
                              style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
            const SizedBox(height: 20),
            Text('Choose date & time', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _selector(
                    icon: Icons.calendar_today_rounded,
                    label: DateFormat('EEE, MMM d').format(_date),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _selector(
                    icon: Icons.access_time_rounded,
                    label: _startTime.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Duration', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [30, 45, 60, 90].map((m) {
                final selected = _durationMinutes == m;
                return ChoiceChip(
                  label: Text('${m} min'),
                  selected: selected,
                  onSelected: (_) => setState(() => _durationMinutes = m),
                  selectedColor: AppColors.skyBlue,
                  labelStyle: GoogleFonts.nunitoSans(
                    color: selected ? Colors.white : AppColors.deepAzure,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: AppColors.chromeMist,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.sunPale, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppColors.sunGlow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Estimated ~${estimatedKwh.toStringAsFixed(1)} kWh • ₹${estimatedCost.toStringAsFixed(0)}',
                      style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            EnergyOrbButton(
              label: 'Confirm booking',
              icon: Icons.event_available_rounded,
              loading: _submitting,
              onPressed: _submitting ? null : _confirmBooking,
              green: true,
              width: double.infinity,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _selector({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.skyBlue),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
