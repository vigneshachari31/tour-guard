import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/current_location.dart';

/// Upload fresh SOS coordinates while the app is in the foreground.
class SosLocationMonitor extends StatefulWidget {
  final Widget child;
  const SosLocationMonitor({super.key, required this.child});
  @override
  State<SosLocationMonitor> createState() => _SosLocationMonitorState();
}
class _SosLocationMonitorState extends State<SosLocationMonitor> with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }
  Future<void> _poll() async {
    if (_busy || !_foreground) return;
    _busy = true;
    try {
      final api = ApiService.instance;
      final session = await api.getSession();
      if (session == null) return;
      final events = await api.getSosHistory();
      final active = events.where((e) => ['OPEN', 'IN_PROGRESS'].contains(e['workflow_status']));
      if (active.isEmpty || !mounted || !_foreground) return;
      final position = await requireCurrentLocation();
      if (!mounted || !_foreground || session.accessToken != (await api.getSession())?.accessToken) return;
      await api.updateSosLocation(active.first['id'] as int, position.latitude, position.longitude, position.accuracy, position.timestamp);
    } catch (_) {
      // The last GPS timestamp remains unchanged; admin UI marks it stale.
    } finally { _busy = false; }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _poll();
  }
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
