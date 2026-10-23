import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/current_location.dart';

class RiskRadarScreen extends StatefulWidget {
  final ApiService? api;
  final Future<Position> Function()? locate;
  final Stream<Position>? positions;
  const RiskRadarScreen({super.key, this.api, this.locate, this.positions});
  @override
  State<RiskRadarScreen> createState() => _RiskRadarScreenState();
}

class _RiskRadarScreenState extends State<RiskRadarScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _foreground = true;
  Timer? _timer;
  StreamSubscription<Position>? _locations;
  Position? _requestedPosition, _assessedPosition, _pendingPosition;
  bool _refreshRequested = false;

  void _watchLocation() {
    if (_locations != null || !_foreground) return;
    // Injected location providers stay isolated from device plugins in tests.
    if (widget.locate != null && widget.positions == null) return;
    final stream = widget.positions ?? Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
    );
    _locations = stream.listen((position) {
      if (!mounted || !_foreground) return;
      final previous = _pendingPosition ?? _requestedPosition;
      if (previous == null || Geolocator.distanceBetween(previous.latitude, previous.longitude,
          position.latitude, position.longitude) >= 50) {
        _load(position: position);
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _error = 'Location tracking interrupted. Enable GPS and refresh.');
    });
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load();
    } else {
      _locations?.cancel();
      _locations = null;
      _pendingPosition = null;
    }
  }

  Future<void> _load({Position? position}) async {
    if (!mounted || !_foreground) return;
    if (_busy) {
      if (position != null) _pendingPosition = position;
      if (position == null) _refreshRequested = true;
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = position ?? await (widget.locate ?? requireCurrentLocation)();
      if (!mounted || !_foreground) return;
      final age = DateTime.now().difference(p.timestamp);
      if (age > const Duration(minutes: 2) || age < const Duration(seconds: -30)) {
        throw const ApiException('GPS returned an old location. Enable precise location and retry.');
      }
      _requestedPosition = p;
      _watchLocation();
      final data = await (widget.api ?? ApiService.instance).assessRisk(
        p.latitude,
        p.longitude,
      );
      if (mounted && _foreground && _pendingPosition == null) {
        setState(() {
          _data = data;
          _assessedPosition = p;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not refresh. Check location permission and connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        final pending = _pendingPosition;
        final refresh = _refreshRequested;
        _refreshRequested = false;
        _pendingPosition = null;
        if (_foreground && pending != null) {
          unawaited(_load(position: pending));
        } else if (_foreground && refresh) {
          unawaited(_load());
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locations?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = (_data?['score'] as num?)?.toInt() ?? 0;
    final level = _data?['risk_level'] as String? ?? '';
    final color = level == 'HIGH'
        ? Colors.red
        : level == 'MODERATE'
        ? Colors.amber
        : Colors.green;
    final weather = _data?['weather'] as Map<String, dynamic>?;
    final factors = _data?['factors'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Risk Radar'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh radar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Around your current location · 2 km',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_assessedPosition != null)
            Text('Assessed location: ${_assessedPosition!.latitude.toStringAsFixed(5)}, ${_assessedPosition!.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          if (_busy && _data != null)
            const Text('Updating for your location. Previous assessment shown.', style: TextStyle(color: Colors.blueGrey)),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$_error Previous results may be out of date.'),
              ),
            ),
          if (_data != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: score / 100,
                                strokeWidth: 12,
                                color: color,
                                backgroundColor: color.withValues(alpha: .15),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$score%',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                                Chip(
                                  key: const ValueKey('radar-status-badge'),
                                  backgroundColor: color.withValues(alpha: .18),
                                  side: BorderSide(color: color),
                                  label: Text(level),
                                  labelStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Risk index based on weather and nearby reports',
                    ),
                    const Text(
                      'This percentage is a rule-based score, not the probability of an incident.',
                    ),
                    const SizedBox(height: 12),
                    for (final factor in factors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('\u2022 $factor'),
                      ),
                    if (factors.isEmpty)
                      const Text(
                        'No scoring thresholds triggered. Missing reports do not establish safety.',
                      ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Weather',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (weather == null)
                      const Text(
                        'Weather unavailable. No weather values were assumed.',
                      )
                    else ...[
                      Text(
                        '${weather['temperature_c']} °C · Wind ${weather['wind_kmh']} km/h',
                      ),
                      Text(
                        'Precipitation: ${weather['rainfall_mm_h']} mm in the forecast hour',
                      ),
                      Text('${weather['source']} · ${weather['at']}'),
                    ],
                  ],
                ),
              ),
            ),
            Text('Updated: ${_data!['checked_at']}'),
            const Text(
              'This radar describes nearby conditions. It does not predict when a disaster will occur or assess your entire route.',
            ),
          ],
        ],
      ),
    );
  }
}
