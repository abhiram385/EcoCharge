class AppUser {
  final String id;
  final String phone;
  final String? name;
  final String? email;
  final double walletBalance;

  AppUser({
    required this.id,
    required this.phone,
    this.name,
    this.email,
    required this.walletBalance,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'],
      phone: json['phone'],
      name: json['name'],
      email: json['email'],
      walletBalance: (json['walletBalance'] as num).toDouble(),
    );
  }
}

class Vehicle {
  final String id;
  final String make;
  final String model;
  final String connectorType;
  final String? regNumber;
  final bool isDefault;

  Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.connectorType,
    this.regNumber,
    required this.isDefault,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'],
      make: json['make'],
      model: json['model'],
      connectorType: json['connectorType'],
      regNumber: json['regNumber'],
      isDefault: json['isDefault'] ?? false,
    );
  }

  String get displayName => '$make $model';
}

class Booking {
  final String id;
  final String stationId;
  final String stationName;
  final String? stationAddress;
  final String connectorId;
  final String? vehicleId;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String status; // confirmed, cancelled, completed, no_show

  Booking({
    required this.id,
    required this.stationId,
    required this.stationName,
    this.stationAddress,
    required this.connectorId,
    this.vehicleId,
    required this.slotStart,
    required this.slotEnd,
    required this.status,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'],
      stationId: json['stationId'],
      stationName: json['stationName'] ?? '',
      stationAddress: json['stationAddress'],
      connectorId: json['connectorId'],
      vehicleId: json['vehicleId'],
      slotStart: DateTime.parse(json['slotStart']),
      slotEnd: DateTime.parse(json['slotEnd']),
      status: json['status'],
    );
  }
}

class ChargingSession {
  final String id;
  final String stationId;
  final String stationName;
  final String connectorId;
  final String status; // active, completed, stopped, error
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final double energyKwh;
  final double cost;
  final double? powerKw;
  final double? pricePerKwh;

  ChargingSession({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.connectorId,
    required this.status,
    required this.startedAt,
    this.stoppedAt,
    required this.energyKwh,
    required this.cost,
    this.powerKw,
    this.pricePerKwh,
  });

  factory ChargingSession.fromJson(Map<String, dynamic> json) {
    return ChargingSession(
      id: json['id'],
      stationId: json['stationId'],
      stationName: json['stationName'] ?? '',
      connectorId: json['connectorId'],
      status: json['status'],
      startedAt: DateTime.parse(json['startedAt']),
      stoppedAt: json['stoppedAt'] != null ? DateTime.parse(json['stoppedAt']) : null,
      energyKwh: (json['energyKwh'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      powerKw: json['powerKw'] != null ? (json['powerKw'] as num).toDouble() : null,
      pricePerKwh: json['pricePerKwh'] != null ? (json['pricePerKwh'] as num).toDouble() : null,
    );
  }
}

class WalletTransaction {
  final String id;
  final String type; // topup, charge_debit, refund
  final double amount;
  final String? reference;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.reference,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'],
      type: json['type'],
      amount: (json['amount'] as num).toDouble(),
      reference: json['reference'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
