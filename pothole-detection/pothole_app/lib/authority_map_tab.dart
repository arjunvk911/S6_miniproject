import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AuthorityMapTab extends StatefulWidget {
  final List<dynamic> reports;
  const AuthorityMapTab({super.key, required this.reports});

  @override
  State<AuthorityMapTab> createState() => _AuthorityMapTabState();
}

class _AuthorityMapTabState extends State<AuthorityMapTab> {
  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  LatLng get _center {
    final withGps = widget.reports
        .where((r) => r['latitude'] != null && r['longitude'] != null)
        .toList();
    if (withGps.isEmpty) return const LatLng(9.49, 76.33);
    final lat = _toDouble(withGps.first['latitude']);
    final lng = _toDouble(withGps.first['longitude']);
    return LatLng(lat, lng);
  }

  double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final withGps = widget.reports
        .where((r) => r['latitude'] != null && r['longitude'] != null)
        .toList();

    if (withGps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No geotagged reports yet',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    final circles = withGps.map((r) {
      final lat = _toDouble(r['latitude']);
      final lng = _toDouble(r['longitude']);
      final sev = r['severity'] as String? ?? 'NONE';
      final color = _sevColor(sev);
      final total = (r['total'] as num? ?? 1).toDouble().clamp(1.0, 10.0);

      return CircleMarker(
        point: LatLng(lat, lng),
        radius: 12 + total * 4,
        color: color.withOpacity(0.35),
        borderColor: color,
        borderStrokeWidth: 2,
      );
    }).toList();

    final markers = withGps.map((r) {
      final lat = _toDouble(r['latitude']);
      final lng = _toDouble(r['longitude']);
      final sev = r['severity'] as String? ?? 'NONE';
      final color = _sevColor(sev);

      return Marker(
        point: LatLng(lat, lng),
        width: 36,
        height: 36,
        child: Tooltip(
          message:
              '#${r['id']} [$sev]\n${r['total']} pothole(s)\n${r['status'] ?? 'Pending'}',
          child: Icon(Icons.location_pin, color: color, size: 32),
        ),
      );
    }).toList();

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(initialCenter: _center, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pothole.app',
            ),
            CircleLayer(circles: circles),
            MarkerLayer(markers: markers),
          ],
        ),
        // Legend
        Positioned(
          bottom: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Heatmap Legend',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  _legendRow(Colors.red, 'HIGH severity'),
                  _legendRow(Colors.orange, 'MEDIUM severity'),
                  _legendRow(Colors.green, 'LOW severity'),
                  const SizedBox(height: 4),
                  const Text('Circle size = pothole count',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
        // Stats overlay
        Positioned(
          top: 12,
          left: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '${withGps.length} report(s) on map',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color c, String label) {
    return Row(children: [
      Icon(Icons.location_pin, color: c, size: 18),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}
