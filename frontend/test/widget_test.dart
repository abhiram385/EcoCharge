import 'package:flutter_test/flutter_test.dart';

import 'package:ecocharge/data/vehicle_catalog.dart';

void main() {
  test('vehicle catalog includes swap-capable entries', () {
    expect(kVehicleCatalog, isNotEmpty);
    expect(kVehicleCatalog.any((v) => v.swapCapable), isTrue);
    expect(kVehicleCatalog.every((v) => v.capacityKwh > 0), isTrue);
  });
}
