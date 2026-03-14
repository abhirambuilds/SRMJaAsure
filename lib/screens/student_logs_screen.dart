import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';

class StudentLogsScreen extends StatefulWidget {
  const StudentLogsScreen({super.key});

  @override
  State<StudentLogsScreen> createState() => _StudentLogsScreenState();
}

class _StudentLogsScreenState extends State<StudentLogsScreen> {
  final supabase = Supabase.instance.client;
  List logs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchLogs();
  }

  Future<void> fetchLogs() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final persistentLogs = await supabase
          .from('booking_logs')
          .select()
          .eq('student_id', user.id)
          .order('booking_date', ascending: false);

      if (mounted) {
        setState(() {
          logs = persistentLogs;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  String formatTime(String time) {
    try {
      if (time.contains('T')) {
          final dt = DateTime.parse(time);
          return DateFormat('h:mm a').format(dt);
      }
      final parts = time.split(":");
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final dt = DateTime(2022, 1, 1, hour, minute);
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return time;
    }
  }

  String formatDate(String dateStr) {
     try {
       final date = DateTime.parse(dateStr);
       return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("History Logs", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("No history found", style: GoogleFonts.inter(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final isApproved = log['action'] == 'approved';
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                      border: Border(
                        left: BorderSide(
                          color: isApproved ? AppTheme.successGreen : AppTheme.errorRed,
                          width: 4,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formatDate(log['booking_date']),
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                log['slot_time'] ?? "",
                                style: GoogleFonts.inter(color: Colors.grey, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    isApproved ? Icons.check_circle : Icons.cancel,
                                    size: 16,
                                    color: isApproved ? AppTheme.successGreen : AppTheme.errorRed
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isApproved ? "Approved" : "Rejected/Cancelled",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: isApproved ? AppTheme.successGreen : AppTheme.errorRed
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Faculty",
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                            ),
                            Text(
                              log['faculty_name'] ?? "Unknown",
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              ),
    );
  }
}
