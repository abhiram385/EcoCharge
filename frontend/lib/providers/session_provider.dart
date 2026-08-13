import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SessionProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  ChargingSession? activeSession;
  bool isLoading = false;
  String? error;
  Timer? _pollTimer;

  // Set for exactly one refresh cycle when a poll discovers the session was
  // auto-stopped (battery reached its target). The active-session screen
  // consumes this once (via a listener) then calls clearAutoStopMessage().
  String? autoStopMessage;

  Future<void> refreshActiveSession() async {
    try {
      final data = await _api.getActiveSession();
      final autoStopped = data['autoStopped'] == true;
      if (autoStopped) {
        final session = data['session'] != null ? ChargingSession.fromJson(data['session']) : null;
        final pct = session?.batteryPct.toStringAsFixed(0) ?? '100';
        autoStopMessage = '🔋 Auto-stopped at $pct% — charged to your target!';
        activeSession = null;
        stopPolling();
      } else {
        activeSession = data['session'] != null ? ChargingSession.fromJson(data['session']) : null;
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
    }
  }

  void clearAutoStopMessage() {
    autoStopMessage = null;
  }

  void startPolling() {
    _pollTimer?.cancel();
    refreshActiveSession();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshActiveSession());
  }

  void stopPolling() {
    _pollTimer?.cancel();
  }

  Future<bool> startCharging({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    String? bookingId,
    int? autoStopPct,
  }) async {
    isLoading = true;
    error = null;
    autoStopMessage = null;
    notifyListeners();
    try {
      final data = await _api.startSession(
        stationId: stationId,
        connectorId: connectorId,
        vehicleId: vehicleId,
        bookingId: bookingId,
        autoStopPct: autoStopPct,
      );
      activeSession = ChargingSession.fromJson(data['session']);
      startPolling();
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> stopCharging() async {
    if (activeSession == null) return false;
    isLoading = true;
    notifyListeners();
    try {
      await _api.stopSession(activeSession!.id);
      activeSession = null;
      autoStopMessage = null;
      stopPolling();
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAutoStop(int? autoStopPct) async {
    if (activeSession == null) return false;
    try {
      final data = await _api.setAutoStop(activeSession!.id, autoStopPct);
      activeSession = ChargingSession.fromJson(data['session']);
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
