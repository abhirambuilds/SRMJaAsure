import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';

class TeacherViewRequestsScreen extends StatefulWidget {
  const TeacherViewRequestsScreen({super.key});

  @override
  State<TeacherViewRequestsScreen> createState() => _TeacherViewRequestsScreenState();
}

class _TeacherViewRequestsScreenState extends State<TeacherViewRequestsScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> requests = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchRequests();
  }

  Future<void> fetchRequests() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('bookings')
          .select('*, profiles(*), lab_slots(*)')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      // Sorting logic: JaAssure first, then high priority
      if (data != null) {
        requests = data;
        requests.sort((a, b) {
          final aPri = (a['is_high_priority'] == true || (a['profiles'] != null && a['profiles']['is_jaassure'] == true)) ? 1 : 0;
          final bPri = (b['is_high_priority'] == true || (b['profiles'] != null && b['profiles']['is_jaassure'] == true)) ? 1 : 0;
          return bPri.compareTo(aPri);
        });
      }

      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _logAction(dynamic request, String action) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    
    final student = request['profiles'];
    final slot = request['lab_slots'];
    
    await supabase.from('booking_logs').insert({
      'student_id': request['student_id'],
      'student_name': student?['name'] ?? student?['full_name'] ?? 'Unknown',
      'student_reg_no': student?['reg_no'] ?? 'Unknown',
      'faculty_id': user.id,
      'faculty_name': 'Faculty', // Could fetch faculty name if needed
      'booking_date': slot?['date'],
      'slot_time': "${slot?['start_time']} - ${slot?['end_time']}",
      'action': action,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> handleAction(dynamic request, String status) async {
    try {
      await supabase.from('bookings').update({'status': status}).eq('id', request['id']);
      await _logAction(request, status);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Request ${status == 'approved' ? 'Approved' : 'Rejected'}!"),
          backgroundColor: status == 'approved' ? AppTheme.successGreen : AppTheme.errorRed,
        ));
        fetchRequests();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Action failed: $e")));
    }
  }

  Widget requestCard(dynamic request) {
    final profile = request['profiles'];
    final slot = request['lab_slots'];
    final bool isJaAssure = profile?['is_jaassure'] ?? false;
    final bool isHighPriority = request['is_high_priority'] ?? false;
    
    final dateStr = slot != null ? DateFormat('EEE, dd MMM').format(DateTime.parse(slot['date'])) : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: (isJaAssure || isHighPriority) ? AppTheme.warningOrange.withOpacity(0.3) : Colors.transparent),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                child: Text(
                  (profile?['name'] ?? 'S')[0].toUpperCase(),
                  style: GoogleFonts.outfit(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?['name'] ?? profile?['full_name'] ?? 'Unknown Student',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    Text(
                      "${profile?['reg_no'] ?? '-'} • ${profile?['department'] ?? '-'}",
                      style: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isJaAssure)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(gradient: AppTheme.jaAssureGradient, borderRadius: BorderRadius.circular(8)),
                  child: Text("JaAssure", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: AppTheme.textGrey),
              const SizedBox(width: 8),
              Text(dateStr, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 20),
              const Icon(Icons.access_time, size: 16, color: AppTheme.textGrey),
              const SizedBox(width: 8),
              Text("${slot?['start_time'].toString().substring(0,5)} - ${slot?['end_time'].toString().substring(0,5)}", 
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Reason:",
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textGrey),
          ),
          const SizedBox(height: 4),
          Text(
            request['request_reason'] ?? "No reason provided",
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => handleAction(request, 'rejected'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.errorRed),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text("Reject", style: GoogleFonts.outfit(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => handleAction(request, 'approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text("Approve", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("Access Requests", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("No pending requests", style: GoogleFonts.inter(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: fetchRequests,
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: requests.length,
                  itemBuilder: (context, index) => requestCard(requests[index]),
                ),
              ),
    );
  }
}
