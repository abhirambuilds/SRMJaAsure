import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_theme.dart';

class TeacherCreateSlotScreen extends StatefulWidget {
  const TeacherCreateSlotScreen({super.key});

  @override
  State<TeacherCreateSlotScreen> createState() => _TeacherCreateSlotScreenState();
}

class _TeacherCreateSlotScreenState extends State<TeacherCreateSlotScreen> {
  final supabase = Supabase.instance.client;

  DateTime selectedDate = DateTime.now();
  final Set<int> selectedHours = {};
  final Set<int> existingHours = {};

  bool _loading = false;
  bool _fetchingExisting = true;

  final int startLabHour = 8;
  final int endLabHour = 20; 
  final TextEditingController capacityController = TextEditingController(text: "20");

  int daysToCreate = 1;

  @override
  void initState() {
    super.initState();
    fetchExistingForDate();
  }

  @override
  void dispose() {
    capacityController.dispose();
    super.dispose();
  }

  String formatDateReadable(DateTime d) => DateFormat('EEE, dd MMM').format(d);
  String formatDateIso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String hourLabel(int hour) {
    int h = hour > 12 ? hour - 12 : (hour == 0 || hour == 12 ? 12 : hour);
    final period = hour >= 12 ? "PM" : "AM";
    return "$h:00 $period";
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: AppTheme.lightTheme.copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primaryBlue),
          ),
          child: child!,
        );
      },
    );
    if (d != null) {
      setState(() {
        selectedDate = d;
        selectedHours.clear();
        existingHours.clear();
        _fetchingExisting = true;
      });
      await fetchExistingForDate();
    }
  }

  Future<void> fetchExistingForDate() async {
    if (!mounted) return;
    setState(() => _fetchingExisting = true);
    try {
      final dateIso = formatDateIso(selectedDate);
      final res = await supabase
          .from('lab_slots')
          .select('start_time')
          .eq('date', dateIso);

      if (mounted) {
        setState(() {
          existingHours.clear();
          if (res != null) {
            for (var r in res) {
              final st = (r['start_time'] ?? '') as String;
              if (st.isEmpty) continue;
              final hour = int.tryParse(st.split(':')[0]) ?? -1;
              if (hour >= 0) existingHours.add(hour);
            }
          }
          _fetchingExisting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _fetchingExisting = false);
      }
    }
  }

  Future<void> createSlots() async {
    if (selectedHours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one hour")));
      return;
    }

    final capacity = int.tryParse(capacityController.text.trim()) ?? 20;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Confirm Slots", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text("Create ${selectedHours.length} slots for $daysToCreate days?\nStarting ${formatDateReadable(selectedDate)}.\nCapacity: $capacity per slot."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            child: const Text("Create"),
          )
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw "Not authenticated";

      List<Map<String, dynamic>> inserts = [];
      
      for (int d = 0; d < daysToCreate; d++) {
        final day = selectedDate.add(Duration(days: d));
        final dayIso = formatDateIso(day);

        for (int hour in selectedHours) {
          if (d == 0 && existingHours.contains(hour)) continue; 

          inserts.add({
            'date': dayIso,
            'start_time': "${hour.toString().padLeft(2, '0')}:00:00",
            'end_time': "${(hour + 1).toString().padLeft(2, '0')}:00:00",
            'is_available': true,
            'faculty_id': user.id,
            'capacity': capacity,
          });
        }
      }

      if (inserts.isEmpty) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No new slots created (already exist).")));
         setState(() => _loading = false);
         return;
      }

      await supabase.from('lab_slots').insert(inserts);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Created ${inserts.length} slots successfully!"),
          backgroundColor: AppTheme.successGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: AppTheme.errorRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = List<int>.generate(endLabHour - startLabHour, (i) => startLabHour + i);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text("Create Lab Slots", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: AppTheme.primaryBlue, size: 20),
                              const SizedBox(width: 12),
                              Text(formatDateReadable(selectedDate), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 12),
                         decoration: BoxDecoration(
                           border: Border.all(color: Colors.grey.shade300),
                           borderRadius: BorderRadius.circular(12),
                           color: Colors.white,
                         ),
                         child: DropdownButtonHideUnderline(
                           child: DropdownButton<int>(
                             value: daysToCreate,
                             isExpanded: true,
                             icon: const Icon(Icons.repeat, color: AppTheme.secondaryPurple),
                             style: GoogleFonts.inter(color: AppTheme.textDark, fontWeight: FontWeight.w600),
                             items: [1, 3, 5, 7, 10, 15, 30].map((d) => DropdownMenuItem(
                               value: d, 
                               child: Text(d == 1 ? "1 Day" : "$d Days"),
                             )).toList(),
                             onChanged: (v) => setState(() => daysToCreate = v ?? 1),
                           ),
                         ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: capacityController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Capacity (PCs)",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          prefixIcon: const Icon(Icons.computer, size: 20),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          Expanded(
            child: _fetchingExisting 
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: hours.length,
                  itemBuilder: (context, index) {
                    final h = hours[index];
                    final exists = existingHours.contains(h);
                    final selected = selectedHours.contains(h);
                    
                    return GestureDetector(
                      onTap: exists ? null : () {
                         setState(() {
                           if (selected) selectedHours.remove(h);
                           else selectedHours.add(h);
                         });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: exists ? Colors.grey.shade200 : (selected ? AppTheme.primaryBlue : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: exists ? Colors.transparent : (selected ? AppTheme.primaryBlue : Colors.grey.shade300)
                          ),
                          boxShadow: selected ? [
                            BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                          ] : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          hourLabel(h),
                          style: GoogleFonts.inter(
                            color: exists ? Colors.grey : (selected ? Colors.white : AppTheme.textDark),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
            ),
            child: SizedBox(
               width: double.infinity,
               height: 56,
               child: ElevatedButton(
                 onPressed: _loading ? null : createSlots,
                 style: ElevatedButton.styleFrom(
                   backgroundColor: AppTheme.successGreen,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                   elevation: 2,
                 ),
                 child: _loading 
                   ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                   : Text("Publish Slots", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
               ),
            ),
          ),
        ],
      ),
    );
  }
}
