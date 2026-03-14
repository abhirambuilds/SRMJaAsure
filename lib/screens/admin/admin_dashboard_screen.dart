// lib/screens/admin_dashboard_screen.dart
import 'package:srm_lab_access/utils/server_time.dart';

import 'admin_pending_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_approved_bookings_screen.dart';
import 'admin_download_logs_screen.dart';
import 'admin_cancellation_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool loading = true;
  Map<String, dynamic>? profile;
  bool jaassureOpen = false;
  bool generalOpen = false;
  bool loadingBookingState = true;

  // week flags
  bool weekOpenGeneral = false;
  bool weekOpenJaassure = false;

  // quick stats
  int pendingCount = 0;
  int approvedCount = 0;
  DateTime weekStart = DateTime.now();
  // Live status expanded toggle
  bool liveExpanded = false;

  @override
  void initState() {
    super.initState();

    _init();

    // sync server time and then refresh active week + counts
    Future.microtask(() async {
      await ServerTime.sync();
      await _loadActiveWeek();
      await _loadQuickCounts();
      // keep booking state in sync with server-time/day rules
      await loadBookingStatus();
    });
  }

  Future<void> _init() async {
    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        profile = null;
        return;
      }

      final prof = await supabase
          .from('profiles')
          .select('id, name, reg_no, department, role_type')
          .eq('id', user.id)
          .maybeSingle();

      profile = prof == null ? null : Map<String, dynamic>.from(prof as Map);

      await Future.wait([_loadWeekFlags(), _loadQuickCounts()]);
      // ensure chips respect day rules after initial flags are loaded
      _applyDayRulesToChips();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Init failed: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Loads the booking week record that contains the current app date (ServerTime.now()).
  /// If no such record exists, this returns early (caller can fallback to latest if desired).
  Future<void> _loadActiveWeek() async {
    final now = ServerTime.now();

    /// 1️⃣ find NEXT MONDAY
    int daysUntilMonday = DateTime.monday - now.weekday;
    if (daysUntilMonday <= 0) {
      daysUntilMonday += 7;
    }

    final nextMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: daysUntilMonday));

    final mondayStr = DateFormat('yyyy-MM-dd').format(nextMonday);

    /// 2️⃣ load that week from DB
    final week = await supabase
        .from('booking_weeks')
        .select('week_start, booking_open_general, booking_open_jaassure')
        .eq('week_start', mondayStr)
        .maybeSingle();

    if (week == null) {
      if (mounted)
        setState(() {
          jaassureOpen = false;
          generalOpen = false;
          weekStart = nextMonday;
        });
      return;
    }

    weekStart = DateTime.parse(week['week_start']);

    /// 3️⃣ day-rule logic
    final weekday = now.weekday;

    jaassureOpen =
        (week['booking_open_jaassure'] == true) && weekday == DateTime.friday;

    generalOpen =
        (week['booking_open_general'] == true) && weekday == DateTime.saturday;

    if (mounted) setState(() {});
  }

  /// Refreshes booking status for today's server-time and applies day rules.
  Future<void> loadBookingStatus() async {
    // small debounce to avoid hammering on quick UI interactions
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      final now = ServerTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);

      final data = await supabase
          .from('booking_weeks')
          .select('booking_open_jaassure, booking_open_general')
          .lte('week_start', today)
          .gte('week_end', today)
          .maybeSingle();

      bool dbJaassure = false;
      bool dbGeneral = false;

      if (data != null) {
        dbJaassure = data['booking_open_jaassure'] == true;
        dbGeneral = data['booking_open_general'] == true;
      } else {
        // no active week → ensure chips are false
        dbJaassure = false;
        dbGeneral = false;
      }

      // apply the day rules:
      // - JaAssure: only open on Friday if DB flag true
      // - General: only open on Saturday if DB flag true
      final weekday = now.weekday;
      jaassureOpen = dbJaassure && weekday == DateTime.friday;
      generalOpen = dbGeneral && weekday == DateTime.saturday;
    } catch (_) {
      jaassureOpen = false;
      generalOpen = false;
    }

    if (mounted) setState(() {});
  }

  /// Loads week flags for the week containing ServerTime.now() (used on startup/refresh).
  Future<void> _loadWeekFlags() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(ServerTime.now());

      final weekRecord = await supabase
          .from('booking_weeks')
          .select('week_start, booking_open_general, booking_open_jaassure')
          .lte('week_start', today)
          .gte('week_end', today)
          .maybeSingle();

      if (weekRecord != null) {
        weekStart =
            DateTime.tryParse(weekRecord['week_start']?.toString() ?? '') ??
            weekStart;

        if (!mounted) return;
        setState(() {
          weekOpenGeneral = weekRecord['booking_open_general'] == true;
          weekOpenJaassure = weekRecord['booking_open_jaassure'] == true;

          // IMPORTANT: sync chips placeholders - actual visible chips follow day rules
          // We'll call _applyDayRulesToChips to set visible chips according to current day.
          // Keep the underlying week flags for counts and other logic.
        });

        _applyDayRulesToChips();
      } else {
        // no week record covering today, keep defaults
      }
    } catch (_) {
      // ignore and leave defaults
    }
  }

  /// Loads pending & approved booking counts for the configured weekStart (Mon..Fri).
  Future<void> _loadQuickCounts() async {
    try {
      final startIso = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(weekStart.year, weekStart.month, weekStart.day));
      final end = weekStart.add(const Duration(days: 4));
      final endIso = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(end.year, end.month, end.day));

      final pendingRaw = await supabase
          .from('gpu_bookings')
          .select('id')
          .gte('booking_for_date', startIso)
          .lte('booking_for_date', endIso)
          .eq('status', 'pending');

      final approvedRaw = await supabase
          .from('gpu_bookings')
          .select('id')
          .gte('booking_for_date', startIso)
          .lte('booking_for_date', endIso)
          .eq('status', 'approved');

      if (!mounted) return;
      setState(() {
        pendingCount = (pendingRaw ?? []).length;
        approvedCount = (approvedRaw ?? []).length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pendingCount = 0;
        approvedCount = 0;
      });
    }
  }

  /// Ensure the visible chips (jaassureOpen / generalOpen) follow the underlying
  /// week flags plus the day-of-week rules we want for testing:
  /// - jaassureOpen only on Friday
  /// - generalOpen only on Saturday
  void _applyDayRulesToChips() {
    final now = ServerTime.now();
    final weekday = now.weekday;
    setState(() {
      jaassureOpen = weekOpenJaassure && (weekday == DateTime.friday);
      generalOpen = weekOpenGeneral && (weekday == DateTime.saturday);
    });
  }

  Future<void> _onLogout() async {
    try {
      await supabase.auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  }

  Future<void> _downloadWeeklyLogs() async {
    setState(() => loading = true);
    try {
      final startIso = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(weekStart.year, weekStart.month, weekStart.day));
      final week = await supabase
          .from('booking_weeks')
          .select('id')
          .eq('week_start', startIso)
          .maybeSingle();
      if (week == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No booking week configured for this week.'),
            ),
          );
        return;
      }
      final weekId = week['id']?.toString();
      if (weekId == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid booking week record.')),
          );
        return;
      }

      final res = await supabase.rpc(
        'export_weekly_booking_archive',
        params: {'p_week_id': weekId},
      );
      if (res == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export did not return a download link'),
            ),
          );
        return;
      }
      final url = res.toString();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export ready'),
          content: SelectableText('Download link:\n$url'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openMenuRoute(String routeName) {
    Navigator.of(context).pushNamed(routeName);
  }

  // --------------------------


  @override
  Widget build(BuildContext context) {
    final roleStr = (profile?['role_type'] ?? '').toString().toLowerCase();
    if (!loading && roleStr != 'admin') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(onPressed: _onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Unauthorized',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your account is not configured as a Admin. Contact admin if this is an error.',
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final displayDate = DateFormat('dd MMM yyyy').format(ServerTime.now());
    final email = supabase.auth.currentUser?.email ?? '';
    final fallbackName = email.split('@').first; // admin@srmist.edu.in → admin
    final name = (profile?['name'] ?? fallbackName).toString();
    final initial = (name.isNotEmpty ? name[0].toUpperCase() : 'A');

    // menu tiles: simplified & vertical-only for top->bottom flow
    final menu = [
      _MenuTileData(
        'Pending Requests',
        'Review pending booking requests',
        Icons.pending_actions,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminPendingRequestsScreen(),
            ),
          );
        },
      ),
      _MenuTileData(
        'Approved Bookings',
        'See approved bookings & OTPs',
        Icons.check_circle,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminApprovedBookingsScreen(),
            ),
          );
        },
      ),
      _MenuTileData(
        'Download Logs',
        'Export weekly booking logs',
        Icons.download,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDownloadLogsScreen()),
          );
        },
      ),
      _MenuTileData(
        'Cancellation',
        'Manage cancellations & send notices',
        Icons.cancel,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminCancellationScreen()),
          );
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => loading = true);
              await _loadWeekFlags();
              await _loadQuickCounts();
              await loadBookingStatus();
              if (mounted) setState(() => loading = false);
            },
          ),
          IconButton(onPressed: _onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
          child: Column(
            children: [
              // header card (improved so name is visible clearly)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Top Row (Avatar + Name + Date)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.blue.shade700,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Role: Admin',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                        Text(
                          displayDate,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),


                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Live status card (collapsible) - placed above the menu as requested
              GestureDetector(
                onTap: () {
                  // toggle expansion; when opening, refresh counts silently (no global loader)
                  setState(() {
                    liveExpanded = !liveExpanded;
                  });

                  // when expanded, refresh counts in background (no await, no global loading)
                  if (liveExpanded) {
                    _loadQuickCounts();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.03),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // header row for live status
                      Row(
                        children: [
                          const Icon(Icons.show_chart, color: Colors.blue),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Live status',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // chevron rotates when expanded
                          AnimatedRotation(
                            turns: liveExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.expand_more,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      // expanded content: small animated reveal of the three stats
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Column(
                            children: [
                              _FullWidthStat(
                                title: 'Pending',
                                value: pendingCount.toString(),
                                color: Colors.orange,
                              ),
                              const SizedBox(height: 10),
                              _FullWidthStat(
                                title: 'Approved',
                                value: approvedCount.toString(),
                                color: Colors.green,
                              ),
                              const SizedBox(height: 10),
                              _FullWidthStat(
                                title: 'Week',
                                value:
                                    DateFormat('dd MMM').format(weekStart) +
                                    ' → ' +
                                    DateFormat('dd MMM').format(
                                      weekStart.add(const Duration(days: 4)),
                                    ),
                                color: Colors.blue,
                              ),
                            ],
                          ),
                        ),
                        crossFadeState: liveExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 250),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // vertical menu list (Pending Requests etc.)
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: menu.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final m = menu[i];
                    return InkWell(
                      onTap: m.onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.03),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.blue.shade50,
                              child: Icon(m.icon, color: Colors.blue, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    m.subtitle,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTileData {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _MenuTileData(this.title, this.subtitle, this.icon, this.onTap);
}

class _FullWidthStat extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _FullWidthStat({
    required this.title,
    required this.value,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12.withOpacity(0.02), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.bar_chart, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool small;
  const _StatusChip({
    required this.label,
    required this.color,
    this.small = false,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: small ? 11 : 12,
            ),
          ),
        ),
      ),
    );
  }
}
