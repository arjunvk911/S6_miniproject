import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CitizenMapTab extends StatefulWidget {
  const CitizenMapTab({super.key});
  @override
  State<CitizenMapTab> createState() => _CitizenMapTabState();
}

class _CitizenMapTabState extends State<CitizenMapTab> {
  List<Map<String, dynamic>> _reports = [];
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('my_reports') ?? [];
    setState(() {
      _reports = raw
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .where((r) => r['latitude'] != null && r['longitude'] != null)
          .toList();
    });
  }

  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final markers = _reports.map((r) {
      final lat = (r['latitude'] is double)
          ? r['latitude'] as double
          : double.tryParse(r['latitude'].toString()) ?? 0.0;
      final lng = (r['longitude'] is double)
          ? r['longitude'] as double
          : double.tryParse(r['longitude'].toString()) ?? 0.0;
      final sev = r['severity'] as String? ?? 'NONE';
      final color = _sevColor(sev);

      return Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showDetail(context, r),
          child: Tooltip(
            message: 'Report #${r['report_id']} [$sev]\n$lat, $lng',
            child: Icon(Icons.location_pin, color: color, size: 36),
          ),
        ),
      );
    }).toList();

    final center = _reports.isNotEmpty
        ? LatLng(
            ((_reports.first['latitude'] is double)
                ? _reports.first['latitude'] as double
                : double.tryParse(
                        _reports.first['latitude'].toString()) ??
                    9.49),
            ((_reports.first['longitude'] is double)
                ? _reports.first['longitude'] as double
                : double.tryParse(
                        _reports.first['longitude'].toString()) ??
                    76.33),
          )
        : const LatLng(9.49, 76.33);

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No GPS reports yet',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const Text('Submit a report with location to see it here',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: center, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pothole.app',
            ),
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
                  const Text('Legend',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  _legendRow(Colors.red, 'HIGH'),
                  _legendRow(Colors.orange, 'MEDIUM'),
                  _legendRow(Colors.green, 'LOW'),
                ],
              ),
            ),
          ),
        ),
        // Refresh
        Positioned(
          top: 12,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'citizen_map_refresh',
            onPressed: _load,
            child: const Icon(Icons.refresh),
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

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReportDetailSheet(report: r),
    );
  }
}

class _ReportDetailSheet extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportDetailSheet({required this.report});

  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final sev = report['severity'] as String? ?? 'NONE';
    final color = _sevColor(sev);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.warning_rounded, color: color, size: 28),
            const SizedBox(width: 8),
            Text('Report #${report['report_id'] ?? '—'}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Chip(
              label: Text(sev,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              backgroundColor: color.withOpacity(0.15),
            ),
          ]),
          const Divider(height: 24),
          _row('Potholes', '${report['total'] ?? 0}'),
          _row('Status', report['status'] ?? 'Pending'),
          _row(
              'GPS',
              report['latitude'] != null
                  ? '${report['latitude']}, ${report['longitude']}'
                  : 'N/A'),
          _row(
              'Submitted',
              report['timestamp']?.toString().substring(0, 16) ?? '—'),
          _row('Saved to DB', report['saved_to_db'] == true ? 'Yes ✅' : 'No'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(color: Colors.grey)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
