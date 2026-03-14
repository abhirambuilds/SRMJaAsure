import 'package:flutter/material.dart';
import 'student/student_login_screen.dart';
import 'teacher/teacher_login_screen.dart';
import '../utils/auth_flags.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {

  static const Color srmBlue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();

    /// VERY IMPORTANT:
    /// Show popup ONLY AFTER screen is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showBlockedPopupIfNeeded();
    });
  }

  void _showBlockedPopupIfNeeded() {

    if (!AuthFlags.blockedNonSrm) return;

    /// reset flag immediately (prevents repeated popup)
    AuthFlags.blockedNonSrm = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                height: 90,
                width: 90,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 48,
                  color: Colors.redAccent,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                "SRM Email Required",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                "Access is restricted to official SRM students.\n\nPlease sign in using your @srmist.edu.in Google account.",
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 26),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Back to Login"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Column(
          children: [

            // ===== HEADER =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 40),
              decoration: const BoxDecoration(
                color: srmBlue,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
              ),
              child: Column(
                children: [

                  Image.asset(
                    'assets/images/srm_logo.png',
                    height: 95,
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    "SRM Institute of Science and Technology",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    "JaAssure Lab Access Portal",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // ===== LOGIN CARDS =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [

                  _roleCard(
                    context,
                    icon: Icons.school,
                    title: "Student Login",
                    subtitle: "SRM Students",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentLoginScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  _roleCard(
                    context,
                    icon: Icons.badge,
                    title: "Faculty Login",
                    subtitle: "SRM Faculty Members",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeacherLoginScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ===== FOOTER =====
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                children: const [
                  Text(
                    "Secure Laboratory Access System",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Powered by SRM Campus Technology",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- ROLE CARD ----------
  static Widget _roleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 14,
              offset: Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: srmBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: srmBlue, size: 30),
            ),

            const SizedBox(width: 18),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_forward_ios_rounded,
                size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
