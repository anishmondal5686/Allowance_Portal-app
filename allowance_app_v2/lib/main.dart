import 'package:flutter/material.dart';
import 'models/claim_data.dart';
import 'services/local_store.dart';
import 'services/theme_store.dart';
import 'theme/modern_theme.dart';
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

class _AllowanceAppState extends State<AllowanceApp> {
  final ClaimData _claimData = ClaimData();
  final LocalStore _localStore = LocalStore();
  final ThemeStore _themeStore = ThemeStore();
  ModernThemeId _themeId = ModernThemeId.modernMarine;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initData();
    _initTheme();
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
    final local = await _localStore.load();
    if (local != null && mounted) {
      setState(() {
        _claimData.master = local.master;
        _claimData.movements.clear();
        _claimData.movements.addAll(local.movements);
        _claimData.attShifts = local.attShifts;
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
    _localStore.save(_claimData);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Allowance Portal 2',
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: ModernThemeData.buildModern(_themeId),
      home: _loading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()))
          : DashboardScreen(
              claimData: _claimData,
              onDataChanged: _onDataChanged,
              themeId: _themeId,
              onThemeChanged: _onThemeChanged,
            ),
    );
  }
}
