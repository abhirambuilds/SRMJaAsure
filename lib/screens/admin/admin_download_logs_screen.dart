import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cross_file/cross_file.dart';

class AdminDownloadLogsScreen extends StatefulWidget {
  const AdminDownloadLogsScreen({super.key});

  @override
  State<AdminDownloadLogsScreen> createState() =>
      _AdminDownloadLogsScreenState();
}

class _AdminDownloadLogsScreenState extends State<AdminDownloadLogsScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  List<Map<String, dynamic>> weeks = [];

  @override
  void initState() {
    super.initState();
    _loadWeeks();
  }

  Future<void> _loadWeeks() async {
    setState(() => loading = true);

    try {
      final raw = await supabase
          .from('booking_weeks')
          .select('id, week_start, week_end')
          .order('week_start', ascending: false);

      weeks = List<Map<String, dynamic>>.from(raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed loading weeks: $e")));
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _downloadWeek(Map<String, dynamic> week) async {
    final weekId = week['id'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await supabase
          .from('gpu_bookings')
          .select('''
      booking_for_date,
      status,
      purpose,
      role_type,
      profiles!gpu_bookings_booking_owner_fkey(name, reg_no, department),
      gpu_slot_templates(start_time, end_time)
    ''')
          .eq('week_id', weekId);

      if (Navigator.canPop(context)) Navigator.pop(context);

      if (res.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No data for this week")));
        return;
      }

      // ================= EXCEL CREATION =================

      final excel = Excel.createExcel();
      final sheet = excel[excel.sheets.keys.first]!;

      sheet.appendRow([
        'Date',
        'Student Name',
        'Reg No',
        'Department',
        'Slot',
        'Role Type',
        'Status',
        'Purpose',
      ]);
      for (final r in res) {
        final profile = r['profiles'] ?? {};
        final slot = r['gpu_slot_templates'] ?? {};

        final slotLabel =
            "${slot['start_time'] ?? ''} - ${slot['end_time'] ?? ''}";

        sheet.appendRow([
          r['booking_for_date']?.toString() ?? '',
          profile['name'] ?? '',
          profile['reg_no'] ?? '',
          profile['department'] ?? '',
          slotLabel,
          r['role_type'] ?? '',
          r['status'] ?? '',
          r['purpose'] ?? '',
        ]);
      }

      final encoded = excel.encode();
      if (encoded == null || encoded.isEmpty) {
        throw Exception("Excel generation failed");
      }

      final bytes = Uint8List.fromList(encoded);

      // ================= SAVE FILE =================

      final dir = await getApplicationDocumentsDirectory();

      final fileName =
          "gpu_week_${weekId}_${DateTime.now().millisecondsSinceEpoch}.xlsx";

      final filePath = "${dir.path}/${fileName}";
      final file = File(filePath);

      await file.writeAsBytes(bytes, flush: true);

      // ================= SHARE SHEET =================

      final box = context.findRenderObject() as RenderBox?;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: "GPU Weekly Report",
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Excel ready (share sheet opened)")),
      );
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  Widget _weekCard(Map<String, dynamic> week) {
    final start = DateTime.parse(week['week_start']);
    final end = DateTime.parse(week['week_end']);

    final label =
        "${DateFormat('dd MMM yyyy').format(start)}  →  ${DateFormat('dd MMM yyyy').format(end)}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          title: const Text(
            "Weekly GPU Usage Report",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label),
          ),
          trailing: SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _downloadWeek(week),
              icon: const Icon(Icons.download, size: 18),
              label: const Text("Export"),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Download Logs")),
      backgroundColor: const Color(0xFFF4F6FA),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : weeks.isEmpty
          ? const Center(child: Text("No booking weeks found"))
          : RefreshIndicator(
              onRefresh: _loadWeeks,
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: weeks.length,
                itemBuilder: (context, i) => _weekCard(weeks[i]),
              ),
            ),
    );
  }
}
