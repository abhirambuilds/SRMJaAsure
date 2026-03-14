import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../student/student_gpu_my_bookings_screen.dart';
import '../gpu_weekly_screen.dart';
import '../role_selection_screen.dart';
import '/utils/server_time.dart';
// removed: import 'student_team_invites_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? profile;
  bool loading = true;
  String? errorText;

  @override
  void initState() {
    super.initState();
    loadProfile();
    // invite-related logic removed for Faculty
    // loadInviteCount();
    // startInviteListener();
  }

  // invite-related fields and methods removed for Faculty:
  // int pendingInvites = 0;
  // RealtimeChannel? inviteChannel;
  //
  // Future<void> loadInviteCount() async { ... }
  // Future<void> startInviteListener() async { ... }

  Future<void> loadProfile() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    await ServerTime.sync(); // removed ServerTime.sync() call
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          errorText = "Not signed in";
          loading = false;
        });
        return;
      }

      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        profile = Map<String, dynamic>.from(data as Map);
      } else {
        profile = null;
      }
    } catch (e) {
      errorText = "Failed to load profile: $e";
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconBg,
    int? badgeCount,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (iconBg ?? const Color(0xFF1565C0)).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF1565C0), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badgeCount != null && badgeCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.grey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final name = profile?['name'] ?? '';
    final dept = profile?['department'] ?? '';
    final regNo = profile?['reg_no'];
    String roleType = (profile?['role_type'] ?? '').toString();

    // only set Faculty when DB actually says 'faculty' (avoid masking mentors)
    if ((profile?['role_type'] ?? '') == 'jaassure') {
      roleType = 'JaAssure Student';
    } else if ((profile?['role_type'] ?? '') == 'student') {
      roleType = 'Student';
    } else if ((profile?['role_type'] ?? '') == 'faculty') {
      roleType = 'Faculty';
    } else {
      // keep raw value or fallback to empty so it's obvious if DB is unexpected
      roleType = roleType.isNotEmpty ? roleType : 'Unknown';
    }

    final initials = name.isNotEmpty
        ? name
              .trim()
              .split(' ')
              .map((s) => s.isNotEmpty ? s[0] : '')
              .take(2)
              .join()
        : '?';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white24,
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Faculty' : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(dept, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                // show reg no only when present and non-empty
                if (regNo != null && regNo.toString().isNotEmpty)
                  Text(
                    'Reg No: $regNo',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              roleType.toString().toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Booking banner changed for Faculty (Fri/Sat/other)
  Widget _bookingInfoBanner() {
    final now = ServerTime.now();
    final weekday = now.weekday; // 1 Mon ... 7 Sun

    final role = (profile?['role_type'] ?? 'student').toString().toLowerCase();

    String message;
    Color color;

    // JAASSURE STUDENT → Friday only
    if (role == 'jaassure') {
      if (weekday == DateTime.friday) {
        message = "Booking is OPEN today for next week.";
        color = Colors.green;
      } else {
        message = "Booking opens Friday for next week.";
        color = Colors.blueGrey;
      }
    }
    // ALL OTHERS (student + faculty) → Saturday only
    else {
      if (weekday == DateTime.saturday) {
        message = "Booking is OPEN today for next week.";
        color = Colors.green;
      } else {
        message = "Booking opens Saturday for next week.";
        color = Colors.blueGrey;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogout() async {
    try {
      await supabase.auth.signOut(scope: SignOutScope.global);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text("Faculty Portal"),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            icon: const Icon(Icons.refresh),
            onPressed: loadProfile,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _onLogout,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (errorText != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await loadProfile();
                      // invite-related refresh removed for Faculty
                      // await loadInviteCount();
                    },
                    child: Column(
                      children: [
                        _headerCard(),
                        const SizedBox(height: 6),
                        _bookingInfoBanner(),
                        Expanded(
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              // BOOK GPU: allow navigation always — enforce rules inside GpuWeeklyScreen / RPC
                              dashboardCard(
                                icon: Icons.memory,
                                title: "Book GPU Slot",
                                subtitle: "Reserve weekly GPU lab access",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const GpuWeeklyScreen(),
                                    ),
                                  );
                                },
                              ),

                              // Team Invites card REMOVED for Faculty

                              // MY GPU BOOKINGS
                              dashboardCard(
                                icon: Icons.computer,
                                title: "My GPU Bookings",
                                subtitle:
                                    "View, manage or cancel GPU reservations",
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StudentGpuMyBookingsScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
    );
  }

  @override
  void dispose() {
    // invite-related cleanup removed for Faculty
    // if (inviteChannel != null) {
    //   supabase.removeChannel(inviteChannel!);
    // }
    super.dispose();
  }
}
