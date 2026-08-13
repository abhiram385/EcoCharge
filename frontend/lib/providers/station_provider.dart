import 'package:flutter/foundation.dart';
import '../models/station.dart';
import '../services/api_service.dart';

class StationProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Station> stations = [];
  bool isLoading = false;
  String? error;

  Station? selectedStation;
  List<Connector> selectedStationConnectors = [];
  bool isLoadingDetail = false;

  Future<void> loadNearby(double lat, double lng) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final raw = await _api.nearbyStations(lat, lng);
      stations = raw.map((j) => Station.fromJson(j)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStationDetail(String id) async {
    isLoadingDetail = true;
    notifyListeners();
    try {
      final data = await _api.stationDetail(id);
      selectedStation = Station.fromJson(data['station']);
      selectedStationConnectors =
          (data['connectors'] as List).map((c) => Connector.fromJson(c)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoadingDetail = false;
      notifyListeners();
    }
  }
}
