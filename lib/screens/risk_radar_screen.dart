import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/current_location.dart';

class RiskRadarScreen extends StatefulWidget {
  const RiskRadarScreen({super.key});
  @override
  State<RiskRadarScreen> createState() => _RiskRadarScreenState();
}
class _RiskRadarScreenState extends State<RiskRadarScreen> with WidgetsBindingObserver {
  Map<String,dynamic>? _data;
  String? _error;
  bool _busy = false, _foreground = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) { if (_foreground) _load(); });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _load();
  }
  Future<void> _load() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final p = await requireCurrentLocation();
      final data = await ApiService.instance.getRiskRadar(p.latitude, p.longitude);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not refresh. Check location permission and connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final model = _data?['model'] as Map<String,dynamic>?;
    final weather = _data?['weather'] as Map<String,dynamic>?;
    final hazards = _data?['hazards'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('AI Risk Radar'), actions: [
        IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh radar'),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Around your current location · 1 km', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('$_error Previous results may be out of date.'))),
        if (_data != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Experimental AI assessment'),
            Text(model?['available'] == true ? '${model!['level']} · demonstration' : 'Assessment unavailable',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(model?['reason'] as String? ?? 'Neural network trained on synthetic examples; not validated on real incidents.'),
            const SizedBox(height: 10),
            Text('Reported hazard alert: ${_data!['hazard_alert']}'),
            Text(_data!['coverage'] as String),
          ]))),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Weather', style: TextStyle(fontWeight: FontWeight.bold)),
            if (weather == null) const Text('Weather unavailable. No weather values were assumed.')
            else ...[
              Text('${weather['temperature_c']} °C · Wind ${weather['wind_kmh']} km/h'),
              Text('Precipitation: ${weather['rainfall_mm_h']} mm in the forecast hour'),
              Text('${weather['source']} · ${weather['at']}'),
            ],
          ]))),
          Text('Nearby official / verified reports (${hazards.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final h in hazards) ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: (h['severity'] as int) >= 4 ? Colors.red : Colors.orange),
            title: Text(h['name'] as String),
            subtitle: Text('${h['type']} · severity ${h['severity']}/5'),
          ),
          Text('Updated: ${_data!['checked_at']}'),
          const Text('This radar describes nearby conditions. It does not predict when a disaster will occur or assess your entire route.'),
        ],
      ]),
    );
  }
}
