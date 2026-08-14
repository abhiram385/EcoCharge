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

-- Real, currently-operational Hyderabad EV charging stations (name, address,
-- and coordinates sourced from the Google Places API; connector types,
-- power, pricing, and status are not available from Places and are
-- app-invented, matching the style of the demo stations above).
INSERT INTO stations (name, address, city, latitude, longitude, rating, is_open_24h, amenities)
VALUES
 ('Tata Power Charging Station', '1, Greenlands Rd, Nishat Bagh Colony, Somajiguda', 'Hyderabad', 17.4298154, 78.4564473, 4.4, TRUE, ARRAY['WiFi']),
 ('EV DOCK Charging Station', 'Bhaskar Plaza, Road No. 1, Banjara Hills', 'Hyderabad', 17.4120536, 78.4500953, 4.0, FALSE, ARRAY['Restroom']),
 ('Zeon Charging Station', 'Ashoka One Mall, Road Number 3, Kukatpally', 'Hyderabad', 17.4794297, 78.4177705, 4.9, TRUE, ARRAY['Mall','Restroom','Cafe']),
 ('LionCharge Charging Station', 'BD Colony, Kundanbagh Colony, Begumpet', 'Hyderabad', 17.4365936, 78.4567269, 5.0, TRUE, ARRAY['WiFi']),
 ('Reliable Charge EV Charging Station', 'Central Mall, Somajiguda', 'Hyderabad', 17.4267023, 78.4530281, 4.2, TRUE, ARRAY['Mall','Restroom']),
 ('Thunder Plus Charging Station', 'Secunderabad Railway Station parking, Khairtabad', 'Hyderabad', 17.4242015, 78.4629467, 3.0, TRUE, ARRAY['Restroom']),
 ('Tata Power Charging Station (Gateway Mall)', 'B1-Level, Gateway Mall, IDA Kukatpally', 'Hyderabad', 17.476998, 78.42272100000001, 5.0, TRUE, ARRAY['Mall','Cafe','Restroom']),
 ('ChargeZone', 'Hyderabad Marriott Hotel, Tank Bund Rd', 'Hyderabad', 17.4252119, 78.4869532, 4.0, TRUE, ARRAY['Cafe','WiFi'])
ON CONFLICT DO NOTHING;

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 19.00, 'available' FROM stations WHERE name = 'Tata Power Charging Station';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.50, 'available' FROM stations WHERE name = 'Tata Power Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 18.00, 'available' FROM stations WHERE name = 'EV DOCK Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 20.00, 'occupied' FROM stations WHERE name = 'Zeon Charging Station';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 15.00, 'available' FROM stations WHERE name = 'Zeon Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 18.50, 'available' FROM stations WHERE name = 'LionCharge Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.00, 'available' FROM stations WHERE name = 'Reliable Charge EV Charging Station';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 40, 17.50, 'offline' FROM stations WHERE name = 'Reliable Charge EV Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 30, 16.50, 'available' FROM stations WHERE name = 'Thunder Plus Charging Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 19.00, 'available' FROM stations WHERE name = 'Tata Power Charging Station (Gateway Mall)';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 19.50, 'available' FROM stations WHERE name = 'ChargeZone';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CHAdeMO', 50, 19.50, 'available' FROM stations WHERE name = 'ChargeZone';
