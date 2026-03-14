// lib/screens/admin_cancellation_screen.dart
import 'dart:async' as async;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/utils/server_time.dart';

class AdminCancellationScreen extends StatefulWidget {
  const AdminCancellationScreen({super.key});

  @override
  State<AdminCancellationScreen> createState() =>
      _AdminCancellationScreenState();
}

class _AdminCancellationScreenState extends State<AdminCancellationScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  DateTime weekStart = _nextWeekMonday(); // Monday of the active booking week
  Map<String, List<Map<String, dynamic>>> bookingsByDate = {};
  int selectedDayIndex = 0; // 0..4 => Mon..Fri
  bool _operationInProgress = false;

  static DateTime _nextWeekMonday() {
    final now = ServerTime.now();
    final thisWeekMonday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(
      thisWeekMonday.year,
      thisWeekMonday.month,
      thisWeekMonday.day,
    ).add(const Duration(days: 7));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWeekAndBookings();
    });
  }

  Future<void> _loadWeekAndBookings() async {
    setState(() {
      loading = true;
      bookingsByDate = {};
    });

    try {
      // 1) optionally get the booking_week row so UI follows backend week control
      final weekRow = await supabase
          .from('booking_weeks')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (weekRow != null && weekRow['week_start'] != null) {
        try {
          final ws = weekRow['week_start'].toString();
          final parsed = DateTime.parse(ws);
          weekStart = DateTime(parsed.year, parsed.month, parsed.day);
        } catch (_) {
          // ignore parse errors and keep computed weekStart
        }
      }

      // 2) load approved bookings for that week (Mon..Fri)
      final startIso = DateFormat('yyyy-MM-dd').format(weekStart);
      final endIso = DateFormat(
        'yyyy-MM-dd',
      ).format(weekStart.add(const Duration(days: 4)));

      final raw = await supabase
          .from('gpu_bookings')
          .select('''
id,
booking_for_date,
otp_code,
purpose,
team_members,

student:profiles!gpu_bookings_booking_owner_fkey(
    id,
    name,
    reg_no,
    department
),

slot:gpu_slot_templates!gpu_bookings_slot_template_id_fkey(
    id,
    slot_name,
    start_time,
    end_time
)
''')
          .eq('status', 'approved')
          .filter('booking_for_date', 'gte', startIso)
          .filter('booking_for_date', 'lte', endIso)
          .order('booking_for_date')
          .order('slot_template_id');

      final rows = List<Map<String, dynamic>>.from(raw ?? []);

      // group by dateKey (yyyy-MM-dd)
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final r in rows) {
        final booking = Map<String, dynamic>.from(r);

        final rawDate = (booking['booking_for_date'] ?? '').toString();
        final dateKey = rawDate.split('T').first;

        booking['student'] = Map<String, dynamic>.from(
          booking['student'] ?? {},
        );
        booking['slot'] = Map<String, dynamic>.from(booking['slot'] ?? {});

        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add(booking);
      }

      // ensure each date has a list (even if empty)
      for (int i = 0; i < 5; i++) {
        final key = DateFormat(
          'yyyy-MM-dd',
        ).format(weekStart.add(Duration(days: i)));
        grouped.putIfAbsent(key, () => []);
      }

      // sort bookings inside each day by slot start_time
      grouped.forEach((k, v) {
        v.sort((a, b) {
          final aStart = (a['slot']?['start_time'] ?? '00:00:00').toString();
          final bStart = (b['slot']?['start_time'] ?? '00:00:00').toString();
          return aStart.compareTo(bStart);
        });
      });

      bookingsByDate = Map<String, List<Map<String, dynamic>>>.from(grouped);
      selectedDayIndex = 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  DateTime _dateForDayIndex(int idx) {
    return DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    ).add(Duration(days: idx));
  }

  String _dateKeyForDayIndex(int idx) {
    return DateFormat('yyyy-MM-dd').format(_dateForDayIndex(idx));
  }

  Widget _dayTile(int idx) {
    final dt = _dateForDayIndex(idx);
    final iso = _dateKeyForDayIndex(idx);
    final label = DateFormat('EEEE').format(dt);
    final short = DateFormat('dd MMM').format(dt);
    final count = bookingsByDate[iso]?.length ?? 0;
    final selected = idx == selectedDayIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedDayIndex = idx;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.grey.shade300,
          ),
          boxShadow: selected
              ? [
                  const BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    short,
                    style: TextStyle(
                      color: selected ? Colors.white70 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? Colors.white24 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? t) {
    if (t == null || t.isEmpty) return '';
    try {
      final parts = t.split(':');
      var h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1] : '00';
      final period = h >= 12 ? 'PM' : 'AM';
      h = h % 12;
      if (h == 0) h = 12;
      return '$h:$m $period';
    } catch (_) {
      return t ?? '';
    }
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final student = (b['student'] as Map?) ?? {};
    final slot = (b['slot'] as Map?) ?? {};
    final name = student['name'] ?? 'Unknown';
    final reg = student['reg_no'] ?? '-';
    final dept = student['department'] ?? '-';
    final slotName = slot['slot_name'] ?? 'Slot';
    final start = slot['start_time']?.toString() ?? '';
    final end = slot['end_time']?.toString() ?? '';
    final otp = b['otp_code']?.toString() ?? '------';
    final purpose = b['purpose'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  otp,
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Reg: $reg',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 4),
                  Text(
                    'Dept: $dept',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$slotName • ${_formatTime(start)} - ${_formatTime(end)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
          if ((purpose ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Purpose: $purpose'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _operationInProgress
                      ? null
                      : () => _confirmCancelSingle(b),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text(
                    'Cancel booking',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelSingle(Map<String, dynamic> booking) async {
    // ask for reason and confirm
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter cancellation reason (student will receive email)',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Reason...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Booking'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reason required')));
      return;
    }

    await _performCancel([booking['id'].toString()], reason);
  }

  Future<void> _confirmCancelWholeDay() async {
    final iso = _dateKeyForDayIndex(selectedDayIndex);
    final listForDay = bookingsByDate[iso] ?? [];
    if (listForDay.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No approved bookings to cancel on this day'),
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cancel All Bookings — Day'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You are about to cancel ${listForDay.length} booking(s) on ${DateFormat('EEE, dd MMM yyyy').format(_dateForDayIndex(selectedDayIndex))}.',
              ),
              const SizedBox(height: 10),
              const Text('Provide a reason (students will receive email)'),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Reason...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel All'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reason required')));
      return;
    }

    final ids = listForDay.map((b) => b['id'].toString()).toList();
    await _performCancel(ids, reason);
  }

  Future<void> _performCancel(List<String> bookingIds, String reason) async {
    if (bookingIds.isEmpty) return;

    setState(() => _operationInProgress = true);

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text("Cancelling bookings..."),
          ],
        ),
      ),
    );

    int success = 0;
    int failed = 0;
    final failures = <String>[];

    try {
      // process sequentially to avoid rate / trigger surprises
      for (final id in bookingIds) {
        try {
          await supabase
              .from('gpu_bookings')
              .update({'status': 'cancelled'})
              .eq('id', id);

          await supabase.from('booking_cancellations').insert({
            'booking_id': id,
            'cancelled_by': supabase.auth.currentUser!.id,
            'cancel_reason': reason,
          });

          success++;
        } catch (e) {
          failed++;
          failures.add('$id -> $e');
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      Navigator.pop(context); // close progress dialog
      setState(() {
        _operationInProgress = false;
      });
    }

    // show summary
    if (success > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cancelled $success booking(s)${failed > 0 ? ' — $failed failed' : ''}',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No bookings cancelled')));
    }

    if (failed > 0) {
      final detail = failures.join('\n');
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some cancellations failed'),
          content: SingleChildScrollView(child: Text(detail)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    // reload state
    await _loadWeekAndBookings();
  }

  Future<void> _refresh() async {
    await _loadWeekAndBookings();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = _dateForDayIndex(selectedDayIndex);
    final selectedIso = DateFormat('yyyy-MM-dd').format(selectedDate);
    final listForSelectedDay = bookingsByDate[selectedIso] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cancel Approved Bookings'),
        backgroundColor: const Color(0xFFB71C1C), // dark red header
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF8F6F6),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Week header
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Booking week',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${DateFormat('dd MMM').format(weekStart)} → ${DateFormat('dd MMM yyyy').format(weekStart.add(const Duration(days: 4)))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              DateFormat('dd MMM yyyy').format(selectedDate),
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Day tiles (vertical)
                    Column(children: List.generate(5, (i) => _dayTile(i))),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Bookings for ${DateFormat('EEEE, dd MMM yyyy').format(selectedDate)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _operationInProgress
                              ? null
                              : _confirmCancelWholeDay,
                          label: const Text('Cancel whole day'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (listForSelectedDay.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Center(
                          child: Column(
                            children: const [
                              Icon(
                                Icons.event_busy,
                                size: 56,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text('No approved bookings'),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          ...listForSelectedDay
                              .map((b) => _bookingCard(b))
                              .toList(),
                          const SizedBox(height: 24),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
