import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class QueuedReport {
  final String imagePath;
  final String lat;
  final String lng;
  final String queuedAt;

  QueuedReport({
    required this.imagePath,
    required this.lat,
    required this.lng,
    required this.queuedAt,
  });

  Map<String, String> toMap() => {
        'imagePath': imagePath,
        'lat': lat,
        'lng': lng,
        'queuedAt': queuedAt,
      };

  factory QueuedReport.fromMap(Map<String, dynamic> m) => QueuedReport(
        imagePath: m['imagePath'] ?? '',
        lat: m['lat'] ?? '0',
        lng: m['lng'] ?? '0',
        queuedAt: m['queuedAt'] ?? '',
      );
}

class OfflineQueue {
  static const _key = 'offline_queue';

  static Future<List<QueuedReport>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => QueuedReport.fromMap(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> enqueue(QueuedReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(report.toMap()));
    await prefs.setStringList(_key, raw);
  }

  static Future<int> flushToServer(String apiBase) async {
    final queue = await getAll();
    if (queue.isEmpty) return 0;

    int sent = 0;
    final remaining = <QueuedReport>[];

    for (final report in queue) {
      final file = File(report.imagePath);
      if (!file.existsSync()) continue; // skip if file gone

      try {
        final req =
            http.MultipartRequest('POST', Uri.parse('$apiBase/detect'));
        req.files.add(await http.MultipartFile.fromPath('file', report.imagePath));
        req.fields['latitude'] = report.lat;
        req.fields['longitude'] = report.lng;
        final res = await req.send().timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          sent++;
        } else {
          remaining.add(report);
        }
      } catch (_) {
        remaining.add(report);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, remaining.map((r) => jsonEncode(r.toMap())).toList());
    return sent;
  }

  static Future<int> count() async {
    final q = await getAll();
    return q.length;
  }
}
