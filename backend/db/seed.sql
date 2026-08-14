-- Demo seed data centered around Hyderabad, Telangana for local testing.
-- Feel free to replace with real station data per city.

INSERT INTO stations (name, address, city, latitude, longitude, rating, is_open_24h, amenities)
VALUES
 ('Banjara Hills Green Hub', 'Road No. 12, Banjara Hills', 'Hyderabad', 17.4156, 78.4347, 4.7, TRUE, ARRAY['Cafe','Restroom','WiFi']),
 ('Hitech City Fast Charge', 'Near Cyber Towers, Hitech City', 'Hyderabad', 17.4435, 78.3772, 4.5, TRUE, ARRAY['Mall','Restroom']),
 ('Gachibowli Charge Point', 'DLF Cyber City, Gachibowli', 'Hyderabad', 17.4401, 78.3489, 4.3, TRUE, ARRAY['Cafe']),
 ('Jubilee Hills Station', 'Road No. 36, Jubilee Hills', 'Hyderabad', 17.4325, 78.4071, 4.2, FALSE, ARRAY['Restroom']),
 ('Secunderabad Rail Charge', 'Near Secunderabad Railway Station', 'Hyderabad', 17.4399, 78.5019, 4.6, TRUE, ARRAY['WiFi','Restroom','Cafe'])
ON CONFLICT DO NOTHING;

-- Attach a couple of connectors to each station
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 18.50, 'available' FROM stations WHERE name = 'Banjara Hills Green Hub';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.00, 'available' FROM stations WHERE name = 'Banjara Hills Green Hub';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 19.00, 'occupied' FROM stations WHERE name = 'Hitech City Fast Charge';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CHAdeMO', 50, 19.00, 'available' FROM stations WHERE name = 'Hitech City Fast Charge';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 13.50, 'available' FROM stations WHERE name = 'Gachibowli Charge Point';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 30, 16.00, 'offline' FROM stations WHERE name = 'Jubilee Hills Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 120, 21.00, 'available' FROM stations WHERE name = 'Secunderabad Rail Charge';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.50, 'available' FROM stations WHERE name = 'Secunderabad Rail Charge';
