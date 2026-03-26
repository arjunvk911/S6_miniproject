import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'theme_provider.dart';
import 'offline_queue.dart';
import 'notifications_service.dart';
import 'citizen_map_tab.dart';
import 'authority_map_tab.dart';
import 'analytics_tab.dart';
import 'community_tab.dart';

// ─────────────────────────────────────────────
// CONFIG — Your laptop IP
// ─────────────────────────────────────────────
//
// Option 1 (Easiest): Turn on your phone's Mobile Hotspot -> Connect laptop
//   to your phone -> Run `ipconfig` -> Paste the new IPv4 address here.
// Option 2 (Ngrok): Download ngrok.exe, run `ngrok http 8000`, and paste the
//   provided `.ngrok.io` URL below.
//
const String API_BASE = 'http://192.168.1.193:8000';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationsService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const PotholeApp(),
    ),
  );
}

class PotholeApp extends StatelessWidget {
  const PotholeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'PotholeWatch',
      debugShowCheckedModeBanner: false,
      themeMode: tp.mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ═══════════════════════════════════════
// LOGIN SCREEN
// ═══════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _role = 'citizen';
  bool _loading = false;
  bool _obscure = true;

  void _login() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 500));

    final u = _userCtrl.text.trim();
    final p = _passCtrl.text.trim();

    if (_role == 'authority' && u == 'admin' && p == 'pwd123') {
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const AuthorityScreen()));
    } else if (_role == 'citizen' && u == 'citizen' && p == 'user123') {
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const CitizenScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Invalid credentials!'),
          backgroundColor: Colors.red));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 16,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 12),
                    const Text('PotholeWatch',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const Text('Smart Road Monitoring System',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 24),

                    // Role selector
                    Row(children: [
                      Expanded(child: _roleBtn('citizen', '👤 Citizen')),
                      const SizedBox(width: 10),
                      Expanded(child: _roleBtn('authority', '🏛️ Authority')),
                    ]),
                    const SizedBox(height: 20),

                    // Username
                    TextField(
                      controller: _userCtrl,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        filled: true,
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 20),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _role == 'authority'
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(
                                _role == 'authority'
                                    ? 'Login as Authority'
                                    : 'Login as Citizen',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Demo creds
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🔑 Demo Credentials',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 6),
                          Text('Authority: admin / pwd123',
                              style: TextStyle(
                                  fontSize: 12, fontFamily: 'monospace')),
                          Text('Citizen:   citizen / user123',
                              style: TextStyle(
                                  fontSize: 12, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleBtn(String role, String label) {
    final selected = _role == role;
    final color = role == 'authority'
        ? const Color(0xFF2563EB)
        : const Color(0xFF7C3AED);
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? color : Colors.grey)),
      ),
    );
  }
}

// ═══════════════════════════════════════
// CITIZEN SCREEN  (3 tabs)
// ═══════════════════════════════════════
class CitizenScreen extends StatefulWidget {
  const CitizenScreen({super.key});
  @override
  State<CitizenScreen> createState() => _CitizenScreenState();
}

class _CitizenScreenState extends State<CitizenScreen> {
  int _tab = 0;
  final _communityKey = GlobalKey<CommunityTabState>();

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        title: const Text('PotholeWatch — Citizen',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // Dark mode toggle
          IconButton(
            icon: Icon(
                tp.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: tp.isDark ? 'Light Mode' : 'Dark Mode',
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const ReportPotholeTab(),
          const MyReportsTab(),
          const CitizenMapTab(),
          CommunityTab(key: _communityKey, apiBase: API_BASE),
        ],
      ),
      floatingActionButton: _tab == 3
          ? FloatingActionButton.extended(
              heroTag: 'add_review_fab',
              onPressed: () =>
                  _communityKey.currentState?.openAddReview(),
              icon: const Icon(Icons.rate_review),
              label: const Text('Add Review'),
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: const Color(0xFF7C3AED),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt), label: 'Report'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list), label: 'My Reports'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.people), label: 'Community'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════
// REPORT POTHOLE TAB
// ═══════════════════════════════════════
class ReportPotholeTab extends StatefulWidget {
  const ReportPotholeTab({super.key});
  @override
  State<ReportPotholeTab> createState() => _ReportPotholeTabState();
}

