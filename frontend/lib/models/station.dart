class Station {
  final String id;
  final String name;
  final String? address;
  final String? city;
  final double latitude;
  final double longitude;
  final double rating;
  final bool isOpen24h;
  final List<String> amenities;
  final String? distanceKm;

  Station({
    required this.id,
    required this.name,
    this.address,
    this.city,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.isOpen24h,
    required this.amenities,
    this.distanceKm,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      city: json['city'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      rating: (json['rating'] as num).toDouble(),
      isOpen24h: json['isOpen24h'] ?? true,
      amenities: List<String>.from(json['amenities'] ?? []),
      distanceKm: json['distanceKm']?.toString(),
    );
  }
}

class Connector {
  final String id;
  final String stationId;
  final String connectorType;
  final double powerKw;
  final double pricePerKwh;
  final String status; // available, occupied, offline

  Connector({
    required this.id,
    required this.stationId,
    required this.connectorType,
    required this.powerKw,
    required this.pricePerKwh,
    required this.status,
  });

  factory Connector.fromJson(Map<String, dynamic> json) {
    return Connector(
      id: json['id'],
      stationId: json['stationId'],
      connectorType: json['connectorType'],
      powerKw: (json['powerKw'] as num).toDouble(),
      pricePerKwh: (json['pricePerKwh'] as num).toDouble(),
      status: json['status'],
    );
  }
}
