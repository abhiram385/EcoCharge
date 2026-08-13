import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';

class HistoryScreen extends StatefulWidget {
  final bool isActive;
  const HistoryScreen({super.key, this.isActive = true});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  List<ChargingSession> _sessions = [];
  List<Booking> _bookings = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final sessions = await _api.getSessionHistory();
      final bookings = await _api.getBookings();
      setState(() {
        _sessions = sessions.map((s) => ChargingSession.fromJson(s)).toList();
        _bookings = bookings.map((b) => Booking.fromJson(b)).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.deepAzure,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.skyBlue,
          labelStyle: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Charging sessions'), Tab(text: 'Bookings')],
        ),
      ),
      body: AeroBackground(
        bubbleCount: 3,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
              : _hasError
                  ? _errorState()
                  : TabBarView(
                      controller: _tabController,
                      children: [_sessionsList(), _bookingsList()],
                    ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Center(
          child: Text("Couldn't load your history", style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(onPressed: _load, child: const Text('Try again')),
        ),
      ],
    );
  }

  Widget _sessionsList() {
    if (_sessions.isEmpty) {
      return _empty('No charging sessions yet', Icons.bolt_rounded);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      itemBuilder: (context, i) {
        final s = _sessions[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            radius: 20,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: AppColors.orbGradient, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.stationName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                      Text(DateFormat('MMM d, h:mm a').format(s.startedAt),
                          style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${s.cost.toStringAsFixed(0)}', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                    Text('${s.energyKwh.toStringAsFixed(1)} kWh', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bookingsList() {
    if (_bookings.isEmpty) {
      return _empty('No bookings yet', Icons.event_available_rounded);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookings.length,
      itemBuilder: (context, i) {
        final b = _bookings[i];
        final statusColor = b.status == 'confirmed'
            ? AppColors.statusAvailable
            : b.status == 'cancelled'
                ? AppColors.error
                : AppColors.textMuted;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPanel(
            padding: EdgeInsets.zero,
            radius: 20,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(gradient: AppColors.orbGradientGreen, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.event_available_rounded, color: Colors.white),
              ),
              title: Text(b.stationName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${DateFormat('MMM d, h:mm a').format(b.slotStart)} – ${DateFormat('h:mm a').format(b.slotEnd)}',
                style: GoogleFonts.nunitoSans(fontSize: 12.5),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(b.status, style: GoogleFonts.nunitoSans(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String message, IconData icon) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Center(child: Text(message, style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
