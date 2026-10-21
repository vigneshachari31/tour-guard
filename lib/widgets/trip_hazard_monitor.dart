import 'package:flutter/material.dart';

import '../services/trip_monitor.dart';
import '../state/active_trip_state.dart';

class TripHazardMonitor extends StatefulWidget {
  final Widget child;
  final TripMonitor? monitor;
  final ActiveTripState? tripState;
  const TripHazardMonitor({
    super.key,
    required this.child,
    this.monitor,
    this.tripState,
  });
  @override
  State<TripHazardMonitor> createState() => _TripHazardMonitorState();
}

class _TripHazardMonitorState extends State<TripHazardMonitor>
    with WidgetsBindingObserver {
  late final TripMonitor _monitor;
  late final ActiveTripState _trips;
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    _monitor = widget.monitor ?? TripMonitor();
    _trips = widget.tripState ?? ActiveTripState.instance;
    WidgetsBinding.instance.addObserver(this);
    _trips.addListener(_sync);
    _sync();
  }

  void _sync() => _monitor.setTrip(_trips.trip?.route.tripId);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _monitor.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _trips.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _monitor.dispose();
    super.dispose();
  }

  @override
  // MaterialApp.builder sits above the Navigator overlay. Give this app-wide
  // banner its own overlay so tooltip buttons work outside individual routes.
  Widget build(BuildContext context) => Overlay.wrap(
    child: ListenableBuilder(
      listenable: _monitor,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: widget.child),
          if (_monitor.hazards.isNotEmpty || _monitor.error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                  ? MediaQuery.viewInsetsOf(context).bottom + 8
                  : MediaQuery.paddingOf(context).bottom + 88,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    color: Colors.white,
                    elevation: 6,
                    shadowColor: const Color(0x261A2D4F),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE3E9F0)),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .3,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _monitor.hazards.isNotEmpty
                                        ? Icons.warning_amber_rounded
                                        : Icons.cloud_off_outlined,
                                    color: const Color(0xFFB74426),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _monitor.hazards.isNotEmpty
                                          ? '${_monitor.error == null ? 'Hazard alert' : 'Last known hazard'}: ${_monitor.hazards.first.name}'
                                          : 'Live monitoring paused',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A2D4F),
                                      ),
                                    ),
                                  ),
                                  if (_monitor.error != null)
                                    IconButton(
                                      tooltip: 'Retry live updates',
                                      onPressed: _monitor.isChecking
                                          ? null
                                          : _monitor.poll,
                                      icon: const Icon(Icons.refresh, size: 20),
                                    ),
                                  if (_monitor.hazards.isNotEmpty)
                                    IconButton(
                                      tooltip: _expanded
                                          ? 'Hide hazard details'
                                          : 'Show hazard details',
                                      onPressed: () => setState(
                                        () => _expanded = !_expanded,
                                      ),
                                      icon: Icon(
                                        _expanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                              if (_monitor.hazards.isNotEmpty)
                                Text(
                                  '${_monitor.hazards.first.type.replaceAll('_', ' ')} · Severity ${_monitor.hazards.first.severity}/5'
                                  '${_monitor.hazards.length > 1 ? ' · +${_monitor.hazards.length - 1} more' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF65758B),
                                  ),
                                ),
                              if (_monitor.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _monitor.error!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B5B54),
                                    ),
                                  ),
                                ),
                              if (_expanded && _monitor.hazards.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Stay alert and avoid the affected area if possible.',
                                  style: TextStyle(fontSize: 13),
                                ),
                                for (final hazard in _monitor.hazards.skip(1))
                                  Text(
                                    '${hazard.name} · ${hazard.type.replaceAll('_', ' ')} · Severity ${hazard.severity}/5',
                                  ),
                                if (_monitor.lastCheckedAt != null)
                                  Text(
                                    'Last checked: ${TimeOfDay.fromDateTime(_monitor.lastCheckedAt!).format(context)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                if (_monitor.error != null)
                                  const Text(
                                    'This warning may be out of date until updates resume.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
