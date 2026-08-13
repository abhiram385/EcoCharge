import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around the EcoCharge REST API.
/// Change [baseUrl] to point at your deployed backend, or use
/// --dart-define=API_BASE_URL=https://your-api.example.com when building.
class ApiService {
  static const _defaultBaseUrl = 'http://10.0.2.2:4000'; // Android emulator -> localhost
  static const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'ecocharge_auth_token';

  Future<String?> get _token async => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
  Future<bool> get isLoggedIn async => (await _token) != null;

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await _token;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _handle(http.Response res) {
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Future.value(body);
    }
    final message = body is Map && body['error'] != null ? body['error'] : 'Something went wrong';
    throw ApiException(message, statusCode: res.statusCode, body: body is Map ? body : {});
  }

  // ---------- Auth ----------

  Future<Map<String, dynamic>> requestOtp(String phone) async {
    final res = await http.post(_uri('/api/auth/request-otp'),
        headers: await _headers(auth: false), body: jsonEncode({'phone': phone}));
    return await _handle(res);
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code, {String? name}) async {
    final res = await http.post(
      _uri('/api/auth/verify-otp'),
      headers: await _headers(auth: false),
      body: jsonEncode({'phone': phone, 'code': code, if (name != null) 'name': name}),
    );
    final data = await _handle(res);
    await saveToken(data['token']);
    return data;
  }

  // ---------- Stations ----------

  Future<List<dynamic>> nearbyStations(double lat, double lng, {double radiusKm = 15}) async {
    final res = await http.get(
      _uri('/api/stations/nearby', {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radiusKm': radiusKm.toString(),
      }),
      headers: await _headers(),
    );
    final data = await _handle(res);
    return data['stations'];
  }

  Future<Map<String, dynamic>> stationDetail(String id) async {
    final res = await http.get(_uri('/api/stations/$id'), headers: await _headers());
    return await _handle(res);
  }

  // ---------- Vehicles ----------

  Future<List<dynamic>> getVehicles() async {
    final res = await http.get(_uri('/api/vehicles'), headers: await _headers());
    final data = await _handle(res);
    return data['vehicles'];
  }

  Future<Map<String, dynamic>> addVehicle({
    required String make,
    required String model,
    required String connectorType,
    String? regNumber,
    bool isDefault = false,
  }) async {
    final res = await http.post(
      _uri('/api/vehicles'),
      headers: await _headers(),
      body: jsonEncode({
        'make': make,
        'model': model,
        'connectorType': connectorType,
        'regNumber': regNumber,
        'isDefault': isDefault,
      }),
    );
    return await _handle(res);
  }

  Future<void> deleteVehicle(String id) async {
    final res = await http.delete(_uri('/api/vehicles/$id'), headers: await _headers());
    await _handle(res);
  }

  // ---------- Bookings ----------

  Future<Map<String, dynamic>> createBooking({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    required DateTime slotStart,
    required DateTime slotEnd,
  }) async {
    final res = await http.post(
      _uri('/api/bookings'),
      headers: await _headers(),
      body: jsonEncode({
        'stationId': stationId,
        'connectorId': connectorId,
        'vehicleId': vehicleId,
        'slotStart': slotStart.toIso8601String(),
        'slotEnd': slotEnd.toIso8601String(),
      }),
    );
    return await _handle(res);
  }

  Future<List<dynamic>> getBookings() async {
    final res = await http.get(_uri('/api/bookings'), headers: await _headers());
    final data = await _handle(res);
    return data['bookings'];
  }

  Future<void> cancelBooking(String id) async {
    final res = await http.post(_uri('/api/bookings/$id/cancel'), headers: await _headers());
    await _handle(res);
  }

  // ---------- Charging sessions ----------

  Future<Map<String, dynamic>> startSession({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    String? bookingId,
  }) async {
    final res = await http.post(
      _uri('/api/sessions/start'),
      headers: await _headers(),
      body: jsonEncode({
        'stationId': stationId,
        'connectorId': connectorId,
        'vehicleId': vehicleId,
        'bookingId': bookingId,
      }),
    );
    return await _handle(res);
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    final res = await http.get(_uri('/api/sessions/active'), headers: await _headers());
    return await _handle(res);
  }

  Future<Map<String, dynamic>> stopSession(String sessionId) async {
    final res = await http.post(_uri('/api/sessions/$sessionId/stop'), headers: await _headers());
    return await _handle(res);
  }

  Future<List<dynamic>> getSessionHistory() async {
    final res = await http.get(_uri('/api/sessions/history'), headers: await _headers());
    final data = await _handle(res);
    return data['sessions'];
  }

  // ---------- Wallet ----------

  Future<Map<String, dynamic>> getWallet() async {
    final res = await http.get(_uri('/api/wallet'), headers: await _headers());
    return await _handle(res);
  }

  Future<Map<String, dynamic>> topUpWallet(double amount, {String? reference}) async {
    final res = await http.post(
      _uri('/api/wallet/topup'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount, 'reference': reference}),
    );
    return await _handle(res);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map body;
  ApiException(this.message, {required this.statusCode, this.body = const {}});

  @override
  String toString() => message;
}
