import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class AnalyticsTab extends StatelessWidget {
  final List<dynamic> reports;
  const AnalyticsTab({super.key, required this.reports});

  int _count(String sev) =>
      reports.where((r) => r['severity'] == sev).length;

  Map<String, int> _reportsPerDay() {
    final Map<String, int> map = {};
    for (final r in reports) {
      final ts = r['timestamp'] as String? ?? '';
      if (ts.length >= 10) {
        final day = ts.substring(0, 10);
        map[day] = (map[day] ?? 0) + 1;
      }
    }
    return map;
  }

  Map<String, int> _statusCounts() {
    final Map<String, int> map = {};
    for (final r in reports) {
      final s = r['status'] as String? ?? 'Pending';
      map[s] = (map[s] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final high = _count('HIGH');
    final medium = _count('MEDIUM');
    final low = _count('LOW');
    final total = reports.length;
    final statusMap = _statusCounts();
    final dayMap = _reportsPerDay();

    final sortedDays = dayMap.keys.toList()..sort();
    final last7 = sortedDays.length > 7
        ? sortedDays.sublist(sortedDays.length - 7)
        : sortedDays;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('📊 Analytics Dashboard',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Total reports: $total',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          // ─── Severity Bar Chart ───
          _sectionHeader('Potholes by Severity'),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: total == 0
                ? const Center(child: Text('No data yet', style: TextStyle(color: Colors.grey)))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (total.toDouble() * 1.2).clamp(4, double.infinity),
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              const labels = ['HIGH', 'MED', 'LOW'];
                              final i = v.toInt();
                              if (i < 0 || i >= labels.length) return const Text('');
                              return Text(labels[i],
                                  style: const TextStyle(fontSize: 11));
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(show: true),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        _bar(0, high.toDouble(), Colors.red),
                        _bar(1, medium.toDouble(), Colors.orange),
                        _bar(2, low.toDouble(), Colors.green),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          // ─── Reports Over Time Line Chart ───
          _sectionHeader('Reports Over Last ${last7.length} Days'),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: last7.isEmpty
                ? const Center(child: Text('No data yet', style: TextStyle(color: Colors.grey)))
                : LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: last7.asMap().entries.map((e) {
                            return FlSpot(
                                e.key.toDouble(),
                                (dayMap[e.value] ?? 0).toDouble());
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFF2563EB),
                          barWidth: 3,
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF2563EB).withOpacity(0.15),
                          ),
                          dotData: const FlDotData(show: true),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= last7.length) return const Text('');
                              final d = last7[i];
                              return Text(d.substring(5),  // MM-DD
                                  style: const TextStyle(fontSize: 9));
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(show: true),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          // ─── Status breakdown ───
          _sectionHeader('Reports by Status'),
          const SizedBox(height: 12),
          if (statusMap.isEmpty)
            const Center(child: Text('No data yet', style: TextStyle(color: Colors.grey)))
          else
            ...statusMap.entries.map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              final color = e.key == 'Repaired'
                  ? Colors.green
                  : e.key == 'Work in Progress'
                      ? Colors.orange
                      : Colors.red;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key),
                        Text('${e.value} (${(pct * 100).toStringAsFixed(0)}%)'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 10,
                        color: color,
                        backgroundColor: color.withOpacity(0.15),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 24),

          // ─── Summary cards ───
          _sectionHeader('Quick Stats'),
          const SizedBox(height: 12),
          Row(children: [
            _statCard('Total\nReports', '$total', Colors.blue),
            const SizedBox(width: 8),
            _statCard('Repaired', '${statusMap['Repaired'] ?? 0}', Colors.green),
            const SizedBox(width: 8),
            _statCard('Pending', '${statusMap['Pending'] ?? 0}', Colors.red),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  BarChartGroupData _bar(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 32,
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 0,
            color: color.withOpacity(0.1),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title,
        style:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}
