// lib/screens/student_gpu_my_bookings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:srm_lab_access/utils/server_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentGpuMyBookingsScreen extends StatefulWidget {
  const StudentGpuMyBookingsScreen({super.key});

  @override
  State<StudentGpuMyBookingsScreen> createState() =>
      _StudentGpuMyBookingsScreenState();
}

class _StudentGpuMyBookingsScreenState
    extends State<StudentGpuMyBookingsScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool actionInProgress = false;

  // bookings keyed list
  List<Map<String, dynamic>> bookings = [];

  // slot template lookup (id -> template map)
  final Map<int, Map<String, dynamic>> slotTemplates = {};

  // team members lookup: booking_id -> list of members
  final Map<String, List<Map<String, dynamic>>> teamMembers = {};

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadAll().then((_) => _setupRealtime());
  }

  @override
  void dispose() {
    // remove realtime subscription(s)
    try {
      if (_channel != null) {
        supabase.removeChannel(_channel!);
      } else {
        // fallback: remove all (safe)
        supabase.removeAllChannels();
      }
    } catch (_) {
      // ignore
    }
    super.dispose();
  }

  Future<void> _setupRealtime() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      _channel = supabase.channel('user_gpu_bookings_${user.id}');

      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'gpu_bookings',
            callback: (payload) {
              try {
                // v2 FIX: use newRecord / oldRecord
                final newRow = payload.newRecord;
                final oldRow = payload.oldRecord;

                final ownerNew = newRow?['booking_owner']?.toString();
                final ownerOld = oldRow?['booking_owner']?.toString();

                // if any change belongs to current user -> reload
                if (ownerNew == user.id || ownerOld == user.id) {
                  _loadAll();
                }
              } catch (_) {}
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    setState(() {
      loading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        // no user — return to safe state
        bookings = [];
        setState(() => loading = false);
        return;
      }

      // 1) load bookings for this user (both past and future)
      // include OTP and team_members fields
      final resp = await supabase
          .from('gpu_bookings')
          .select('''
id,
week_id,
slot_template_id,
booking_for_date,
booking_owner,
role_type,
reason,
purpose,
mentor_approved,
approved_by,
status,
otp_code,
team_members,
created_at
''')
          .eq('booking_owner', user.id)
          .neq('status', 'cancelled')
          .order('booking_for_date', ascending: false);

      final rawBookings = List<Map<String, dynamic>>.from(resp ?? []);

      // collect slot_template_ids and booking ids
      final slotIds = <int>{};

      for (var b in rawBookings) {
        final slotId = b['slot_template_id'];
        if (slotId is int) slotIds.add(slotId);
      }

      // 2) load slot templates needed
      slotTemplates.clear();
      if (slotIds.isNotEmpty) {
        final tplResp = await supabase
            .from('gpu_slot_templates')
            .select()
            .inFilter('id', slotIds.toList())
            .order('slot_order', ascending: true);
        for (var t in tplResp as List<dynamic>) {
          final m = Map<String, dynamic>.from(t as Map);
          slotTemplates[m['id'] as int] = m;
        }
      }

      // 3) parse team_members JSONB stored on gpu_bookings
      teamMembers.clear();
      for (final b in rawBookings) {
        final id = b['id']?.toString();
        final raw = b['team_members'];

        if (id == null || raw == null) continue;

        try {
          // raw may already be List<dynamic> (decoded by supabase client), or string JSON
          if (raw is List) {
            teamMembers[id] = raw
                .where((e) => e != null)
                .map<Map<String, dynamic>>(
                  (e) => e is Map
                      ? Map<String, dynamic>.from(e)
                      : <String, dynamic>{},
                )
                .where((m) => m.isNotEmpty)
                .toList();
          } else if (raw is String) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              teamMembers[id] = decoded
                  .where((e) => e != null)
                  .map<Map<String, dynamic>>(
                    (e) => e is Map
                        ? Map<String, dynamic>.from(e)
                        : <String, dynamic>{},
                  )
                  .where((m) => m.isNotEmpty)
                  .toList();
            } else {
              teamMembers[id] = [];
            }
          } else {
            // unexpected type
            teamMembers[id] = [];
          }
        } catch (_) {
          teamMembers[id] = [];
        }
      }

      setState(() {
        bookings = rawBookings;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load bookings: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Color _statusColor(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final role = (booking['role_type'] ?? '').toString().toLowerCase();

    if (status == 'cancelled') return Colors.red.shade600;
    if (status == 'rejected') return Colors.red.shade400;
    if (role == 'jaassure') return Colors.red.shade700;
    if (status == 'approved' || status == 'confirmed') return Colors.green;
    if (booking['mentor_approved'] == true) return Colors.green.shade700;
    return Colors.orange.shade800; // pending / default
  }

  String _statusLabel(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    if (status == 'cancelled') return 'Cancelled';
    if (status == 'rejected') return 'Rejected';
    if (status == 'approved' || status == 'confirmed') return 'Approved';
    if (booking['mentor_approved'] == true) return 'Mentor Approved';
    return 'Pending';
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Unknown';
    try {
      final d = DateTime.parse(isoDate);
      return DateFormat('EEE, dd MMM yyyy').format(d);
    } catch (_) {
      return isoDate;
    }
  }

  String _slotLabel(int? slotId) {
    if (slotId == null) return 'Slot';
    final tpl = slotTemplates[slotId];
    if (tpl == null) return 'Slot $slotId';
    final start = (tpl['start_time'] ?? '').toString();
    final end = (tpl['end_time'] ?? '').toString();

    String fmt(String timeStr) {
      try {
        final hour = int.parse(timeStr.split(':').first);
        final period = hour >= 12 ? 'PM' : 'AM';
        var h = hour % 12;
        if (h == 0) h = 12;
        return '$h:00 $period';
      } catch (_) {
        return timeStr;
      }
    }

    return '${tpl['slot_name'] ?? 'Slot'} · ${fmt(start)} - ${fmt(end)}';
  }

  bool _canCancel(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString().toLowerCase();
    // only allow cancel for approved bookings (and not already cancelled)
    if (status != 'approved') return false;

    final role = (booking['role_type'] ?? '').toString().toLowerCase();
    if (role == 'jaassure') return false;

    final iso = booking['booking_for_date']?.toString();
    final slotId = booking['slot_template_id'];

    if (iso == null || slotId == null) return false;

    final tpl = slotTemplates[slotId];
    if (tpl == null) return false;

    try {
      // booking date
      final date = DateTime.parse(iso);

      // slot start time (HH:mm:ss)
      final startTime = (tpl['start_time'] ?? '').toString();
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      // actual slot start DateTime
      final slotStart = DateTime(date.year, date.month, date.day, hour, minute);

      final now = ServerTime.now();

      final diff = slotStart.difference(now);

      // allow cancel ONLY if 24+ hrs before slot start
      return diff.inHours >= 24;
    } catch (_) {
      return false;
    }
  }

  void _openDetails(Map<String, dynamic> booking) {
    final bid = booking['id']?.toString() ?? '';
    final members = teamMembers[bid] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final status = (booking['status'] ?? '').toString().toLowerCase();
        final otp = booking['otp_code']?.toString();
        return Padding(
          padding: MediaQuery.of(ctx).viewInsets.add(const EdgeInsets.all(16)),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 6,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  _formatDate(booking['booking_for_date']?.toString()),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_slotLabel(booking['slot_template_id'] as int?)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Chip(
                      label: Text(_statusLabel(booking)),
                      backgroundColor: _statusColor(booking),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Purpose:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  booking['purpose']?.toString() ?? booking['reason'] ?? '—',
                ),
                const SizedBox(height: 12),

                // OTP (visible only for approved bookings)
                if (status == 'approved') ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Lab OTP:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Center(
                      child: Text(
                        (otp?.isNotEmpty == true) ? otp! : '------',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Text(
                  'Team Members',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                members.isEmpty
                    ? const Text('No team members invited')
                    : Column(
                        children: members.map((m) {
                          final name = m['name']?.toString() ?? 'Member';
                          final reg = m['regno']?.toString() ?? '';
                          final email = m['email']?.toString() ?? '';

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text(name),
                            subtitle: Text(
                              reg.isEmpty ? email : '$reg • $email',
                            ),
                          );
                        }).toList(),
                      ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy, size: 72, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No GPU bookings yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'When you create bookings, they will appear here. Tap "Book GPU" from the dashboard to make a booking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.dashboard_rounded, size: 22),
                label: const Text(
                  'Back to Dashboard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My GPU Bookings'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : bookings.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  _emptyState(),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: bookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final b = bookings[idx];
                  final id = b['id']?.toString() ?? '';
                  final dateStr = _formatDate(
                    b['booking_for_date']?.toString(),
                  );
                  final slotLbl = _slotLabel(b['slot_template_id'] as int?);

                  // Only show cancel X for approved bookings and when allowed by rules
                  final showCancelIcon =
                      (b['status'] ?? '').toString().toLowerCase() ==
                          'approved' &&
                      _canCancel(b);

                  return InkWell(
                    onTap: () => _openDetails(b),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          // left: status indicator
                          Container(
                            width: 8,
                            height: 70,
                            decoration: BoxDecoration(
                              color: _statusColor(b),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // middle: info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  slotLbl,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Chip(
                                      label: Text(_statusLabel(b)),
                                      backgroundColor: _statusColor(b),
                                      labelStyle: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (b['role_type'] != null &&
                                        b['role_type'] == 'jaassure')
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 6.0,
                                        ),
                                        child: Chip(
                                          label: const Text('JaAssure'),
                                          backgroundColor: Colors.red.shade700,
                                          labelStyle: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // right: actions
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const SizedBox(height: 18),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Details',
                                    onPressed: () => _openDetails(b),
                                    icon: const Icon(Icons.info_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
