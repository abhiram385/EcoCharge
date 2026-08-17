class SwapPoint {
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

  SwapPoint({
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

  factory SwapPoint.fromJson(Map<String, dynamic> json) {
    return SwapPoint(
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

class SwapPack {
  final String id;
  final String swapPointId;
  final String packType;
  final double capacityKwh;
  final double pricePerSwap;
  final int availableCount;
  final int totalCount;

  SwapPack({
    required this.id,
    required this.swapPointId,
    required this.packType,
    required this.capacityKwh,
    required this.pricePerSwap,
    required this.availableCount,
    required this.totalCount,
  });

  bool get inStock => availableCount > 0;

  factory SwapPack.fromJson(Map<String, dynamic> json) {
    return SwapPack(
      id: json['id'],
      swapPointId: json['swapPointId'],
      packType: json['packType'],
      capacityKwh: (json['capacityKwh'] as num).toDouble(),
      pricePerSwap: (json['pricePerSwap'] as num).toDouble(),
      availableCount: json['availableCount'] as int,
      totalCount: json['totalCount'] as int,
    );
  }
}

class SwapRecord {
  final String id;
  final String swapPointName;
  final String packType;
  final double capacityKwh;
  final double cost;
  final DateTime createdAt;

  SwapRecord({
    required this.id,
    required this.swapPointName,
    required this.packType,
    required this.capacityKwh,
    required this.cost,
    required this.createdAt,
  });

  factory SwapRecord.fromJson(Map<String, dynamic> json) {
    return SwapRecord(
      id: json['id'],
      swapPointName: json['swapPointName'] ?? '',
      packType: json['packType'],
      capacityKwh: (json['capacityKwh'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