class _ReportPotholeTabState extends State<ReportPotholeTab> {
  File? _image;
  String? _lat, _lng;
  bool _loading = false;
  Map<String, dynamic>? _result;
  final _picker = ImagePicker();
  int _queuedCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
    _listenConnectivity();
  }

  Future<void> _refreshQueueCount() async {
    final c = await OfflineQueue.count();
    if (mounted) setState(() => _queuedCount = c);
  }

  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) async {
      final online = result.any((r) => r != ConnectivityResult.none);
      if (online) {
        final sent = await OfflineQueue.flushToServer(API_BASE);
        if (sent > 0) {
          await NotificationsService.showQueueFlushed(sent);
          _refreshQueueCount();
        }
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked =
        await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _image = File(picked.path);
        _result = null;
      });
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await _picker.pickVideo(source: source);
    if (picked != null) {
      setState(() {
        _image = File(picked.path);
        _result = null;
      });
    }
  }

  Future<void> _getLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    setState(() {
      _lat = pos.latitude.toStringAsFixed(6);
      _lng = pos.longitude.toStringAsFixed(6);
    });
    _show('📍 Location: $_lat, $_lng');
  }

  Future<void> _detect() async {
    if (_image == null) {
      _show('⚠️ Please select an image first');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    final online = connectivity.any((r) => r != ConnectivityResult.none);

    if (!online) {
      // Queue offline
      await OfflineQueue.enqueue(QueuedReport(
        imagePath: _image!.path,
        lat: _lat ?? '0',
        lng: _lng ?? '0',
        queuedAt: DateTime.now().toIso8601String(),
      ));
      await NotificationsService.showQueued();
      _show('📥 No Internet — report queued for later');
      _refreshQueueCount();
      setState(() => _loading = false);
      return;
    }

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$API_BASE/detect'));
      req.files.add(await http.MultipartFile.fromPath('file', _image!.path));
      req.fields['latitude'] = _lat ?? '0';
      req.fields['longitude'] = _lng ?? '0';

      final res = await req.send().timeout(const Duration(seconds: 15));
      final body = await res.stream.bytesToString();
      final data = jsonDecode(body);

      // Save to local prefs
      final prefs = await SharedPreferences.getInstance();
      final reports = prefs.getStringList('my_reports') ?? [];
      reports.insert(
          0,
          jsonEncode({
            ...data,
            'timestamp': DateTime.now().toIso8601String(),
          }));
      await prefs.setStringList('my_reports', reports.take(20).toList());

      setState(() => _result = data);
      _show('✅ ${data['total']} pothole(s) detected!');

      // Push notification
      await NotificationsService.showSubmitted(
        data['total'] as int? ?? 0,
        data['severity'] as String? ?? 'NONE',
      );
    } catch (e) {
      _show('⚠️ Backend offline — check main.py is running');
    }
    setState(() => _loading = false);
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Offline queue banner
        if (_queuedCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber),
            ),
            child: Row(children: [
              const Icon(Icons.offline_bolt, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_queuedCount report(s) queued — will send when online',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),

        const Text('📷 Report a Pothole',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Take a photo or upload from gallery',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),

        // Image buttons
        Row(children: [
          Expanded(
              child: ElevatedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
          )),
          const SizedBox(width: 10),
          Expanded(
              child: ElevatedButton.icon(
            onPressed: () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[700],
              foregroundColor: Colors.white,
            ),
          )),
        ]),
        const SizedBox(height: 10),

        // Video button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () => _pickVideo(ImageSource.gallery),
            icon: const Icon(Icons.videocam),
            label: const Text('Upload Dashcam Video (.mp4)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // File preview
        if (_image != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(
                  _image!.path.toLowerCase().endsWith('.mp4') ||
                          _image!.path.toLowerCase().endsWith('.mov')
                      ? Icons.video_file
                      : Icons.image,
                  color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_image!.path.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ] else
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No image selected',
                        style: TextStyle(color: Colors.grey)),
                  ]),
            ),
          ),
        const SizedBox(height: 14),

        // GPS
        OutlinedButton.icon(
          onPressed: _getLocation,
          icon: const Icon(Icons.gps_fixed),
          label: Text(_lat != null
              ? '📍 $_lat, $_lng'
              : '📍 Get My Location'),
        ),
        const SizedBox(height: 14),

        // Detect button
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _detect,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(_loading ? 'Detecting...' : '🔍 Detect & Submit Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        // Result
        if (_result != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _sevColor(_result!['severity']).withOpacity(0.1),
              border: Border.all(color: _sevColor(_result!['severity'])),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _result!['total'] > 0
                        ? '⚠️ ${_result!['total']} Pothole(s) Detected!'
                        : '✅ Road looks clear!',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _sevColor(_result!['severity'])),
                  ),
                  const SizedBox(height: 10),
                  _resultRow('Severity', _result!['severity'] ?? 'NONE'),
                  _resultRow(
                      'Report ID', '#${_result!['report_id'] ?? '—'}'),
                  _resultRow(
                      'Saved',
                      _result!['saved_to_db'] == true ? 'Yes ✅' : 'No'),
                ]),
          ),
        ],
      ]),
    );
  }

  Widget _resultRow(String key, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(key, style: const TextStyle(color: Colors.grey)),
        Text(val,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ]),
    );
  }
}

