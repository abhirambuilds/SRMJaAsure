import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: '',
    anonKey:
        '',
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
