import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/app_theme.dart';
import 'student_request_booking_screen.dart';

class StudentViewSlotsScreen extends StatefulWidget {
  const StudentViewSlotsScreen({super.key});

  @override
  State<StudentViewSlotsScreen> createState() => _StudentViewSlotsScreenState();
}

class _StudentViewSlotsScreenState extends State<StudentViewSlotsScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> slotGroups = [];
  bool loading = true;
  bool bookingsEnabled = true;

  @override
  void initState() {
    super.initState();
    fetchSlots();
  }

  Future<void> fetchSlots() async {
    try {
      // 1. Check if bookings are enabled
      final settings = await supabase.from('lab_settings').select('is_booking_enabled').single();
      bookingsEnabled = settings['is_booking_enabled'] ?? true;

      if (!bookingsEnabled) {
         if (mounted) setState(() => loading = false);
         return;
      }

      // 2. Fetch slots and existing bookings count
      final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      final slotData = await supabase
          .from('lab_slots')
          .select('*, bookings(count)')
          .gte('date', todayIso)
          .eq('is_available', true)
          .order('date')
          .order('start_time');

      // Group by date
      Map<String, List<dynamic>> grouped = {};
      for (var slot in slotData) {
        final d = slot['date'];
        if (!grouped.containsKey(d)) grouped[d] = [];
        grouped[d]!.add(slot);
      }

      if (mounted) {
        setState(() {
          slotGroups = grouped.entries.toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget slotTile(Map<String, dynamic> slot) {
    final int capacity = slot['capacity'] ?? 20;
    final int bookedCount = (slot['bookings'] as List).isNotEmpty ? slot['bookings'][0]['count'] : 0;
    final int remaining = capacity - bookedCount;
    final bool isFull = remaining <= 0;
    
    final startTime = slot['start_time'].toString().substring(0, 5);
    final endTime = slot['end_time'].toString().substring(0, 5);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isFull ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isFull ? Colors.grey.shade200 : Colors.white),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isFull ? Colors.grey.shade100 : AppTheme.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.access_time, color: isFull ? Colors.grey : AppTheme.primaryBlue),
        ),
        title: Text(
          "$startTime - $endTime",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: isFull ? Colors.grey : AppTheme.textDark),
        ),
        subtitle: Text(
          isFull ? "Fully Booked" : "$remaining Spots Remaining",
          style: GoogleFonts.inter(fontSize: 13, color: isFull ? Colors.grey : AppTheme.successGreen, fontWeight: FontWeight.w600),
        ),
        trailing: isFull 
          ? const Icon(Icons.block, color: Colors.grey, size: 20)
          : ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentRequestBookingScreen(slot: slot)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("Book", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("Available Slots", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : !bookingsEnabled
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_clock, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("Booking is currently disabled", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text("Please check back later during the lab window.", textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: fetchSlots,
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: slotGroups.length,
                  itemBuilder: (context, index) {
                    final date = slotGroups[index].key;
                    final slots = slotGroups[index].value;
                    final formattedDate = DateFormat('EEEE, dd MMM').format(DateTime.parse(date));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            formattedDate,
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                          ),
                        ),
                        ...slots.map<Widget>((s) => slotTile(s)).toList(),
                        const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ),
    );
  }
}
