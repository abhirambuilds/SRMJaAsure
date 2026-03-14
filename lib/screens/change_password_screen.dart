import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'teacher/teacher_dashboard_screen.dart';
import 'gpu_weekly_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final supabase = Supabase.instance.client;

  final newPassController = TextEditingController();
  final confirmPassController = TextEditingController();

  bool loading = false;
  bool obscure1 = true;
  bool obscure2 = true;

  String strengthText = "";
  Color strengthColor = Colors.grey;
  double strengthValue = 0.0;

  void checkStrength(String password) {
    final len = password.length;
    strengthValue = min(1.0, len / 12.0);

    if (len == 0) {
      strengthText = "";
      strengthColor = Colors.grey;
    } else if (len < 6) {
      strengthText = "Too short";
      strengthColor = Colors.red;
    } else if (len < 8) {
      strengthText = "Medium";
      strengthColor = Colors.orange;
    } else {
      strengthText = "Strong";
      strengthColor = Colors.green;
    }

    setState(() {});
  }

  Future<void> changePassword() async {
    final pass = newPassController.text.trim();
    final confirm = confirmPassController.text.trim();

    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password must be at least 6 characters")),
      );
      return;
    }

    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser!;
      if (user == null) throw "Not authenticated";

      // 1) update auth password
      await supabase.auth.updateUser(UserAttributes(password: pass));

      // 2) mark in DB
      await supabase.from('profiles').update({
        'password_changed': true,
        'must_change_password': false,
      }).eq('id', user.id);
      await supabase.auth.refreshSession();

      // 3) read role_type so we can route correctly
      final profile = await supabase
          .from('profiles')
          .select('role_type')
          .eq('id', user.id)
          .maybeSingle();

      final roleType = (profile != null && profile['role_type'] != null)
          ? (profile['role_type'] as String)
          : 'student';

      // success toast
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password updated")),
        );
      }

      // 4) route based on role_type (keep minimal, replace mentor route later)
      if (!mounted) return;

      if (roleType == 'faculty' || roleType == 'mentor') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GpuWeeklyScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed: $e")));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    newPassController.dispose();
    confirmPassController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      filled: true,
      fillColor: const Color(0xFFF4F6FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // keep it clean and centered
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/images/srm_logo.png', height: 90),

                  const SizedBox(height: 20),

                  const Text(
                    "Secure Account Setup",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    "Change your temporary password to continue.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),

                  const SizedBox(height: 28),

                  // new password
                  TextField(
                    controller: newPassController,
                    obscureText: obscure1,
                    onChanged: checkStrength,
                    decoration: _inputDecoration(
                      "New Password",
                      suffix: IconButton(
                        icon: Icon(
                          obscure1 ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => obscure1 = !obscure1),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // strength bar + text
                  if (strengthText.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: strengthValue,
                              minHeight: 6,
                              backgroundColor: Colors.black12,
                              valueColor: AlwaysStoppedAnimation(strengthColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          strengthText,
                          style: TextStyle(color: strengthColor, fontSize: 12),
                        ),
                      ],
                    ),

                  const SizedBox(height: 18),

                  // confirm
                  TextField(
                    controller: confirmPassController,
                    obscureText: obscure2,
                    decoration: _inputDecoration(
                      "Confirm Password",
                      suffix: IconButton(
                        icon: Icon(
                          obscure2 ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => obscure2 = !obscure2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  loading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: changePassword,
                            child: const Text("Update Password"),
                          ),
                        ),

                  const SizedBox(height: 14),

                  const Text(
                    "You will be required to use this password for future logins.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}