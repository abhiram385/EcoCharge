import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class WalletProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  double balance = 0;
  List<WalletTransaction> transactions = [];
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      final data = await _api.getWallet();
      balance = (data['balance'] as num).toDouble();
      transactions =
          (data['transactions'] as List).map((t) => WalletTransaction.fromJson(t)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> topUp(double amount) async {
    try {
      final data = await _api.topUpWallet(amount, reference: 'app_topup');
      balance = (data['balance'] as num).toDouble();
      await load();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
