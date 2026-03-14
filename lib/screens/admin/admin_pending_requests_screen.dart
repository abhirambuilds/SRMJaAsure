// lib/screens/admin_pending_requests_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:srm_lab_access/utils/server_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPendingRequestsScreen extends StatefulWidget {
  const AdminPendingRequestsScreen({super.key});

  @override
  State<AdminPendingRequestsScreen> createState() =>
      _AdminPendingRequestsScreenState();
}

class _AdminPendingRequestsScreenState
    extends State<AdminPendingRequestsScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  List<Map<String, dynamic>> bookings = [];

  @override
  void initState() {
    super.initState();
    loadPendingBookings();

    supabase
        .channel('gpu_bookings_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'gpu_bookings',
          callback: (payload) {
            loadPendingBookings();
          },
        )
        .subscribe();
  }

  Future<void> loadPendingBookings() async {
    setState(() => loading = true);

    try {
      final data = await supabase
          .from('gpu_bookings')
          .select('''
id,
booking_for_date,
purpose,
reason,
role_type,
team_members,
slot_template_id,
gpu_slot_templates!gpu_bookings_slot_template_id_fkey(slot_name,start_time,end_time),
profiles!gpu_bookings_booking_owner_fkey(name,reg_no,department,role_type)
''')
          .eq('status', 'pending')
          .order('booking_for_date');

      // Supabase returns null for no rows - guard it
      final rows = (data ?? []) as List<dynamic>;
      bookings = rows
          .map<Map<String, dynamic>>(
            (r) => Map<String, dynamic>.from(r as Map<String, dynamic>),
          )
          .toList();
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

  Future<void> approveBooking(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve booking?'),
        content: const Text(
          'Approving will allocate the GPU seat and reject all competing requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final adminId = supabase.auth.currentUser!.id;

      final otp = await supabase.rpc(
        'approve_gpu_booking',
        params: {'p_booking_id': bookingId, 'p_admin': adminId},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking Approved • OTP: $otp')));

      await loadPendingBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Approval failed: $e')));
      }
    }
  }

  Future<void> rejectBooking(String bookingId) async {
    final controller = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Request"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Optional reason"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final adminId = supabase.auth.currentUser?.id;
      final nowIso = ServerTime.now().toIso8601String();

      // attempt to write reject_reason (safe — if column missing server will return error and we catch it)
      await supabase
          .from('gpu_bookings')
          .update({
            'status': 'rejected',
            'reject_reason': controller.text.trim(),
            'approved_by': adminId,
            'approved_at': nowIso,
          })
          .eq('id', bookingId);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking Rejected')));

      await loadPendingBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
      }
    }
  }

  /// Parse team_members which may come as a List or JSON string or null.
  List<Map<String, dynamic>> _parseTeamMembers(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      // ensure each element is Map
      return raw
          .where((e) => e != null)
          .map<Map<String, dynamic>>((e) {
            if (e is Map) return Map<String, dynamic>.from(e as Map);
            if (e is String) {
              try {
                final parsed = jsonDecode(e);
                if (parsed is Map) return Map<String, dynamic>.from(parsed);
              } catch (_) {}
            }
            return <String, dynamic>{};
          })
          .where((m) => m.isNotEmpty)
          .toList();
    }
    if (raw is String) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .map<Map<String, dynamic>>(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{},
              )
              .where((m) => m.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // string not JSON -> return empty
      }
    }
    return [];
  }

  /// Group bookings by booking_for_date (yyyy-MM-dd)
  Map<String, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final r in rows) {
      final rawDate = r['booking_for_date']?.toString() ?? '';
      // normalize to date part only
      final dateKey = rawDate.split('T').first;
      groups[dateKey] ??= [];
      groups[dateKey]!.add(r);
    }
    // sort each group's bookings by slot/time if available
    groups.forEach((k, v) {
      v.sort((a, b) {
        final aStart = (a['gpu_slot_templates']?['start_time'] ?? '00:00:00')
            .toString();
        final bStart = (b['gpu_slot_templates']?['start_time'] ?? '00:00:00')
            .toString();
        return aStart.compareTo(bStart);
      });
    });
    return Map.fromEntries(
      groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ); // sort by date asc
  }

  Widget bookingTile(Map<String, dynamic> booking) {
    final profile = booking['profiles'] ?? {};
    final slot = booking['gpu_slot_templates'] ?? {};

    final date =
        DateTime.tryParse(booking['booking_for_date']?.toString() ?? '') ??
        DateTime.now();
    final dateStr = DateFormat('EEE, dd MMM').format(date);

    final role = (profile['role_type'] ?? booking['role_type'] ?? '')
        .toString()
        .toLowerCase();

    Color roleColor;
    if (role == 'jaassure') {
      roleColor = Colors.purple;
    } else if (role == 'faculty') {
      roleColor = Colors.blue;
    } else {
      roleColor = Colors.grey.shade700;
    }

    final team = _parseTeamMembers(booking['team_members']);

    final slotName = slot['slot_name'] ?? 'Slot';
    final start = slot['start_time']?.toString() ?? '';
    final end = slot['end_time']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  DateFormat('dd MMM').format(date),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // reg & dept
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Reg: ${profile['reg_no'] ?? '-'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Dept: ${profile['department'] ?? '-'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // slot
            Row(
              children: [
                Icon(Icons.event_note, size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  '$slotName • ${_formatTimeRange(start, end)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),

            if (team.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Team members',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ...team.map((m) {
                final name = m['name'] ?? m['full_name'] ?? '-';
                final reg = m['regno'] ?? m['reg_no'] ?? '-';
                final email = m['email'] ?? '-';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.black54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$name • $reg',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],

            if ((booking['purpose'] ?? '').toString().isNotEmpty ||
                (booking['reason'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              if ((booking['purpose'] ?? '').toString().isNotEmpty)
                Text('Purpose: ${booking['purpose']}'),
              if ((booking['reason'] ?? '').toString().isNotEmpty)
                Text('Reason: ${booking['reason']}'),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () => approveBooking(booking['id'] as String),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    onPressed: () => rejectBooking(booking['id'] as String),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeRange(String start, String end) {
    String parseHour(String t) {
      if (t.isEmpty) return '';
      try {
        final parts = t.split(':');
        var hour = int.parse(parts[0]);
        final minute = parts.length > 1 ? parts[1] : '00';
        final period = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        return '$hour:$minute $period';
      } catch (_) {
        return t;
      }
    }

    final s = parseHour(start);
    final e = parseHour(end);
    if (s.isEmpty && e.isEmpty) return '';
    if (e.isEmpty) return s;
    return '$s - $e';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDay(bookings);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Requests"),
        actions: [
          IconButton(
            onPressed: loadPendingBookings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : grouped.isEmpty
          ? const Center(child: Text("No pending requests"))
          : RefreshIndicator(
              onRefresh: loadPendingBookings,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                children: grouped.entries.map((entry) {
                  final dateKey = entry.key;
                  final dayBookings = entry.value;
                  DateTime parsed;
                  try {
                    parsed =
                        DateTime.tryParse(dateKey) ??
                        DateFormat('yyyy-MM-dd').parse(dateKey);
                  } catch (_) {
                    parsed = DateTime.now();
                  }
                  final header = DateFormat('EEEE, dd MMM yyyy').format(parsed);

                  return ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                    collapsedIconColor: Colors.black54,
                    iconColor: Colors.black54,
                    title: Row(
                      children: [
                        Text(
                          header,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${dayBookings.length} request(s)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: dayBookings
                        .map(
                          (b) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: bookingTile(b),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
            ),
    );
  }

  @override
  void dispose() {
    supabase.removeAllChannels();
    super.dispose();
  }
}
