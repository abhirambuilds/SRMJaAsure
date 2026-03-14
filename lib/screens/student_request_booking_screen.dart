import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';

class StudentRequestBookingScreen extends StatefulWidget {
  final Map<String, dynamic> slot;
  const StudentRequestBookingScreen({super.key, required this.slot});

  @override
  State<StudentRequestBookingScreen> createState() => _StudentRequestBookingScreenState();
}

class _StudentRequestBookingScreenState extends State<StudentRequestBookingScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController reasonController = TextEditingController();
  bool loading = false;
  bool isJaAssure = false;

  @override
  void initState() {
    super.initState();
    checkProfile();
  }

  Future<void> checkProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    
    final data = await supabase.from('profiles').select('is_jaassure').eq('id', user.id).single();
    if (mounted) {
      setState(() {
        isJaAssure = data['is_jaassure'] ?? false;
      });
    }
  }

  Future<void> submitRequest() async {
    if (reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide a reason")));
      return;
    }

    setState(() => loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw "Unauthorized";

      await supabase.from('bookings').insert({
        'slot_id': widget.slot['id'],
        'student_id': user.id,
        'request_reason': reasonController.text.trim(),
        'status': 'pending', 
        'is_high_priority': isJaAssure, 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text(isJaAssure ? "Priority Request Sent!" : "Request Sent! Awaiting approval."),
             backgroundColor: AppTheme.successGreen,
           ),
        );
        Navigator.pop(context); // Back to slots
        Navigator.pop(context); // Back to dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: AppTheme.errorRed));
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, dd MMM').format(DateTime.parse(widget.slot['date']));
    final time = "${widget.slot['start_time'].toString().substring(0, 5)} - ${widget.slot['end_time'].toString().substring(0, 5)}";

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("Confirm Request", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot Info Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.calendar_month, color: AppTheme.primaryBlue),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Date", style: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 12)),
                          Text(date, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.secondaryPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.access_time, color: AppTheme.secondaryPurple),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Time Slot", style: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 12)),
                          Text(time, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            if (isJaAssure) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.jaAssureGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "JaAssure Priority Detection: You are eligible for priority booking.",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
            Text("Reason for Request", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Why do you need lab access during this slot?",
                hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: loading ? null : submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                  shadowColor: AppTheme.primaryBlue.withOpacity(0.3),
                ),
                child: loading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : Text("Confirm Request", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
