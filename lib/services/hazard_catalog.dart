import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Shared authoritative active list. Errors must never masquerade as deletions.
class HazardCatalog extends ChangeNotifier {
  static final instance = HazardCatalog();
  final ApiService api;
  HazardCatalog({ApiService? api}) : api = api ?? ApiService.instance;
  List<AdminHazard> items = [];
  bool hasLoaded = false;
  bool _busy = false;
  Timer? _timer;
  Set<int> get activeIds => items.map((h) => h.id).toSet();
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    unawaited(refresh());
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      items = await api.getActiveHazardZones();
      hasLoaded = true;
      notifyListeners();
    } catch (_) {
      // Preserve the last verified list on transport/server failures.
    } finally {
      _busy = false;
    }
  }
}
