import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServerTime {
  static DateTime? _serverNow;
  static DateTime? _deviceFetchMoment;
  static Timer? _resyncTimer;

  /// Call once after login (AuthGate already does)
  static Future<void> sync() async {
    final supabase = Supabase.instance.client;

    try {
      final res = await supabase.rpc('get_app_time');

      if (res == null) return;

      _serverNow = DateTime.parse(res.toString());
      _deviceFetchMoment = DateTime.now();

      // 🔴 IMPORTANT: start auto resync
      _startAutoResync();
    } catch (_) {}
  }

  static void _startAutoResync() {
    _resyncTimer?.cancel();

    // resync every 60 seconds
    _resyncTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final supabase = Supabase.instance.client;
      try {
        final res = await supabase.rpc('get_app_time');
        if (res != null) {
          _serverNow = DateTime.parse(res.toString());
          _deviceFetchMoment = DateTime.now();
        }
      } catch (_) {}
    });
  }

  /// behaves like DateTime.now() but from server
  static DateTime now() {
    if (_serverNow == null || _deviceFetchMoment == null) {
      return DateTime.now();
    }

    final passed = DateTime.now().difference(_deviceFetchMoment!);
    return _serverNow!.add(passed);
  }
}