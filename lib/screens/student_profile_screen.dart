import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_theme.dart';
import 'student_dashboard_screen.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController regNoController = TextEditingController();
  final TextEditingController deptController = TextEditingController();
  bool loading = false;

  Future<void> saveProfile() async {
    if (nameController.text.isEmpty || regNoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      await supabase.from('profiles').upsert({
        'id': user!.id,
        'name': nameController.text.trim(),
        'reg_no': regNoController.text.trim().toUpperCase(),
        'department': deptController.text.trim(),
        'role_type': 'student',
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentDashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                "Complete Your\nProfile",
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Tell us a bit about yourself to get started with lab access.",
                style: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 15),
              ),
              const SizedBox(height: 40),
              
              Text("Full Name", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: InputDecoration(hintText: "Enter your full name", prefixIcon: const Icon(Icons.person_outline, size: 20)),
              ),
              
              const SizedBox(height: 24),
              Text("Registration Number", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: regNoController,
                decoration: InputDecoration(hintText: "RA2xxxxxxxxx", prefixIcon: const Icon(Icons.badge_outlined, size: 20)),
              ),
              
              const SizedBox(height: 24),
              Text("Department", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: deptController,
                decoration: InputDecoration(hintText: "e.g. CSE - Core", prefixIcon: const Icon(Icons.business_outlined, size: 20)),
              ),
              
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: loading ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: loading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : Text("Save & Continue", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
