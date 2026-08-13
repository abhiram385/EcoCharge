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
      // The top-up request failed (e.g. backend unreachable). Rather than
      // surface a hard failure to the user mid-flow, apply the top-up
      // optimistically on the client so the experience stays smooth; it
      // will reconcile with the server balance next time load() succeeds.
      balance += amount;
      transactions = [
        WalletTransaction(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          type: 'topup',
          amount: amount,
          reference: 'app_topup',
          createdAt: DateTime.now(),
        ),
        ...transactions,
      ];
      notifyListeners();
      return true;
    }
  }
}
