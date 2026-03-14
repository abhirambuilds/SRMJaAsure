// lib/screens/gpu_weekly_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:srm_lab_access/utils/server_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GpuWeeklyScreen extends StatefulWidget {
  const GpuWeeklyScreen({super.key});

  @override
  State<GpuWeeklyScreen> createState() => _GpuWeeklyScreenState();
}

class _GpuWeeklyScreenState extends State<GpuWeeklyScreen> {
  final supabase = Supabase.instance.client;

  // raw bookings from DB
  List<Map<String, dynamic>> rawBookings = [];
  // slot templates (id -> template)
  Map<int, Map<String, dynamic>> slotTemplates = {};
  // quick lookup: 'yyyy-mm-dd' -> { slotId: booking }
  Map<String, Map<int, Map<String, dynamic>>> bookingLookup = {};

  // current user's profile
  Map<String, dynamic>? myProfile;

  bool loading = true;
  bool bookingOpenGeneral = false;
  bool bookingOpenJaassure = false;

  // UI state: show NEXT week's Monday..Friday
  DateTime weekStart = _nextWeekMonday();
  static DateTime _nextWeekMonday() {
    final today = ServerTime.now();
    final thisWeekMonday = today.subtract(Duration(days: today.weekday - 1));
    return thisWeekMonday.add(const Duration(days: 7)); // NEXT week Monday
  }

