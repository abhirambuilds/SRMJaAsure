import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/auth_flags.dart';
import 'role_selection_screen.dart';
import 'student/student_profile_screen.dart';
import 'change_password_screen.dart';
import 'teacher/teacher_dashboard_screen.dart';
import 'student/student_dashboard_screen.dart';
import 'admin/admin_dashboard_screen.dart'; // new import for mentor dashboard
import '../utils/server_time.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;
  bool _routing = false;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        /// NOT LOGGED IN
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (session == null) {
          return const RoleSelectionScreen();
        }

        /// LOGGED IN
        return FutureBuilder(
          future: _routeUser(session),
          builder: (context, snapshot) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          },
        );
      },
    );
  }

  Future<void> _routeUser(Session session) async {
    if (_routing) return;
    _routing = true;
    // small delay to let SDK hydrate (keeps your previous behavior)
    await Future.delayed(const Duration(milliseconds: 300));

    final live = supabase.auth.currentSession;
    if (live != null) {
      session = live;
    }

    final email = session.user.email ?? "";

    // fetch profile row for this user (may be null on first login)
    final res = await supabase
        .from('profiles')
        .select()
        .eq('id', session.user.id)
        .maybeSingle();

    await ServerTime.sync();

    if (!mounted) {
      _routing = false;
      return;
    }

    // Do navigation after build to avoid context/setState races (preserve previous pattern)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _routing = false;
        return;
      }

      /// first login (unchanged)
      if (res == null || res['name'] == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentProfileScreen()),
        );
        _routing = false;
        return;
      }

      // Phase-2 role handling: prefer role_type, fallback to legacy role
      final roleType = (res['role_type'] ?? res['role'] ?? 'student')
          .toString();
      final changed = res['password_changed'] ?? false;
      // ---------------- ADMIN ----------------
      if (roleType.toLowerCase() == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        _routing = false;
        return;
      }

      // FACULTY (phase-2): force change-password first time, then TeacherDashboard
      if (roleType.toLowerCase() == 'faculty' ||
          roleType.toLowerCase() == 'teacher') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => changed
                ? const TeacherDashboardScreen()
                : const ChangePasswordScreen(),
          ),
        );
        _routing = false;
        return;
      }

      // ADMIN
      if (roleType.toLowerCase() == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
        _routing = false;
        return;
      }

      // STUDENT (unchanged): go to StudentDashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StudentDashboardScreen()),
      );
    });
  }
}
