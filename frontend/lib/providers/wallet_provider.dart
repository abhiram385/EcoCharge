import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class WalletProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final Razorpay _razorpay = Razorpay();

  double balance = 0;
  List<WalletTransaction> transactions = [];
  bool isLoading = false;
  String? error;

  // Bridges Razorpay's callback-based SDK back to topUp()'s Future<bool>.
  Completer<bool>? _topUpCompleter;

  WalletProvider() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

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

  /// Opens a Razorpay order on the backend, then the Checkout SDK. Resolves
  /// once the payment is verified server-side and the wallet credited (or
  /// false on any failure/cancellation) — the actual credit only happens
  /// after the backend verifies the payment signature, not from anything
  /// this method decides client-side.
  Future<bool> topUp(double amount) async {
    error = null;
    try {
      final order = await _api.createTopupOrder(amount);
      _topUpCompleter = Completer<bool>();
      _razorpay.open({
        'key': order['keyId'],
        'amount': (amount * 100).round(), // paise; must match what the order was created with
        'order_id': order['orderId'],
        'name': 'EcoCharge',
        'description': 'Wallet top-up',
        'theme': {'color': '#1E6FD9'},
      });
      return await _topUpCompleter!.future;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final data = await _api.verifyTopup(
        orderId: response.orderId!,
        paymentId: response.paymentId!,
        signature: response.signature!,
      );
      balance = (data['balance'] as num).toDouble();
      await load();
      _topUpCompleter?.complete(true);
    } catch (e) {
      error = e.toString();
      notifyListeners();
      _topUpCompleter?.complete(false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    error = response.message ?? 'Payment failed';
    notifyListeners();
    _topUpCompleter?.complete(false);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    error = '${response.walletName ?? 'That wallet'} isn\'t supported yet';
    notifyListeners();
    _topUpCompleter?.complete(false);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }
}
