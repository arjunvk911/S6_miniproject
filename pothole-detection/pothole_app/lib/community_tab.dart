import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────
class Review {
  final String id;
  final String author;
  final String message;
  final int rating; // 1–5
  final String category; // 'Review' | 'Complaint'
  final String timestamp;

  Review({
    required this.id,
    required this.author,
    required this.message,
    required this.rating,
    required this.category,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'author': author,
        'message': message,
        'rating': rating,
        'category': category,
        'timestamp': timestamp,
      };

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] ?? '',
        author: m['author'] ?? 'Anonymous',
        message: m['message'] ?? '',
        rating: m['rating'] as int? ?? 3,
        category: m['category'] ?? 'Review',
        timestamp: m['timestamp'] ?? '',
      );
}

// ─────────────────────────────────────────────
// COMMUNITY TAB  (stats + reviews/complaints)
// ─────────────────────────────────────────────
class CommunityTab extends StatefulWidget {
  final String apiBase;
  const CommunityTab({super.key, required this.apiBase});

  @override
  State<CommunityTab> createState() => CommunityTabState();
}

class CommunityTabState extends State<CommunityTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ── Stats state ──
  bool _statsLoading = false;
  int _total = 0, _repaired = 0, _pending = 0, _inProgress = 0;

  // ── Reviews state ──
  List<Review> _reviews = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadStats();
    _loadReviews();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ────────── Stats ──────────
  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final res = await http
          .get(Uri.parse('${widget.apiBase}/reports'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      final reports = data['reports'] as List? ?? [];
      setState(() {
        _total = reports.length;
        _repaired =
            reports.where((r) => r['status'] == 'Repaired').length;
        _inProgress =
            reports.where((r) => r['status'] == 'Work in Progress').length;
        _pending =
            reports.where((r) => r['status'] == 'Pending').length;
      });
    } catch (_) {
      // Show demo values if backend offline
      setState(() {
        _total = 12;
        _repaired = 5;
        _inProgress = 3;
        _pending = 4;
      });
    }
    setState(() => _statsLoading = false);
  }

  // ────────── Reviews ──────────
  static const _prefsKey = 'community_reviews';

  Future<void> _loadReviews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    setState(() {
      _reviews = raw
          .map((e) => Review.fromMap(jsonDecode(e) as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _saveReviews() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsKey, _reviews.map((r) => jsonEncode(r.toMap())).toList());
  }

  void openAddReview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddReviewSheet(
        onSubmit: (review) async {
          setState(() => _reviews.insert(0, review));
          await _saveReviews();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(review.category == 'Complaint'
                  ? '📢 Complaint submitted!'
                  : '⭐ Review submitted!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _deleteReview(String id) async {
    setState(() => _reviews.removeWhere((r) => r.id == id));
    await _saveReviews();
  }

  @override
  Widget build(BuildContext context) {
    final repairPct = _total > 0 ? _repaired / _total : 0.0;

    return Column(
      children: [
        // ── Tab bar ──
        Container(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            labelColor: const Color(0xFF7C3AED),
            indicatorColor: const Color(0xFF7C3AED),
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart), text: 'Public Stats'),
              Tab(icon: Icon(Icons.rate_review), text: 'Reviews'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // ── TAB 1: Stats ──
              _statsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadStats,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('🏘️ Community Road Watch',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text(
                                'Live stats from potholes reported in your area',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 20),

                            // ── Big stat cards ──
                            Row(children: [
                              _bigStat(
                                  '${_total}',
                                  'Total\nReported',
                                  Icons.report_problem,
                                  Colors.blue),
                              const SizedBox(width: 12),
                              _bigStat(
                                  '$_repaired',
                                  'Fixed &\nRepaired',
                                  Icons.check_circle,
                                  Colors.green),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              _bigStat(
                                  '$_inProgress',
                                  'Work in\nProgress',
                                  Icons.construction,
                                  Colors.orange),
                              const SizedBox(width: 12),
                              _bigStat(
                                  '$_pending',
                                  'Awaiting\nAction',
                                  Icons.hourglass_empty,
                                  Colors.red),
                            ]),
                            const SizedBox(height: 24),

                            // ── Repair progress ──
                            const Text('🔧 Overall Repair Progress',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: repairPct,
                                minHeight: 20,
                                color: Colors.green,
                                backgroundColor: Colors.green.withOpacity(0.15),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '${(repairPct * 100).toStringAsFixed(0)}% repaired',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green)),
                                Text('$_repaired of $_total fixed',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // ── Status breakdown ──
                            const Text('📊 Status Breakdown',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 12),
                            _statusBar('Repaired', _repaired, _total,
                                Colors.green, Icons.check_circle),
                            const SizedBox(height: 8),
                            _statusBar('Work in Progress', _inProgress,
                                _total, Colors.orange, Icons.construction),
                            const SizedBox(height: 8),
                            _statusBar('Awaiting Action', _pending, _total,
                                Colors.red, Icons.hourglass_empty),
                            const SizedBox(height: 24),

                            // ── Motivational message ──
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF7C3AED),
                                    Color(0xFF2563EB)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(children: [
                                const Icon(Icons.people,
                                    color: Colors.white, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                          'Together we make roads safer!',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                      Text(
                                          '$_total pothole(s) reported by citizens like you.',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),

              // ── TAB 2: Reviews & Complaints ──
              _reviews.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.rate_review,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('No reviews yet',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 16)),
                          const Text(
                              'Be the first to share your experience!',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: openAddReview,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Review'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Summary bar
                        _ReviewSummaryBar(reviews: _reviews),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _reviews.length,
                            itemBuilder: (_, i) => _ReviewCard(
                              review: _reviews[i],
                              onDelete: () => _deleteReview(_reviews[i].id),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bigStat(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(
      String label, int count, int total, Color color, IconData icon) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      SizedBox(
        width: 110,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 10,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('$count',
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]);
  }
}

// ─────────────────────────────────────────────
// REVIEW SUMMARY BAR
// ─────────────────────────────────────────────
class _ReviewSummaryBar extends StatelessWidget {
  final List<Review> reviews;
  const _ReviewSummaryBar({required this.reviews});

  @override
  Widget build(BuildContext context) {
    final avg = reviews.isEmpty
        ? 0.0
        : reviews.fold(0, (s, r) => s + r.rating) / reviews.length;
    final complaints =
        reviews.where((r) => r.category == 'Complaint').length;
    final revs = reviews.length - complaints;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(
              '${avg.toStringAsFixed(1)} ⭐', 'Avg Rating', Colors.amber),
          _summaryItem('$revs', 'Reviews', Colors.blue),
          _summaryItem('$complaints', 'Complaints', Colors.red),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label, Color color) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
    ]);
  }
}

// ─────────────────────────────────────────────
// INDIVIDUAL REVIEW CARD
// ─────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final Review review;
  final VoidCallback onDelete;
  const _ReviewCard({required this.review, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isComplaint = review.category == 'Complaint';
    final color = isComplaint ? Colors.red : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.15),
              child: Text(
                review.author.isNotEmpty ? review.author[0].toUpperCase() : '?',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(review.author,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      review.timestamp.length >= 16
                          ? review.timestamp.substring(0, 16)
                          : review.timestamp,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(review.category,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
            const SizedBox(width: 4),
            // Delete
            GestureDetector(
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete?'),
                    content: const Text(
                        'Remove this review/complaint?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) onDelete();
              },
              child: const Icon(Icons.close,
                  size: 16, color: Colors.grey),
            ),
          ]),
          const SizedBox(height: 10),
          // Stars
          Row(children: List.generate(
            5,
            (i) => Icon(
              i < review.rating ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 18,
            ),
          )),
          const SizedBox(height: 6),
          Text(review.message),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ADD REVIEW / COMPLAINT SHEET
// ─────────────────────────────────────────────
class _AddReviewSheet extends StatefulWidget {
  final Function(Review) onSubmit;
  const _AddReviewSheet({required this.onSubmit});

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _category = 'Review';
  int _rating = 4;

  void _submit() async {
    if (_msgCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please write a message first')));
      return;
    }
    final review = Review(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      author: _nameCtrl.text.trim().isEmpty
          ? 'Anonymous'
          : _nameCtrl.text.trim(),
      message: _msgCtrl.text.trim(),
      rating: _rating,
      category: _category,
      timestamp: DateTime.now().toIso8601String(),
    );
    Navigator.pop(context);
    await widget.onSubmit(review);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
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
          const Text('Share Your Feedback',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Category toggle
          Row(children: [
            Expanded(
              child: _catBtn('Review', Icons.star, Colors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _catBtn('Complaint', Icons.report, Colors.red),
            ),
          ]),
          const SizedBox(height: 16),

          // Name
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Your Name (optional)',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),

          // Star rating
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Rating:',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          Row(children: List.generate(5, (i) {
            return GestureDetector(
              onTap: () => setState(() => _rating = i + 1),
              child: Icon(
                i < _rating ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 36,
              ),
            );
          })),
          const SizedBox(height: 12),

          // Message
          TextField(
            controller: _msgCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _category == 'Complaint'
                  ? 'Describe your complaint...'
                  : 'Write your review...',
              prefixIcon: const Icon(Icons.edit),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: Icon(_category == 'Complaint'
                  ? Icons.report
                  : Icons.send),
              label: Text('Submit ${_category}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _category == 'Complaint'
                    ? Colors.red
                    : const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _catBtn(String cat, IconData icon, Color color) {
    final selected = _category == cat;
    return GestureDetector(
      onTap: () => setState(() => _category = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          border:
              Border.all(color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? color : Colors.grey, size: 18),
          const SizedBox(width: 6),
          Text(cat,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected ? color : Colors.grey)),
        ]),
      ),
    );
  }
}
