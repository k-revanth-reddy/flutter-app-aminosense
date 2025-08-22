import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const AmioSenseApp());
}

class AmioSenseApp extends StatelessWidget {
  const AmioSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amniosense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00F2FE), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0E1320),
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Segoe UI'),
      ),
      home: const DashboardPage(),
    );
  }
}

// --- Models ---
class SensorDatum {
  final String label;
  final double value;
  final DateTime timestamp;

  SensorDatum({required this.label, required this.value, required this.timestamp});

  factory SensorDatum.fromJson(Map<String, dynamic> json) {
    final rawVal = json['value'];
    final doubleVal = rawVal is num ? rawVal.toDouble() : double.tryParse(rawVal.toString()) ?? double.nan;
    return SensorDatum(
      label: json['label']?.toString() ?? '-',
      value: doubleVal,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

// --- API Service ---
class ApiService {
  static final Uri _endpoint = Uri.parse('https://majestic-minds-api.onrender.com/get-data');

  static Future<List<SensorDatum>> fetchData() async {
    final res = await http.get(_endpoint, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    return body.map((e) => SensorDatum.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// --- Utilities ---
String normalizeLabel(String raw) {
  if (raw.isEmpty) return raw;
  final s = raw.toLowerCase();
  return s[0].toUpperCase() + s.substring(1);
}

bool isTargetSensor(String label) {
  final s = label.toLowerCase();
  return s == 'temperature' || s == 'moisture';
}

const unitsMap = {
  'Temperature': '°C',
  'Moisture': 'units',
  'temperature': '°C',
  'moisture': 'units',
};

// --- Dashboard Page ---
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Map<String, List<SensorDatum>> _history = {
    'Temperature': <SensorDatum>[],
    'Moisture': <SensorDatum>[],
  };

  DateTime? _lastUpdated;
  Timer? _liveTimer;
  Timer? _chartTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _updateLiveData();
    _updateCharts();
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _updateLiveData());
    _chartTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateCharts());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _chartTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateLiveData() async {
    try {
      final all = await ApiService.fetchData();
      final filtered = all.where((d) => isTargetSensor(d.label)).toList();
      final Map<String, SensorDatum> latest = {};
      for (final d in filtered) {
        final k = normalizeLabel(d.label);
        final prev = latest[k];
        if (prev == null || d.timestamp.isAfter(prev.timestamp)) {
          latest[k] = d;
        }
      }
      for (final entry in latest.entries) {
        final label = normalizeLabel(entry.key);
        final list = _history[label] ??= <SensorDatum>[];
        list.add(entry.value);
        if (list.length > 200) {
          list.removeRange(0, list.length - 200);
        }
      }
      setState(() {
        _lastUpdated = latest.values.isEmpty
            ? _lastUpdated
            : latest.values.map((e) => e.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _updateCharts() async {
    try {
      final all = await ApiService.fetchData();
      final filtered = all.where((d) => isTargetSensor(d.label)).toList();
      final Map<String, List<SensorDatum>> grouped = {};
      for (final d in filtered) {
        final k = normalizeLabel(d.label);
        (grouped[k] ??= <SensorDatum>[]).add(d);
      }
      for (final e in grouped.entries) {
        e.value.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final recent = e.value.length > 50 ? e.value.sublist(e.value.length - 50) : e.value;
        final list = _history[e.key] ??= <SensorDatum>[];
        list
          ..clear()
          ..addAll(recent);
      }
      setState(() {
        _error = null;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy • HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.65),
        elevation: 0,
        title: const Text('Amniosense'),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: () {
              _updateLiveData();
              _updateCharts();
            },
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Smart IoT dashboard for Temperature & Moisture',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                // Live Data Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_outlined),
                          const SizedBox(width: 8),
                          Text('Live Data', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                      else if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text('Error: $_error', style: const TextStyle(color: Colors.redAccent)),
                        )
                      else
                        Wrap(
                          runSpacing: 8,
                          spacing: 8,
                          children: [
                            _buildLiveChip('Temperature'),
                            _buildLiveChip('Moisture'),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Last updated: ${_lastUpdated == null ? '-' : dateFmt.format(_lastUpdated!)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Charts Card
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.show_chart),
                          const SizedBox(width: 8),
                          Text('Live Graphs', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(height: 220, child: _buildChart('Temperature')),
                      const SizedBox(height: 16),
                      SizedBox(height: 220, child: _buildChart('Moisture')),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    '© 2025 Amniosense | Empowering Maternal Health with IoT',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Widgets helpers ---
  Widget _buildLiveChip(String label) {
    final list = _history[label] ?? [];
    final latest = list.isNotEmpty ? list.last : null;
    final unit = unitsMap[label] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(width: 4, color: Colors.cyanAccent.shade100)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Text(
        latest == null
            ? '$label: -'
            : '$label: ${latest.value.toStringAsFixed(2)} $unit',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildChart(String label) {
    final data = _history[label] ?? [];
    if (data.isEmpty) {
      return const Center(child: Text('No data yet'));
    }

    // Use index as X instead of timestamp differences (cleaner)
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].value));
    }

    return LineChart(
      LineChartData(
        minY: _minY(spots),
        maxY: _maxY(spots),
        gridData: FlGridData(
          show: true,
          horizontalInterval: ((_maxY(spots) - _minY(spots)) / 5).clamp(1, 50),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white24,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (spots.length / 5).ceilToDouble(),
              getTitlesWidget: (v, meta) {
                final idx = v.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                return Text(
                  DateFormat('HH:mm').format(data[idx].timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: label == 'Temperature' ? Colors.orangeAccent : Colors.cyanAccent,
            dotData: const FlDotData(show: false),
            barWidth: 2,
            belowBarData: BarAreaData(
              show: true,
              color: (label == 'Temperature'
                      ? Colors.orangeAccent
                      : Colors.cyanAccent)
                  .withOpacity(0.2),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  double _minY(List<FlSpot> s) {
    if (s.isEmpty) return 0;
    final values = s.map((e) => e.y).toList();
    values.sort();
    final min = values.first;
    final max = values.last;
    final pad = (max - min).abs() * 0.15 + 0.5;
    return min - pad;
  }

  double _maxY(List<FlSpot> s) {
    if (s.isEmpty) return 0;
    final values = s.map((e) => e.y).toList();
    values.sort();
    final min = values.first;
    final max = values.last;
    final pad = (max - min).abs() * 0.15 + 0.5;
    return max + pad;
  }
}

// --- Glassmorphism Card ---
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
