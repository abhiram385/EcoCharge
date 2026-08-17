-- Demo seed data centered around Bhopal, MP for local testing.
-- Feel free to replace with real station data per city.

INSERT INTO stations (name, address, city, latitude, longitude, rating, is_open_24h, amenities)
VALUES
 ('Arera Colony Green Hub', 'E-8 Arera Colony', 'Bhopal', 23.2260, 77.4360, 4.7, TRUE, ARRAY['Cafe','Restroom','WiFi']),
 ('DB City Charge Point', 'DB City Mall, Zone-I', 'Bhopal', 23.2340, 77.4090, 4.5, TRUE, ARRAY['Mall','Restroom']),
 ('MP Nagar Fast Charge', 'Zone II, MP Nagar', 'Bhopal', 23.2350, 77.4340, 4.3, TRUE, ARRAY['Cafe']),
 ('Kolar Road Station', 'Kolar Road', 'Bhopal', 23.1850, 77.4230, 4.2, FALSE, ARRAY['Restroom']),
 ('Habibganj Rail Charge', 'Near Habibganj Station', 'Bhopal', 23.2140, 77.4360, 4.6, TRUE, ARRAY['WiFi','Restroom','Cafe'])
ON CONFLICT DO NOTHING;

-- Attach a couple of connectors to each station
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 18.50, 'available' FROM stations WHERE name = 'Arera Colony Green Hub';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.00, 'available' FROM stations WHERE name = 'Arera Colony Green Hub';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 19.00, 'occupied' FROM stations WHERE name = 'DB City Charge Point';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CHAdeMO', 50, 19.00, 'available' FROM stations WHERE name = 'DB City Charge Point';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 13.50, 'available' FROM stations WHERE name = 'MP Nagar Fast Charge';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 30, 16.00, 'offline' FROM stations WHERE name = 'Kolar Road Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 120, 21.00, 'available' FROM stations WHERE name = 'Habibganj Rail Charge';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.50, 'available' FROM stations WHERE name = 'Habibganj Rail Charge';

-- Battery swap points (fake data) — for lightweight two-wheelers (Type2
-- pack class) that swap instead of charge.
INSERT INTO swap_points (name, address, city, latitude, longitude, rating, is_open_24h, amenities)
VALUES
 ('New Market Swap Hub', '11 New Market', 'Bhopal', 23.2599, 77.4014, 4.6, TRUE, ARRAY['Restroom','WiFi']),
 ('Bittan Market Swap Point', 'Bittan Market', 'Bhopal', 23.2280, 77.4380, 4.4, TRUE, ARRAY['Cafe']),
 ('Ashoka Garden Swap Point', 'Ashoka Garden', 'Bhopal', 23.2450, 77.4460, 4.3, FALSE, ARRAY['Restroom']),
 ('Board Office Swap Hub', 'Board Office Square', 'Bhopal', 23.2320, 77.4160, 4.7, TRUE, ARRAY['Cafe','WiFi'])
ON CONFLICT DO NOTHING;

INSERT INTO swap_packs (swap_point_id, pack_type, capacity_kwh, price_per_swap, available_count, total_count)
SELECT id, 'Type2', 3.5, 149.00, 6, 8 FROM swap_points WHERE name = 'New Market Swap Hub';
INSERT INTO swap_packs (swap_point_id, pack_type, capacity_kwh, price_per_swap, available_count, total_count)
SELECT id, 'Type2', 3.5, 149.00, 2, 6 FROM swap_points WHERE name = 'Bittan Market Swap Point';
INSERT INTO swap_packs (swap_point_id, pack_type, capacity_kwh, price_per_swap, available_count, total_count)
SELECT id, 'Type2', 3.5, 159.00, 0, 5 FROM swap_points WHERE name = 'Ashoka Garden Swap Point';
INSERT INTO swap_packs (swap_point_id, pack_type, capacity_kwh, price_per_swap, available_count, total_count)
SELECT id, 'Type2', 3.5, 139.00, 9, 10 FROM swap_points WHERE name = 'Board Office Swap Hub';