  // selected date in the date-strip (defaults to weekStart)
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = weekStart;
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        // no user — bail out but keep UI consistent
        myProfile = null;
      } else {
        // load my profile (role_type, reg_no, name) so we can check jaassure
        final profile = await supabase
            .from('profiles')
            .select('id, name, reg_no,role, role_type')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null) myProfile = Map<String, dynamic>.from(profile);
      }

      // 1) latest booking_week (optional). If backend provides, use it (still expecting NEXT week window)
      final week = await supabase
          .from('booking_weeks')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (week != null) {
        bookingOpenGeneral = week['booking_open_general'] ?? false;
        bookingOpenJaassure = week['booking_open_jaassure'] ?? false;
      }

      if (week != null) {
        final ws = week['week_start'];
        if (ws != null) {
          weekStart = DateTime.parse(ws);
        } else {
          weekStart = _nextWeekMonday();
        }
      } else {
        // keep computed next-week monday
        weekStart = _nextWeekMonday();
      }

      // ensure selected date stays within weekStart..weekStart+4
      selectedDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

      // 2) slot templates (fixed 4 slots)
      final templates = await supabase
          .from('gpu_slot_templates')
          .select()
          .order('slot_order', ascending: true);

      slotTemplates = {};
      if (templates != null) {
        for (var t in templates) {
          slotTemplates[t['id'] as int] = Map<String, dynamic>.from(t);
        }
      }

      // 3) bookings for this week (next week)
      final startIso = DateFormat('yyyy-MM-dd').format(weekStart);
      final end = weekStart.add(const Duration(days: 4));
      final endIso = DateFormat('yyyy-MM-dd').format(end);

      // IMPORTANT: include booking_owner's profile name via relationship
      final bookings = await supabase
          .from('gpu_bookings')
          .select(
            'booking_for_date, slot_template_id, status, role_type, created_at, id, booking_owner, profiles!gpu_bookings_booking_owner_fkey(name, reg_no)',
          )
          .gte('booking_for_date', startIso)
          .lte('booking_for_date', endIso);

      rawBookings = (bookings ?? []).cast<Map<String, dynamic>>();

      // build lookup map
      bookingLookup = {};
      final myUserId = supabase.auth.currentUser?.id;

      for (var b in rawBookings) {
        final status = (b['status'] ?? '').toString().toLowerCase();
        final owner = b['booking_owner'];

        // show to everyone ONLY if approved
        if (status == 'approved') {
          final dateStr = (b['booking_for_date'] ?? '')
              .toString()
              .split('T')
              .first;
          final slotId = b['slot_template_id'] as int;
          bookingLookup[dateStr] ??= {};
          bookingLookup[dateStr]![slotId] = Map<String, dynamic>.from(b);
        }
        // show pending ONLY to the student who requested
        else if (status == 'pending' && owner == myUserId) {
          final dateStr = (b['booking_for_date'] ?? '')
              .toString()
              .split('T')
              .first;
          final slotId = b['slot_template_id'] as int;
          bookingLookup[dateStr] ??= {};
          bookingLookup[dateStr]![slotId] = Map<String, dynamic>.from(b);
        }
      }
    } catch (e) {
      // non-blocking error - show snackbar
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to load bookings: $e")));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _isBookedFor(DateTime day, int slotId) {
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    return bookingLookup[dateKey] != null &&
        bookingLookup[dateKey]!.containsKey(slotId) &&
        (bookingLookup[dateKey]![slotId]!['status']?.toString().toLowerCase() !=
            'cancelled');
  }

  Map<String, dynamic>? _getBookingFor(DateTime day, int slotId) {
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    return bookingLookup[dateKey] == null
        ? null
        : bookingLookup[dateKey]![slotId];
  }

  bool _bookingAllowedForUser() {
    final role = (myProfile?['role_type'] ?? '').toString().toLowerCase();
    final now = ServerTime.now();
    final dow = now.weekday; // 1=Mon ... 7=Sun

    // Monday–Thursday → closed
    if (dow >= DateTime.monday && dow <= DateTime.thursday) {
      return false;
    }

    // Friday → only JaAssure
    if (dow == DateTime.friday) {
      return role == 'jaassure';
    }

    // Saturday → everyone EXCEPT JaAssure
    if (dow == DateTime.saturday) {
      return role != 'jaassure';
    }

    // Sunday → closed
    return false;
  }

  Color _slotColor(Map<String, dynamic>? booking) {
    if (booking == null) return const Color(0xFF16A34A);

    final status = (booking['status'] ?? '').toString().toLowerCase();

    // RED only when admin approved
    if (status == 'approved') {
      return const Color(0xFFEF4444);
    }

    // pending/rejected should still appear available
    return const Color(0xFF16A34A);
  }

  String _slotLabel(int slotId) {
    final t = slotTemplates[slotId];
    if (t == null) return 'S$slotId';
    final start = t['start_time']?.toString() ?? '';
    final end = t['end_time']?.toString() ?? '';
    // format like 9:00 AM - 11:00 AM
    try {
      final sHour = int.parse(start.split(':').first);
      final eHour = int.parse(end.split(':').first);
      final s = _formatHourLabel(sHour);
      final e = _formatHourLabel(eHour);
      return '${t['slot_name']}\n$s - $e';
    } catch (_) {
      return t['slot_name'] ?? 'S$slotId';
    }
  }

  String _formatHourLabel(int hour24) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    var hour = hour24 % 12;
    if (hour == 0) hour = 12;
    return '$hour:00 $period';
  }

  // Opens booking UI: if already booked -> show info sheet; else navigate to details page
  Future<void> _openBookingSheet(DateTime day, int slotId) async {
    final booking = _getBookingFor(day, slotId);
    final myUser = supabase.auth.currentUser;

    // 🚫 If YOU already requested this slot
    if (booking != null &&
        booking['booking_owner'] == myUser?.id &&
        (booking['status'] ?? '').toString().toLowerCase() == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already requested this slot')),
      );
      return;
    }
    // REALTIME DB CHECK (prevents double booking)
    final fresh = await supabase
        .from('gpu_bookings')
        .select('id,status')
        .eq('slot_template_id', slotId)
        .eq('booking_for_date', DateFormat('yyyy-MM-dd').format(day))
        .eq('status', 'approved') // ← IMPORTANT CHANGE
        .limit(1)
        .maybeSingle();
    if (fresh != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This slot is already booked')),
      );
      await _loadAll();
      return;
    }

    if (fresh != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This slot was just booked by someone else'),
        ),
      );
      await _loadAll();
      return;
    }
    final slotTpl = slotTemplates[slotId];
    final slotLabel = _slotLabel(slotId);

    // If already booked -> show simple info and block booking (same behaviour as before)
    if (booking != null && booking['status'] == 'approved') {
      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          final ownerName =
              booking['profiles!gpu_bookings_booking_owner_fkey']?['name'] ??
              'Student';
          final status = booking['status'] ?? 'pending';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('EEEE, dd MMM yyyy').format(day),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(slotLabel, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 18),
                  // show generic "Booked" chip (do NOT expose JaAssure or role)
                  Chip(
                    label: const Text('Booked'),
                    backgroundColor: _slotColor(booking),
                    labelStyle: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text('Status: $status'),
                  const SizedBox(height: 12),
                  Text(
                    'Booked by: $ownerName',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 18),
                  const Text('This slot is already booked.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    // Booking allowed check
    if (!_bookingAllowedForUser()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Bookings are currently closed. Please wait until the lab admin opens booking.",
          ),
        ),
      );
      return;
    }

    // date restriction: no past bookings
    final today = ServerTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    if (day.isBefore(normalizedToday)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot book past dates')));
      return;
    }

    // NAVIGATE to full-page booking details (new page)
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingDetailsPage(
          day: day,
          slotId: slotId,
          slotTemplate: slotTpl ?? {},
          supabaseClient: supabase,
          myProfile: myProfile,
        ),
      ),
    );

    // if booking created -> refresh
    if (res == true) {
      await _loadAll();
    }
  }

  Widget _legendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  List<DateTime> _weekDays() {
    return List.generate(5, (i) => weekStart.add(Duration(days: i)));
  }

  Widget _buildDateStrip() {
    final days = _weekDays();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: days.map((d) {
          final isSelected =
              DateFormat('yyyy-MM-dd').format(d) ==
              DateFormat('yyyy-MM-dd').format(selectedDate);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedDate = DateTime(d.year, d.month, d.day);
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : Colors.grey.shade300,
                    ),
                    boxShadow: isSelected
                        ? [
                            const BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(d),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('dd MMM').format(d),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSlotsForSelectedDate() {
    final tplList = slotTemplates.entries.toList()
      ..sort(
        (a, b) =>
            (a.value['slot_order'] ?? 0).compareTo(b.value['slot_order'] ?? 0),
      );
    if (tplList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No slots configured'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadAll, child: const Text('Reload')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        children: [
          // header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text('Slots', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 12),
          // grid of slot cards (two columns)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tplList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final entry = tplList[index];
              final slotId = entry.key;
              final tpl = entry.value;
              final booking = _getBookingFor(selectedDate, slotId);
              final color = _slotColor(booking);
              final slotName = tpl['slot_name'] ?? 'Slot';
              final start = (tpl['start_time'] ?? '09:00:00').toString();
              final end = (tpl['end_time'] ?? '11:00:00').toString();
              final startHour = int.tryParse(start.split(':').first) ?? 9;
              final endHour = int.tryParse(end.split(':').first) ?? 11;
              final labelTime =
                  '${_formatHourLabel(startHour)} - ${_formatHourLabel(endHour)}';
              // NOTE: show only generic "Booked" if taken — do not reveal JaAssure
              String bookingLabel;
              final myUserId = supabase.auth.currentUser?.id;

              if (booking == null) {
                bookingLabel = 'Available';
              } else if (booking['status'] == 'approved') {
                bookingLabel = 'Booked';
              } else if (booking['booking_owner'] == myUserId) {
                bookingLabel = 'Requested';
              } else {
                bookingLabel = 'Available';
              }

              final myUser = supabase.auth.currentUser;

              bool disabled = false;

              if (booking != null) {
                final status = (booking['status'] ?? '')
                    .toString()
                    .toLowerCase();

                // approved -> nobody can click
                if (status == 'approved') disabled = true;

                // pending -> only owner cannot click again
                if (status == 'pending' &&
                    booking['booking_owner'] == myUser?.id) {
                  disabled = true;
                }
              }

              return GestureDetector(
                onTap: disabled
                    ? null
                    : () => _openBookingSheet(selectedDate, slotId),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slotName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labelTime,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bookingLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final days = _weekDays();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('SRM GPU Lab — Weekly Booking'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF1565C0), // keep top blue
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          children: [
            // Week header + legend (two states only)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Booking Week',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat('dd MMM').format(days.first)}  →  ${DateFormat('dd MMM yyyy').format(days.last)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _legendChip(const Color(0xFF16A34A), 'Available'),
                        _legendChip(const Color(0xFFEF4444), 'Booked'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // date strip (BookMyShow style)
            _buildDateStrip(),

            const SizedBox(height: 8),

            // slots for selected date
            Expanded(
              child: SingleChildScrollView(child: _buildSlotsForSelectedDate()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Booking details page (full screen) — opens when user clicks an available slot.
/// Re-uses the same RPC call `request_gpu_booking`.
class BookingDetailsPage extends StatefulWidget {
  final DateTime day;
  final int slotId;
  final Map<String, dynamic> slotTemplate;
  final SupabaseClient supabaseClient;
  final Map<String, dynamic>? myProfile;

  const BookingDetailsPage({
    required this.day,
    required this.slotId,
    required this.slotTemplate,
    required this.supabaseClient,
    required this.myProfile,
    super.key,
  });

  @override
  State<BookingDetailsPage> createState() => _BookingDetailsPageState();
}

class _BookingDetailsPageState extends State<BookingDetailsPage> {
  final _purposeController = TextEditingController();
  final _reasonController = TextEditingController();
  final _mentorNameController = TextEditingController();
  final _mentorEmailController = TextEditingController();

  // New team member controllers (form-based)
  final _teamNameController = TextEditingController();
  final _teamEmailController = TextEditingController();
  final _teamRegController = TextEditingController();

  List<Map<String, dynamic>> teamMembers = [];
  bool adding =
      false; // kept for backward compatibility with UI (not used for network)
  String addError = '';
  bool _submitting = false;
  bool _isTeam = false;

  @override
  void dispose() {
    _purposeController.dispose();
    _reasonController.dispose();
    _mentorNameController.dispose();
    _mentorEmailController.dispose();
    _teamNameController.dispose();
    _teamEmailController.dispose();
    _teamRegController.dispose();
    super.dispose();
  }

  bool get isFaculty {
    final role = (widget.myProfile?['role'] ?? '').toString().toLowerCase();
    return role == 'teacher' || role == 'faculty';
  }

  bool get isStudent {
    return !isFaculty;
  }

  bool get isJaassure {
    final role = (widget.myProfile?['role_type'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'jaassure';
  }

  String _formatHourLabel(int hour24) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    var hour = hour24 % 12;
    if (hour == 0) hour = 12;
    return '$hour:00 $period';
  }

  // Replace regno lookup with simple form-based add
  void _addMember() {
    final name = _teamNameController.text.trim();
    final email = _teamEmailController.text.trim();
    final reg = _teamRegController.text.trim();

    if (name.isEmpty || email.isEmpty || reg.isEmpty) {
      setState(() => addError = "Enter all team member details");
      return;
    }

    if (!email.toLowerCase().endsWith('@srmist.edu.in')) {
      setState(() => addError = "Must be SRM email");
      return;
    }

    if (teamMembers.length >= 3) {
      setState(() => addError = "Max 4 including leader");
      return;
    }

    setState(() {
      teamMembers.add({"name": name, "email": email, "regno": reg});

      _teamNameController.clear();
      _teamEmailController.clear();
      _teamRegController.clear();
      addError = "";
    });
  }

  Future<void> _submit() async {
    final purpose = _purposeController.text.trim();
    final reason = _reasonController.text.trim();

    final teamJson = (isFaculty || isJaassure) ? [] : teamMembers;
    final role = (widget.myProfile?['role_type'] ?? '')
        .toString()
        .toLowerCase();

    if (isStudent && !isJaassure) {
      final email = _mentorEmailController.text.trim();
      if (_mentorNameController.text.trim().isEmpty || email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter mentor details')),
        );
        return;
      }
      if (!email.contains('@') || !email.contains('.')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid mentor email')),
        );
        return;
      }
    }
    if (purpose.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please add purpose')));
      return;
    }

    try {
      setState(() => _submitting = true);
      final bookingDate = DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
      );
      // send teamMembers (list of {name,email,regno}) to RPC
      final res = await widget.supabaseClient.rpc(
        'request_gpu_booking',
        params: {
          'p_slot_id': widget.slotId,
          'p_booking_date': bookingDate.toIso8601String().split('T').first,
          'p_reason': reason.isEmpty ? 'GPU Lab Usage' : reason,
          'p_purpose': purpose,
          'p_team_members': teamJson,
        },
      );

      if (!mounted) return;

      setState(() => _submitting = false);

      if (res == 'SUCCESS' || res == 'AUTO_APPROVED') {
        // Inform the creator appropriately (this snackbar is shown only to the creator)
        if ((widget.myProfile?['role_type'] ?? '') == 'jaassure') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking confirmed instantly (JaAssure)'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking sent for mentor approval')),
          );
        }
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res.toString())));
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tpl = widget.slotTemplate;
    final start = (tpl['start_time'] ?? '09:00:00').toString();
    final end = (tpl['end_time'] ?? '11:00:00').toString();
    final sHour = int.tryParse(start.split(':').first) ?? 9;
    final eHour = int.tryParse(end.split(':').first) ?? 11;
    final dateStr = DateFormat('EEE, dd MMM yyyy').format(widget.day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Booking'),
        backgroundColor: const Color(0xFF1565C0),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(
                  0xFF16A34A,
                ), // green header for available booking flow
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${tpl['slot_name'] ?? 'Slot'} · ${_formatHourLabel(sHour)} - ${_formatHourLabel(eHour)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ======= PURPOSE (compact single-line) =======
            TextField(
              controller: _purposeController,
              decoration: InputDecoration(
                labelText: 'Purpose ',
                hintText: 'e.g., Model training / Project work',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 1,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // ======= REASON (explicitly brief) =======
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (brief)',
                hintText: 'Write a short explanation ',
                alignLabelWithHint:
                    true, // important for multiline like address field
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              minLines: 2, // starts like address field
              maxLines: 4, // expands up to 4 lines
              textInputAction: TextInputAction.newline,
            ),

            const SizedBox(height: 12),

            if (isStudent && !isJaassure) ...[
              const SizedBox(height: 8),
              const Text(
                'Mentor Details (Required)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _mentorNameController,
                decoration: InputDecoration(
                  labelText: 'Mentor Name',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mentorEmailController,
                decoration: InputDecoration(
                  labelText: 'Mentor Email',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ======= TEAM HEADER with improved switch (purple) =======
            if (isStudent && !isJaassure) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Team (optional, max 4 including leader)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch(
                    value: _isTeam,
                    onChanged: (v) => setState(() => _isTeam = v),
                    activeColor: const Color(0xFFFFFFFF),
                    activeTrackColor: const Color(0xFF7C3AED),
                    inactiveThumbColor: Colors.grey.shade300,
                    inactiveTrackColor: Colors.grey.shade300,
                  ),
                ],
              ),
            ],
            // Animated show/hide team area
            if (isStudent && !isJaassure)
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _isTeam
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 6),
                          // compact row for name + regno on larger screens, otherwise stacked
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth > 520) {
                                // place name and reg side-by-side if wide
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: _teamNameController,
                                        decoration: const InputDecoration(
                                          hintText: 'Member name',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _teamRegController,
                                        decoration: const InputDecoration(
                                          hintText: 'Reg No',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    TextField(
                                      controller: _teamNameController,
                                      decoration: const InputDecoration(
                                        hintText: 'Member name',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _teamRegController,
                                      decoration: const InputDecoration(
                                        hintText: 'Reg No',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _teamEmailController,
                            decoration: const InputDecoration(
                              hintText:
                                  'Member SRM email (must end with @srmist.edu.in)',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _addMember,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Add Member'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    teamMembers.clear();
                                    addError = '';
                                  });
                                },
                                child: const Text('Clear Members'),
                              ),
                            ],
                          ),
                          if (addError.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                addError,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 8),
                          // show max hint + members as chips (compact)
                          Row(
                            children: [
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Max 4 including leader',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (teamMembers.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: teamMembers.map((m) {
                                return Chip(
                                  label: Text('${m['name']} • ${m['regno']}'),
                                  avatar: const CircleAvatar(
                                    child: Icon(Icons.person, size: 16),
                                  ),
                                  deleteIcon: const Icon(Icons.close),
                                  onDeleted: () {
                                    setState(() {
                                      teamMembers.removeWhere(
                                        (x) => x['regno'] == m['regno'],
                                      );
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 12),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Book slot'),
              ),
            ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
