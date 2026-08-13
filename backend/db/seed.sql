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
