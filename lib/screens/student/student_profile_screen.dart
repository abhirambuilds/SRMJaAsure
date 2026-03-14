import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth_gate.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {

  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();
  final regController = TextEditingController();
  final sectionController = TextEditingController();
  final deptController = TextEditingController();

  String? selectedYear;

  bool loading = false;

  // ---------- VALIDATION ----------
  bool _validateRegNo(String reg) {
    // SRM RegNo format usually RAxxxxxxxxxxxxx
    if (reg.length < 10) return false;
    if (!reg.toUpperCase().startsWith("RA")) return false;
    return true;
  }

  Future<void> saveProfile() async {

    final reg = regController.text.trim().toUpperCase();

    if (nameController.text.isEmpty ||
        reg.isEmpty ||
        sectionController.text.isEmpty ||
        deptController.text.isEmpty ||
        selectedYear == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    if (!_validateRegNo(reg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid Register Number")),
      );
      return;
    }

    setState(() => loading = true);

    final user = supabase.auth.currentUser;

    try {

      await supabase.from('profiles').upsert({
        'id': user!.id,
        'name': nameController.text.trim(),
        'reg_no': reg,
        'department': deptController.text.trim().toUpperCase(),
        'year': selectedYear,
        'section': sectionController.text.trim().toUpperCase(),
        'role': 'student',
      });

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );

    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => loading = false);
  }

  Widget field(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF4F6FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final email = supabase.auth.currentUser?.email ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),

      appBar: AppBar(
        title: const Text("Student Verification"),
        automaticallyImplyLeading: false,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            children: [

              const SizedBox(height: 10),

              Image.asset('assets/images/srm_logo.png', height: 85),

              const SizedBox(height: 20),

              const Text(
                "Identity Verification Required",
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              const Text(
                "Please verify your student details before accessing the JaAssure Laboratory booking system.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 22),

              // EMAIL
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email, color: Color(0xFF1565C0)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // FORM
              field("Full Name", nameController, Icons.person),
              field("Register Number (RAxxxxxxxxxxxx)", regController, Icons.badge),
              field("Department (CSE, IT, ECE...)", deptController, Icons.school),

              // YEAR DROPDOWN
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: DropdownButtonFormField<String>(
                  value: selectedYear,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.calendar_today),
                    labelText: "Year",
                    filled: true,
                    fillColor: const Color(0xFFF4F6FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: "1st Year", child: Text("1st Year")),
                    DropdownMenuItem(value: "2nd Year", child: Text("2nd Year")),
                    DropdownMenuItem(value: "3rd Year", child: Text("3rd Year")),
                    DropdownMenuItem(value: "4th Year", child: Text("4th Year")),
                  ],
                  onChanged: (value) {
                    setState(() => selectedYear = value);
                  },
                ),
              ),

              field("Section", sectionController, Icons.group),

              const SizedBox(height: 25),

              loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: saveProfile,
                        child: const Text("Verify & Continue"),
                      ),
                    ),

              const SizedBox(height: 16),

              const Text(
                "Incorrect details may lead to booking rejection.",
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
