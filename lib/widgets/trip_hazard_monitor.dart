import 'dart:async';

import 'package:flutter/material.dart';

import '../services/trip_monitor.dart';
import '../services/hazard_catalog.dart';
import '../state/active_trip_state.dart';

class TripHazardMonitor extends StatefulWidget {
  final Widget child;
  final TripMonitor? monitor;
  final ActiveTripState? tripState;
  final Duration displayDuration;
  final Duration snoozeInterval;
  const TripHazardMonitor({
    super.key,
    required this.child,
    this.monitor,
    this.tripState,
    this.displayDuration = const Duration(seconds: 20),
    this.snoozeInterval = const Duration(seconds: 90),
  });
  @override
  State<TripHazardMonitor> createState() => _TripHazardMonitorState();
}

class _TripHazardMonitorState extends State<TripHazardMonitor>
    with WidgetsBindingObserver {
  late final TripMonitor _monitor;
  late final ActiveTripState _trips;
  bool _expanded = false;
  int? _dismissedCompletion;
  bool _visible = true;
  Timer? _dismissTimer;
  Timer? _repeatTimer;
  Set<int> _previousHazardIds = {};
  String? _previousError;
  @override
  void initState() {
    super.initState();
    _monitor = widget.monitor ?? TripMonitor();
    _trips = widget.tripState ?? ActiveTripState.instance;
    WidgetsBinding.instance.addObserver(this);
    _trips.addListener(_sync);
    _monitor.onPosition = _trips.updatePosition;
    _monitor.onCompleted = _trips.markCompleted;
    _monitor.onHazards = _trips.updateActiveHazards;
    _monitor.addListener(_onMonitorUpdate);
    _sync();
    if (_monitor.hazards.isNotEmpty || _monitor.error != null) {
      _previousHazardIds = _monitor.hazards.map((h) => h.id).toSet();
      _previousError = _monitor.error;
      _showPopup();
    }
    if (widget.monitor == null) {
      HazardCatalog.instance.addListener(_hazardsChanged);
      HazardCatalog.instance.start();
    }
  }

  void _hazardsChanged() {
    final catalog = HazardCatalog.instance;
    if (!catalog.hasLoaded) return;
    _trips.reconcileHazards(catalog.activeIds);
    _monitor.reconcileHazards(catalog.activeIds);
  }

  void _onMonitorUpdate() {
    final currentIds = _monitor.hazards.map((h) => h.id).toSet();
    final currentError = _monitor.error;
    final hasHazards = _monitor.hazards.isNotEmpty;
    final hasError = currentError != null;

    if (!hasHazards && !hasError) {
      _dismissTimer?.cancel();
      _repeatTimer?.cancel();
      _repeatTimer = null;
      _previousHazardIds.clear();
      _previousError = null;
      if (_visible) {
        setState(() => _visible = false);
      }
      return;
    }

    final newHazardDetected =
        currentIds.difference(_previousHazardIds).isNotEmpty;
    final newErrorDetected =
        currentError != null && currentError != _previousError;
    _previousHazardIds = currentIds;
    _previousError = currentError;

    if (newHazardDetected || newErrorDetected) {
      _showPopup();
    } else if (!_visible && _repeatTimer == null) {
      _repeatTimer = Timer(widget.snoozeInterval, _onRepeatCheck);
    }
  }

  void _showPopup() {
    _dismissTimer?.cancel();
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (mounted) {
      setState(() => _visible = true);
    } else {
      _visible = true;
    }
    _dismissTimer = Timer(widget.displayDuration, () {
      if (!mounted) return;
      _dismissPopup();
    });
  }

  void _dismissPopup() {
    _dismissTimer?.cancel();
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (mounted) {
      setState(() => _visible = false);
    } else {
      _visible = false;
    }
    if (_monitor.hazards.isNotEmpty || _monitor.error != null) {
      _repeatTimer = Timer(widget.snoozeInterval, _onRepeatCheck);
    }
  }

  void _onRepeatCheck() {
    _repeatTimer = null;
    if (!mounted) return;
    if (_monitor.hazards.isNotEmpty || _monitor.error != null) {
      _showPopup();
    }
  }

  Color _severityColor(int severity) {
    if (severity >= 4) return const Color(0xFFDC2626); // Crimson
    if (severity == 3) return const Color(0xFFEA580C); // Vibrant Orange
    return const Color(0xFFD97706); // Amber
  }

  Color _severityBgColor(int severity) {
    if (severity >= 4) return const Color(0xFFFEF2F2);
    if (severity == 3) return const Color(0xFFFFF7ED);
    return const Color(0xFFFFFBEB);
  }

  String _severityLabel(int severity) {
    if (severity >= 4) return 'CRITICAL HAZARD';
    if (severity == 3) return 'HAZARD WARNING';
    return 'CAUTION AREA';
  }

  IconData _hazardIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('flood')) return Icons.water_drop_rounded;
    if (lower.contains('landslide')) return Icons.terrain_rounded;
    if (lower.contains('weather') || lower.contains('storm')) {
      return Icons.thunderstorm_rounded;
    }
    if (lower.contains('tide')) return Icons.waves_rounded;
    return Icons.warning_amber_rounded;
  }

  String _hazardAdvice(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('flood')) {
      return 'Stay alert and avoid the affected area if possible. Move to higher ground immediately. Never drive, walk, or swim through moving flood waters.';
    }
    if (lower.contains('landslide')) {
      return 'Stay alert and avoid the affected area if possible. Watch for falling rocks and debris. Move away from steep slopes, bluffs, and drainage valleys.';
    }
    if (lower.contains('weather') || lower.contains('storm')) {
      return 'Stay alert and avoid the affected area if possible. Seek sturdy indoor shelter immediately and stay away from windows and power lines.';
    }
    if (lower.contains('tide')) {
      return 'Stay alert and avoid the affected area if possible. Stay clear of low-lying beaches, rocks, and coastal breakwaters.';
    }
    return 'Stay alert and avoid the affected area if possible. Follow local authorities\' safety instructions and plan an alternative route.';
  }

  void _sync() =>
      _monitor.setTrip(_trips.completed ? null : _trips.trip?.route.tripId);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    _monitor.setForeground(foreground);
    if (widget.monitor == null) {
      if (foreground) {
        HazardCatalog.instance.start();
      } else {
        HazardCatalog.instance.stop();
      }
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _repeatTimer?.cancel();
    _monitor.removeListener(_onMonitorUpdate);
    if (widget.monitor == null) {
      HazardCatalog.instance.removeListener(_hazardsChanged);
      HazardCatalog.instance.stop();
    }
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
      listenable: Listenable.merge([_monitor, _trips]),
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: widget.child),
          if (_trips.completed &&
              _dismissedCompletion != _trips.trip?.route.tripId)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: AlertDialog(
                    title: const Text('Trip Completed!'),
                    content: const Text(
                      'You have safely reached your destination.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => setState(
                          () =>
                              _dismissedCompletion = _trips.trip?.route.tripId,
                        ),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if ((_monitor.hazards.isNotEmpty || _monitor.error != null) &&
              _visible)
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                  ? MediaQuery.viewInsetsOf(context).bottom + 8
                  : MediaQuery.paddingOf(context).bottom + 88,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Builder(
                    builder: (context) {
                      final hasHazards = _monitor.hazards.isNotEmpty;
                      final primary = hasHazards ? _monitor.hazards.first : null;
                      final severity = primary?.severity ?? 2;
                      final sevColor = _severityColor(severity);
                      final sevBg = _severityBgColor(severity);

                      return Material(
                        color: Colors.transparent,
                        elevation: 10,
                        shadowColor: const Color(0x331A2D4F),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: hasHazards
                                  ? sevColor.withValues(alpha: 0.35)
                                  : const Color(0xFFCBD5E1),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: hasHazards
                                    ? sevColor.withValues(alpha: 0.12)
                                    : const Color(0x140F172A),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20.5),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Top Accent Indicator Bar
                                Container(
                                  height: 4.5,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: hasHazards ? sevColor : const Color(0xFF94A3B8),
                                  ),
                                ),
                                // Main Card Body
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                                  ),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Top Interactive Header
                                        InkWell(
                                          onTap: hasHazards
                                              ? () => setState(() => _expanded = !_expanded)
                                              : null,
                                          borderRadius: BorderRadius.circular(14),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Stylized Icon Box
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    color: hasHazards ? sevBg : const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(13),
                                                    border: Border.all(
                                                      color: hasHazards
                                                          ? sevColor.withValues(alpha: 0.25)
                                                          : const Color(0xFFE2E8F0),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      hasHazards
                                                          ? _hazardIcon(primary!.type)
                                                          : Icons.cloud_off_outlined,
                                                      color: hasHazards ? sevColor : const Color(0xFF64748B),
                                                      size: 24,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),

                                                // Texts Column
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // Pill Badge Row
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 4,
                                                        crossAxisAlignment: WrapCrossAlignment.center,
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 2,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: hasHazards ? sevColor : const Color(0xFF64748B),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Container(
                                                                  width: 6,
                                                                  height: 6,
                                                                  decoration: const BoxDecoration(
                                                                    color: Colors.white,
                                                                    shape: BoxShape.circle,
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 4.5),
                                                                Text(
                                                                  hasHazards
                                                                      ? _severityLabel(primary!.severity)
                                                                      : 'MONITORING PAUSED',
                                                                  style: const TextStyle(
                                                                    fontSize: 9.5,
                                                                    fontWeight: FontWeight.w800,
                                                                    color: Colors.white,
                                                                    letterSpacing: 0.5,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          if (hasHazards && _monitor.hazards.length > 1)
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFF1F5F9),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                '+ more',
                                                                style: const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.w700,
                                                                  color: Color(0xFF475569),
                                                                ),
                                                              ),
                                                            ),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFFF1F5F9),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: const Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Icon(Icons.timer_outlined, size: 10, color: Color(0xFF64748B)),
                                                                SizedBox(width: 3),
                                                                Text(
                                                                  '20s popup',
                                                                  style: TextStyle(
                                                                    fontSize: 9.5,
                                                                    fontWeight: FontWeight.w700,
                                                                    color: Color(0xFF64748B),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 5),

                                                      // Hazard Alert Title
                                                      Text(
                                                        hasHazards
                                                            ? '${_monitor.error == null ? 'Hazard alert' : 'Last known hazard'}: ${primary!.name}'
                                                            : 'Live monitoring paused',
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 14.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: Color(0xFF0F172A),
                                                          height: 1.25,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),

                                                      // Hazard Type and Severity
                                                      if (hasHazards)
                                                        Text(
                                                          '${primary!.type.replaceAll('_', ' ')} · Severity ${primary.severity}/5'
                                                          '${_monitor.hazards.length > 1 ? ' · +${_monitor.hazards.length - 1} more' : ''}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: sevColor.withValues(alpha: 0.95),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),

                                                // Right Icons
                                                if (_monitor.error != null)
                                                  IconButton(
                                                    tooltip: 'Retry live updates',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                                    style: IconButton.styleFrom(
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      padding: EdgeInsets.zero,
                                                      minimumSize: const Size(28, 28),
                                                    ),
                                                    onPressed: _monitor.isChecking
                                                        ? null
                                                        : _monitor.poll,
                                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                                  ),
                                                if (hasHazards)
                                                  IconButton(
                                                    tooltip: _expanded
                                                        ? 'Hide hazard details'
                                                        : 'Show hazard details',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                                    style: IconButton.styleFrom(
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      padding: EdgeInsets.zero,
                                                      minimumSize: const Size(28, 28),
                                                    ),
                                                    onPressed: () => setState(
                                                      () => _expanded = !_expanded,
                                                    ),
                                                    icon: AnimatedRotation(
                                                      turns: _expanded ? 0.5 : 0,
                                                      duration: const Duration(milliseconds: 200),
                                                      child: const Icon(
                                                        Icons.keyboard_arrow_down_rounded,
                                                        size: 20,
                                                        color: Color(0xFF475569),
                                                      ),
                                                    ),
                                                  ),
                                                IconButton(
                                                  tooltip: 'Dismiss alert',
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                                  style: IconButton.styleFrom(
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: const Size(28, 28),
                                                  ),
                                                  onPressed: _dismissPopup,
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 20,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Error Box if live updates failed
                                        if (_monitor.error != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFFFECACA)),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.cloud_off_rounded, size: 16, color: Color(0xFFDC2626)),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _monitor.error!,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFFDC2626),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                        // Expanded Section
                                        if (_expanded && hasHazards) ...[
                                          const SizedBox(height: 12),
                                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                          const SizedBox(height: 12),

                                          // Safety Advisory Card
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: sevBg,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: sevColor.withValues(alpha: 0.2)),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.shield_outlined,
                                                  size: 18,
                                                  color: sevColor,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'SAFETY ADVISORY',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w800,
                                                          color: sevColor,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        _hazardAdvice(primary!.type),
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w500,
                                                          color: Color(0xFF1E293B),
                                                          height: 1.35,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Additional hazards list
                                          if (_monitor.hazards.length > 1) ...[
                                            const SizedBox(height: 10),
                                            const Text(
                                              'Other hazards on route:',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            for (final hazard in _monitor.hazards.skip(1))
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      _hazardIcon(hazard.type),
                                                      size: 16,
                                                      color: _severityColor(hazard.severity),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '${hazard.name} · ${hazard.type.replaceAll('_', ' ')} · Severity ${hazard.severity}/5',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: Color(0xFF1E293B),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],

                                          // Footer: Timestamp & Collapse
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              if (_monitor.lastCheckedAt != null)
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF94A3B8)),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Last checked: ${TimeOfDay.fromDateTime(_monitor.lastCheckedAt!).format(context)}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontSize: 11.5,
                                                            fontWeight: FontWeight.w500,
                                                            color: Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              TextButton(
                                                onPressed: () => setState(() => _expanded = false),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFF64748B),
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                child: const Text(
                                                  'Minimize',
                                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                                ),
                                              ),
                                            ],
                                          ),

                                          if (_monitor.error != null)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: Text(
                                                'This warning may be out of date until updates resume.',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontStyle: FontStyle.italic,
                                                  color: Color(0xFFB45309),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
