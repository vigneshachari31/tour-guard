import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/current_location.dart';

class TouristReportAlerts extends StatefulWidget {
  final ApiService? api;
  final Future<LatLng> Function()? locate;
  const TouristReportAlerts({super.key, this.api, this.locate});
  @override
  State<TouristReportAlerts> createState() => _TouristReportAlertsState();
}

class _TouristReportAlertsState extends State<TouristReportAlerts> {
  List<Map<String, dynamic>>? _reports;
  String? _error;
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final LatLng point;
      if (widget.locate != null) {
        point = await widget.locate!();
      } else {
        final gps = await requireCurrentLocation();
        point = LatLng(gps.latitude, gps.longitude);
      }
      final reports = await (widget.api ?? ApiService.instance)
          .getNearbyTouristReports(point.latitude, point.longitude);
      if (mounted) {
        setState(() {
          _reports = reports;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException ? error.message : 'Nearby reports unavailable. Check location permission and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'TOURIST REPORTS NEAR YOU',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Refresh tourist reports',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const Text('Within 2 km of your current location'),
      if (_busy && _reports == null) const LinearProgressIndicator(),
      if (_error != null)
        Text('$_error${_reports == null ? '' : ' Showing previous reports.'}'),
      if (_reports != null && _reports!.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('No nearby tourist reports.'),
        ),
      for (final report in _reports ?? <Map<String, dynamic>>[])
        Card(
          child: ListTile(
            leading: Icon(
              Icons.warning_amber_rounded,
              color: (report['severity'] as int) >= 4
                  ? Colors.red
                  : Colors.orange,
            ),
            title: Text(report['name'] as String),
            subtitle: Text(
              '${report['hazard_type']} - Severity ${report['severity']}/5\n${report['status'] == 'verified' ? 'Admin verified' : 'Awaiting verification'}',
            ),
            isThreeLine: true,
          ),
        ),
      const SizedBox(height: 16),
    ],
  );
}
