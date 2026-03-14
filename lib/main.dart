import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ifnaertbfklehuttrpzy.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmbmFlcnRiZmtsZWh1dHRycHp5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzNzczNTksImV4cCI6MjA4Njk1MzM1OX0.QT-TqXX0Oe9BhOHGVbLJTd3QSEIx1GGcfN1qS8WgDzI',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      detectSessionInUri: true, 
    ),
    realtimeClientOptions: const RealtimeClientOptions(),
  );

  runApp(const SRMLabAccessApp());
}

class SRMLabAccessApp extends StatelessWidget {
  const SRMLabAccessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SRM Lab Access',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, 
      home: const AuthGate(),
    );
  }
}