// ═══════════════════════════════════════
// MY REPORTS TAB  (with tappable detail sheet)
// ═══════════════════════════════════════
class MyReportsTab extends StatefulWidget {
  const MyReportsTab({super.key});
  @override
  State<MyReportsTab> createState() => _MyReportsTabState();
}

class _MyReportsTabState extends State<MyReportsTab> {
  List<Map<String, dynamic>> _reports = [];

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
          .map((r) => jsonDecode(r) as Map<String, dynamic>)
          .toList();
    });
  }

  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  void _showDetail(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _reportDetailSheet(r),
    );
  }

  Widget _reportDetailSheet(Map<String, dynamic> r) {
    final sev = r['severity'] as String? ?? 'NONE';
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
            Text('Report #${r['report_id'] ?? '—'}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Chip(
              label: Text(sev,
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.bold)),
              backgroundColor: color.withOpacity(0.15),
            ),
          ]),
          const Divider(height: 24),
          _detailRow('Potholes detected', '${r['total'] ?? 0}'),
          _detailRow('Status', r['status'] ?? 'Pending'),
          _detailRow(
              'GPS',
              r['latitude'] != null
                  ? '${r['latitude']}, ${r['longitude']}'
                  : 'N/A'),
          _detailRow(
              'Submitted at',
              r['timestamp']?.toString().substring(0, 16) ?? '—'),
          _detailRow(
              'Saved to DB', r['saved_to_db'] == true ? 'Yes ✅' : 'No'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(color: Colors.grey)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _reports.isEmpty
          ? const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('No reports yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text('Submit your first pothole report!',
                    style: TextStyle(color: Colors.grey)),
              ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reports.length,
              itemBuilder: (_, i) {
                final r = _reports[i];
                final sev = r['severity'] ?? 'NONE';
                final color = _sevColor(sev);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showDetail(r),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.2),
                        child: Icon(Icons.warning_rounded, color: color),
                      ),
                      title: Text(
                          '#${r['report_id'] ?? '—'}  •  $sev',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: color)),
                      subtitle: Text(
                          '${r['total'] ?? 0} pothole(s) • '
                          '${r['timestamp']?.toString().substring(0, 16) ?? '—'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              color: r['saved_to_db'] == true
                                  ? Colors.green
                                  : Colors.grey,
                              size: 12),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: Colors.grey, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
    );
  }
}

// ═══════════════════════════════════════
// AUTHORITY SCREEN  (4 tabs)
// ═══════════════════════════════════════
class AuthorityScreen extends StatefulWidget {
  const AuthorityScreen({super.key});
  @override
  State<AuthorityScreen> createState() => _AuthorityScreenState();
}

class _AuthorityScreenState extends State<AuthorityScreen> {
  List<dynamic> _reports = [];
  List<dynamic> _filtered = [];
  bool _loading = false;
  int _tab = 0;

  // Filter state
  String _filterSeverity = 'All';
  String _filterStatus = 'All';
  String _sortBy = 'Date ↓';

  static const _severities = ['All', 'HIGH', 'MEDIUM', 'LOW'];
  static const _statuses = ['All', 'Pending', 'Work in Progress', 'Repaired'];
  static const _sorts = ['Date ↓', 'Date ↑', 'Severity'];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('$API_BASE/reports'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      _reports = data['reports'] ?? [];
    } catch (e) {
      _reports = [
        {
          'id': 'demo1',
          'severity': 'HIGH',
          'total': 3,
          'status': 'Pending',
          'timestamp': DateTime.now().toIso8601String(),
          'latitude': 9.49,
          'longitude': 76.33
        },
        {
          'id': 'demo2',
          'severity': 'MEDIUM',
          'total': 1,
          'status': 'Work in Progress',
          'timestamp': DateTime.now().toIso8601String(),
          'latitude': 9.50,
          'longitude': 76.34
        },
        {
          'id': 'demo3',
          'severity': 'LOW',
          'total': 2,
          'status': 'Repaired',
          'timestamp': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'latitude': 9.51,
          'longitude': 76.35
        },
      ];
    }
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    var list = List<dynamic>.from(_reports);
    if (_filterSeverity != 'All') {
      list = list.where((r) => r['severity'] == _filterSeverity).toList();
    }
    if (_filterStatus != 'All') {
      list = list.where((r) => r['status'] == _filterStatus).toList();
    }
    switch (_sortBy) {
      case 'Date ↓':
        list.sort((a, b) =>
            (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
        break;
      case 'Date ↑':
        list.sort((a, b) =>
            (a['timestamp'] ?? '').compareTo(b['timestamp'] ?? ''));
        break;
      case 'Severity':
        const order = {'HIGH': 0, 'MEDIUM': 1, 'LOW': 2};
        list.sort((a, b) => (order[a['severity']] ?? 3)
            .compareTo(order[b['severity']] ?? 3));
        break;
    }
    setState(() => _filtered = list);
  }

  Future<void> _exportCsv() async {
    final rows = [
      ['ID', 'Severity', 'Potholes', 'Status', 'Lat', 'Lng', 'Timestamp'],
      ..._reports.map((r) => [
            r['id'] ?? '',
            r['severity'] ?? '',
            r['total'] ?? 0,
            r['status'] ?? '',
            r['latitude'] ?? '',
            r['longitude'] ?? '',
            r['timestamp'] ?? '',
          ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pothole_reports.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'PotholeWatch Reports Export',
      text: 'Exported ${_reports.length} pothole report(s)',
    );
  }

  Future<void> _deleteReport(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text(
            'Are you sure you want to permanently delete this report?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await http.delete(Uri.parse('$API_BASE/reports/$id'));
      if (res.statusCode == 200) {
        setState(() {
          _reports.removeWhere((r) => r['id'] == id);
          _applyFilters();
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🗑️ Report permanently deleted!'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ Network error deleting report'),
          backgroundColor: Colors.orange));
    }
  }

  Color _sevColor(String? sev) {
    if (sev == 'HIGH') return Colors.red;
    if (sev == 'MEDIUM') return Colors.orange;
    if (sev == 'LOW') return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        title: const Text('PotholeWatch — Authority',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export CSV',
              onPressed: _exportCsv),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReports),
          IconButton(
            icon: Icon(tp.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: tp.isDark ? 'Light Mode' : 'Dark Mode',
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _tab,
              children: [
                _reportsTab(),
                AnalyticsTab(reports: _reports),
                AuthorityMapTab(reports: _reports),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: const Color(0xFF2563EB),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Reports'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Analytics'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map), label: 'Heatmap'),
        ],
      ),
    );
  }

