import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn directions to [lat]/[lng] in the device's Google Maps
/// app (falls back to the browser if it isn't installed).
Future<void> openDirections(double lat, double lng) {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
