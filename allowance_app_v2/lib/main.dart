import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_app_v2/services/drive_service.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:allowance_shared/services/theme_store.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AllowanceApp());
}

class AllowanceApp extends StatefulWidget {
  const AllowanceApp({super.key});

  @override
  State<AllowanceApp> createState() => _AllowanceAppState();
}

class _AllowanceAppState extends State<AllowanceApp>
    with WidgetsBindingObserver {
  static const _appVersion = '2.0.37';
  final ClaimData _claimData = ClaimData();
  final DriveService _driveService = DriveService();
  final ThemeStore _themeStore = ThemeStore();
  ModernThemeId _themeId = ModernThemeId.modernMarine;
  bool _loading = true;

  /// Debounce for the Drive auto-upload. Local saves land immediately via
  /// [_onDataChanged]; uploads batch behind a longer window so daily edits
  /// cost one transfer instead of one per keystroke.
  Timer? _uploadTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
    _initTheme();
  }

  @override
  void dispose() {
    _uploadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush a pending upload now; the OS may suspend the process next.
      _uploadTimer?.cancel();
      _uploadTimer = null;
      _autoUpload();
    }
  }

  Future<void> _initTheme() async {
    final id = await _themeStore.load();
    if (mounted) setState(() => _themeId = id);
  }

  void _onThemeChanged(ModernThemeId id) {
    if (id == _themeId) return;
    setState(() => _themeId = id);
    _themeStore.save(id);
  }

  Future<void> _initData() async {
    // One-time carry-over: months written by the pre-2.0.38 local-only store
    // still sit in the documents root. Copying them into the user folder
    // (closer mirrors stay in place) keeps every existing v2 user intact
    // before the storage backbone switches to the Drive-mirror pattern.
    try {
      await _driveService.migrateDocumentsRootFiles();
    } catch (_) {
      // Storage unavailable (e.g. widget tests); the legacy fallback inside
      // loadLocalBackup covers the stragglers.
    }
    final local = await _driveService.loadLocalBackup();
    if (local != null && mounted) {
      setState(() {
        _claimData.master = local.master;
        _claimData.movements.clear();
        _claimData.movements.addAll(local.movements);
        _claimData.attShifts = AllowanceCalculator.pruneFutureShifts(local.attShifts);
        _claimData.attManualDates = local.attManualDates;
        _claimData.attLocked = local.attLocked;
        _claimData.attOffDay = local.attOffDay;
        _claimData.attRotation = local.attRotation;
        _claimData.actingAdmDates.clear();
        _claimData.actingAdmDates.addAll(local.actingAdmDates);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _onDataChanged() {
    _driveService.saveLocalBackup(_claimData);
    setState(() {});
    _scheduleAutoUpload();
  }

  void _scheduleAutoUpload() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer(const Duration(seconds: 30), () {
      _uploadTimer = null;
      _autoUpload();
    });
  }

  /// Best-effort background upload, signed-in only. Failures (offline,
  /// expired login) are silent: the local backup is the source of truth and
  /// the next success converges. Success stamps `DriveService.lastSyncTime`,
  /// which the dashboard Drive card displays.
  Future<void> _autoUpload() async {
    if (!_driveService.isSignedIn) return;
    try {
      await _driveService.uploadClaim(_claimData);
    } catch (_) {
      // Silent by design; surfaces as staleness on the Drive card instead.
    }
  }

  @override
  Widget build(BuildContext context) {
    // DynamicColorBuilder resolves the wallpaper palette on Android 12+ and
    // hands back nulls elsewhere, where buildModern falls back to the seed.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        title: 'Allowance Portal 2',
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        theme: ModernThemeData.buildModern(
          _themeId,
          dynamicScheme: _themeId.brightness == Brightness.dark
              ? darkDynamic
              : lightDynamic,
        ),
        home: _loading
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator()))
            : DashboardScreen(
                claimData: _claimData,
                driveService: _driveService,
                onDataChanged: _onDataChanged,
                themeId: _themeId,
                onThemeChanged: _onThemeChanged,
                appVersion: _appVersion,
              ),
      ),
    );
  }
}