  Widget _reportsTab() {
    final high = _reports.where((r) => r['severity'] == 'HIGH').length;
    final medium = _reports.where((r) => r['severity'] == 'MEDIUM').length;
    final low = _reports.where((r) => r['severity'] == 'LOW').length;

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stats
              Row(children: [
                _statCard('Total', '${_reports.length}', Colors.blue),
                const SizedBox(width: 8),
                _statCard('HIGH', '$high', Colors.red),
                const SizedBox(width: 8),
                _statCard('MED', '$medium', Colors.orange),
                const SizedBox(width: 8),
                _statCard('LOW', '$low', Colors.green),
              ]),
              const SizedBox(height: 16),

              // ── Filter chips ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  const Text('Severity: ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  ..._severities.map((s) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: _filterSeverity == s,
                          onSelected: (_) {
                            setState(() => _filterSeverity = s);
                            _applyFilters();
                          },
                          selectedColor: _sevColor(s).withOpacity(0.25),
                        ),
                      )),
                ]),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  const Text('Status: ',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  ..._statuses.map((s) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: _filterStatus == s,
                          onSelected: (_) {
                            setState(() => _filterStatus = s);
                            _applyFilters();
                          },
                        ),
                      )),
                ]),
              ),
              const SizedBox(height: 6),
              // Sort row
              Row(children: [
                const Text('Sort: ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
                ..._sorts.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: _sortBy == s,
                        onSelected: (_) {
                          setState(() => _sortBy = s);
                          _applyFilters();
                        },
                      ),
                    )),
              ]),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('📋 Reports (${_filtered.length})',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),

              if (_filtered.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No reports match filters',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ..._filtered.map((r) {
                  final sev = r['severity'] ?? 'NONE';
                  final color = _sevColor(sev);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(children: [
                                    Text('#${r['id']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Colors.redAccent),
                                      onPressed: () =>
                                          _deleteReport(r['id']),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ]),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(sev,
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ),
                                ]),
                            const SizedBox(height: 8),
                            Text(
                                '${r['total'] ?? 0} pothole(s) detected',
                                style:
                                    const TextStyle(color: Colors.grey)),
                            Text(
                              r['latitude'] != null
                                  ? '📍 ${(r['latitude'] as num).toStringAsFixed(4)}, ${(r['longitude'] as num).toStringAsFixed(4)}'
                                  : '📍 No GPS',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: r['status'] ?? 'Pending',
                              decoration: InputDecoration(
                                labelText: 'Status',
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                isDense: true,
                              ),
                              items: [
                                'Pending',
                                'Work in Progress',
                                'Repaired'
                              ]
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (val) async {
                                if (val == null) return;
                                try {
                                  await http.put(Uri.parse(
                                      '$API_BASE/reports/${r['id']}/status?status=${Uri.encodeComponent(val)}'));
                                  await NotificationsService
                                      .showStatusChange(
                                          '${r['id']}', val);
                                  _loadReports();
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                '⚠️ Backend offline')));
                                  }
                                }
                              },
                            ),
                          ]),
                    ),
                  );
                }),
            ]),
      ),
    );
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
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}
