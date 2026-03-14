import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/app_theme.dart';

class StudentApprovedBookingsScreen extends StatefulWidget {
  const StudentApprovedBookingsScreen({super.key});

  @override
  State<StudentApprovedBookingsScreen> createState() => _StudentApprovedBookingsScreenState();
}

class _StudentApprovedBookingsScreenState extends State<StudentApprovedBookingsScreen> {
  final supabase = Supabase.instance.client;
  List bookings = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchApprovedBookings();
  }

  Future<void> fetchApprovedBookings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('bookings')
        .select('*, lab_slots(*)') 
        .eq('student_id', user.id)
        .eq('status', 'approved') 
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        bookings = data;
        loading = false;
      });
    }
  }

  String formatTime(String time) {
    try {
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
       return DateFormat('EEE, d MMM').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("My Entry Pass", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : bookings.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.airplane_ticket_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("No active passes", style: GoogleFonts.inter(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: fetchApprovedBookings,
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final booking = bookings[index];
                    final slot = booking['lab_slots'];
                    if (slot == null) return const SizedBox.shrink();

                    final date = slot['date'] ?? slot['slot_date'];
                    final otp = booking['otp_code'] ?? '---';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))
                        ],
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryBlue,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.verified, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text("APPROVED ACCESS", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text("SRM LABS", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                                ),
                              ],
                            ),
                          ),
                          
                          // Body
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("DATE", style: GoogleFonts.inter(color: Colors.grey, fontSize: 10, letterSpacing: 1)),
                                        const SizedBox(height: 4),
                                        Text(formatDate(date), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("TIME", style: GoogleFonts.inter(color: Colors.grey, fontSize: 10, letterSpacing: 1)),
                                        const SizedBox(height: 4),
                                        Text("${formatTime(slot['start_time'])} - ${formatTime(slot['end_time'])}", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Flex(
                                      direction: Axis.horizontal,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      mainAxisSize: MainAxisSize.max,
                                      children: List.generate((constraints.constrainWidth() / 10).floor(), (index) => SizedBox(
                                        width: 5, height: 1,
                                        child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey.shade300)),
                                      )),
                                    );
                                  },
                                ),
                                const SizedBox(height: 24),
                                
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("ENTRY OTP", style: GoogleFonts.inter(color: Colors.grey, fontSize: 10, letterSpacing: 1)),
                                          const SizedBox(height: 8),
                                          Text(otp, style: GoogleFonts.chivoMono(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, letterSpacing: 2)),
                                          const SizedBox(height: 4),
                                          Text("Show this to faculty", style: GoogleFonts.inter(color: AppTheme.successGreen, fontSize: 12, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: QrImageView(
                                        data: otp,
                                        version: QrVersions.auto,
                                        size: 80.0,
                                        foregroundColor: AppTheme.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
    );
  }
}
