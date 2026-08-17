import 'package:flutter/foundation.dart';
import '../models/swap.dart';
import '../services/api_service.dart';

class SwapProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<SwapPoint> swapPoints = [];
  bool isLoading = false;
  String? error;

  SwapPoint? selectedPoint;
  List<SwapPack> selectedPointPacks = [];
  bool isLoadingDetail = false;

  Future<void> loadNearby(double lat, double lng) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final raw = await _api.nearbySwapPoints(lat, lng);
      swapPoints = raw.map((j) => SwapPoint.fromJson(j)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSwapPointDetail(String id) async {
    isLoadingDetail = true;
    notifyListeners();
    try {
      final data = await _api.swapPointDetail(id);
      selectedPoint = SwapPoint.fromJson(data['swapPoint']);
      selectedPointPacks = (data['packs'] as List).map((p) => SwapPack.fromJson(p)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoadingDetail = false;
      notifyListeners();
    }
  }
}
