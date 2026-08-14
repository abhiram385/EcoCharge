import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  AppUser? user;
  bool isLoading = false;
  String? error;
  bool checkingSession = true;
  String? lastDevOtp;

  Future<void> bootstrap() async {
    checkingSession = true;
    notifyListeners();
    final loggedIn = await _api.isLoggedIn;
    // Token presence implies a session; user profile is refreshed via wallet/etc.
    // (A dedicated /me endpoint could be added; for now we keep it lightweight.)
    checkingSession = false;
    if (!loggedIn) {
      user = null;
    }
    notifyListeners();
  }

  Future<bool> requestOtp(String phone) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.requestOtp(phone);
      lastDevOtp = data['devOtp'] as String?;
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

  Future<bool> verifyOtp(String phone, String code) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.verifyOtp(phone, code);
      user = AppUser.fromJson(data['user']);
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

  Future<void> logout() async {
    await _api.clearToken();
    user = null;
    notifyListeners();
  }
}
