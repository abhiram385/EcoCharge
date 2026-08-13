/// Static, hardcoded catalog of common India-market EVs, used by the
/// vehicle-selection UI (Profile "Add vehicle" and the Charge Now flow).
/// No external API — capacities were verified against public specs as of
/// August 2026 and are the base/current India-market trim where a model
/// has multiple battery options.
class VehicleCatalogEntry {
  final String make;
  final String model;
  final double capacityKwh;
  final String connectorType;

  const VehicleCatalogEntry({
    required this.make,
    required this.model,
    required this.capacityKwh,
    required this.connectorType,
  });

  String get displayName => '$make $model';
}

const List<VehicleCatalogEntry> kVehicleCatalog = [
  // Cars
  VehicleCatalogEntry(make: 'Tata', model: 'Tiago EV', capacityKwh: 24, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Punch EV', capacityKwh: 35, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Nexon EV', capacityKwh: 40.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Curvv EV', capacityKwh: 55, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'XUV400', capacityKwh: 39.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'BE 6', capacityKwh: 79, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'XEV 9e', capacityKwh: 79, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'Comet EV', capacityKwh: 17.3, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'ZS EV', capacityKwh: 50.3, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'Windsor EV', capacityKwh: 52.9, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Kona Electric', capacityKwh: 39.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Ioniq 5', capacityKwh: 72.6, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Creta Electric', capacityKwh: 51.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'Atto 3', capacityKwh: 60.5, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'Seal', capacityKwh: 82.5, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'eMax 7', capacityKwh: 71.8, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Citroen', model: 'eC3', capacityKwh: 29.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Maruti Suzuki', model: 'e Vitara', capacityKwh: 61, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Kia', model: 'EV6', capacityKwh: 77.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Kia', model: 'Syros EV', capacityKwh: 51.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Volvo', model: 'EX30', capacityKwh: 69, connectorType: 'CCS2'),
  // Two-wheelers
  VehicleCatalogEntry(make: 'Ola', model: 'S1 Pro', capacityKwh: 4, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'Ather', model: '450X', capacityKwh: 3.7, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'TVS', model: 'iQube', capacityKwh: 3.04, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'Bajaj', model: 'Chetak', capacityKwh: 3, connectorType: 'Type2'),
];
