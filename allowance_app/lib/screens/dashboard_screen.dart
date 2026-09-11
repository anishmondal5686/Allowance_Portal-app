import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:allowance_shared/services/update_service.dart';
import 'package:allowance_app/services/drive_service.dart';
import 'package:allowance_shared/theme/modern_theme.dart';
import 'attendance_screen.dart';
import 'claim_summary_screen.dart';
import 'movement_screen.dart';

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class DashboardScreen extends StatefulWidget {
  final ClaimData claimData;
  final DriveService driveService;
  final VoidCallback onDataChanged;
  final ModernThemeId themeId;
  final ValueChanged<ModernThemeId> onThemeChanged;
  final String appVersion;

  const DashboardScreen({
    super.key,
    required this.claimData,
    required this.driveService,
    required this.onDataChanged,
    required this.themeId,
    required this.onThemeChanged,
    required this.appVersion,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  late int _selectedMonth;
  late int _selectedYear;
  String _currentDesignation = '';
  late DateTime _sunDate;

  Set<String> _savedMonths = {};
  bool _syncing = false;
  String _syncStatus = '';
  late String _savedBaselineGlyph;

  static const _designationOptions = [
    ('BERTHING PILOT', Icons.directions_boat_outlined),
    ('DOCK PILOT', Icons.anchor_outlined),
    ('ADM', Icons.supervisor_account_outlined),
  ];

  String _normalizeDesignation(String d) {
    final upper = d.toUpperCase();
    if (upper.contains('ADM') || upper.contains('ASSISTANT DOCK MASTER')) {
      return 'ADM';
    }
    if (upper.contains('BERTHING')) return 'BERTHING PILOT';
    return 'DOCK PILOT';
  }

  @override
  void initState() {
    super.initState();
    final m = widget.claimData.master;
    final now = DateTime.now();
    final parsed = MasterData.parseMonthYear(m.month);
    _selectedYear = parsed?.$1 ?? now.year;
    _selectedMonth = parsed?.$2 ?? now.month;
    _currentDesignation = _normalizeDesignation(m.designation);
    _sunDate = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _savedBaselineGlyph = _currentEditGlyph();
    });
    _refreshSavedMonths();
  }

  Future<void> _refreshSavedMonths() async {
    try {
      final list = await widget.driveService.listSavedMonths();
      if (!mounted) return;
      setState(() => _savedMonths = list.toSet());
    } catch (_) {
      // Storage may be unavailable (e.g. in widget tests); just skip markers.
    }
  }

  Future<void> _checkForUpdate({bool manual = false}) async {
    final info = await UpdateService.checkForUpdate(widget.appVersion,
        appVariant: 'v1');
    if (!mounted) return;
    if (info == null) {
      if (manual) _showSnack('You are up to date (v${widget.appVersion})');
      return;
    }
    _showUpdateDialog(info);
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(info: info),
    );
  }

  void _saveMaster() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.saveAndValidate()) return;
    final values = formState.value;
    widget.claimData.master = MasterData(
      month: MasterData.monthKey(_selectedYear, _selectedMonth),
      name: (values['name'] as String).trim().toUpperCase(),
      designation: values['designation'] as String,
      employee: (values['employee'] as String).trim(),
      sapEmployeeId: (values['sapEmployeeId'] as String).trim(),
      pay: (values['pay'] as String).trim(),
      bill: (values['bill'] as String).trim(),
      basic: (values['basic'] as String).trim(),
      ada: (values['ada'] as String).trim(),
    );
    widget.onDataChanged();
    _refreshSavedMonths();
    _showSnack('Master data saved');
  }

  void _applyMaster(MasterData m) {
    final parsed = MasterData.parseMonthYear(m.month);
    _selectedYear = parsed?.$1 ?? DateTime.now().year;
    _selectedMonth = parsed?.$2 ?? DateTime.now().month;
    // FormBuilder fields will be updated via initialValue on rebuild
    _formKey.currentState?.patchValue({
      'name': m.name,
      'designation': _normalizeDesignation(m.designation),
      'employee': m.employee,
      'sapEmployeeId': m.sapEmployeeId,
      'pay': m.pay,
      'bill': m.bill,
      'basic': m.basic,
      'ada': m.ada,
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// A serialization of the claim as it currently appears on screen, including
  /// any uncommitted master-form edits. Comparing this to the last-persisted
  /// glyph tells us whether the user has unsaved changes.
  String _currentEditGlyph() {
    final formState = _formKey.currentState;
    formState?.save();
    final values = formState?.value ?? {};
    final data = widget.claimData.toJson();
    data['master'] = {
      'month': MasterData.monthKey(_selectedYear, _selectedMonth),
      'name': (values['name'] as String?)?.trim().toUpperCase() ?? '',
      'designation': values['designation'] as String? ?? '',
      'employee': (values['employee'] as String?)?.trim() ?? '',
      'sapEmployeeId': (values['sapEmployeeId'] as String?)?.trim() ?? '',
      'pay': (values['pay'] as String?)?.trim() ?? '',
      'bill': (values['bill'] as String?)?.trim() ?? '',
      'basic': (values['basic'] as String?)?.trim() ?? '',
      'ada': (values['ada'] as String?)?.trim() ?? '',
    };
    return jsonEncode(data);
  }

  bool get _hasUnsavedChanges =>
      _currentEditGlyph() != _savedBaselineGlyph;

  /// Result of the unsaved-changes confirmation dialog: true = explicit save,
  /// false = discard and continue. Returns null if the user cancelled.
  Future<bool?> _confirmDiscardChanges() async {
    return showDialog<bool?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
            'There are changes that have not been explicitly saved.\n\n'
            'Save them to this device, or discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveLocal() {
    _saveMaster();
    _savedBaselineGlyph = _currentEditGlyph();
    _showSnack('Saved to this device');
  }

  void _openSummary() {
    _saveMaster();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClaimSummaryScreen(
          claimData: widget.claimData,
          onChanged: widget.onDataChanged,
        ),
      ),
    );
  }

  Future<void> _exportJson() async {
    _saveMaster();
    try {
      final jsonStr = const JsonEncoder.withIndent('  ')
          .convert(widget.claimData.toJson());
      final dir = await getTemporaryDirectory();
      final name = widget.claimData.master.month.isNotEmpty
          ? DriveService.monthFileName(widget.claimData.master.month)
          : 'allowance-data.json';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(jsonStr);
      await SharePlus.instance.share(ShareParams(
        title: 'Export Allowance Data',
        files: [XFile(file.path, mimeType: 'application/json')],
      ));
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  Future<void> _importJson() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final data =
          ClaimData.fromJson(jsonDecode(content) as Map<String, dynamic>);
      widget.claimData.master = data.master;
      widget.claimData.movements
        ..clear()
        ..addAll(data.movements);
      widget.claimData.attManualDates = data.attManualDates;
      widget.claimData.attLocked = data.attLocked;
      widget.claimData.attOffDay = data.attOffDay;
      widget.claimData.attRotation = data.attRotation;
      final parsed = MasterData.parseMonthYear(data.master.month);
      widget.claimData.attShifts = AllowanceCalculator.pruneFutureShifts(
          parsed == null
              ? data.attShifts
              : AllowanceCalculator.fillRoster(
                  year: parsed.$1,
                  month: parsed.$2,
                  offDay: data.attOffDay,
                  rotation: data.attRotation,
                  existing: data.attShifts));
      _applyMaster(data.master);
      widget.onDataChanged();
      if (mounted) setState(() {});
      _showSnack('Data imported successfully');
    } catch (e) {
      _showSnack('Import failed: invalid JSON');
    }
  }

  Future<void> _syncToDrive() async {
    setState(() => _syncing = true);
    try {
      _saveMaster();
      final result = await widget.driveService.uploadClaim(widget.claimData);
      await widget.driveService.saveLocalBackup(widget.claimData);
      _savedBaselineGlyph = _currentEditGlyph();
      if (result.success) {
        setState(() => _syncStatus = 'Synced to Drive');
        _showSnack('Uploaded to Drive');
      } else {
        setState(() => _syncStatus = 'Sync failed: ${result.error}');
        _showSnack('Upload failed: ${result.error}');
      }
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<void> _syncFromDrive() async {
    setState(() => _syncing = true);
    try {
      final currentMonth = MasterData.monthKey(_selectedYear, _selectedMonth);
      var result = currentMonth.isNotEmpty
          ? await widget.driveService.downloadClaim(
              target: widget.claimData,
              fileName: DriveService.monthFileName(currentMonth),
            )
          : SyncResult(false, 'No file found');
      if (!result.success) {
        final picked = await _pickMonthFileFromDrive();
        if (picked == null) return;
        result = await widget.driveService.downloadClaim(
          target: widget.claimData,
          fileName: picked,
        );
      }
      if (result.success) {
        _applyMaster(widget.claimData.master);
        widget.onDataChanged();
        setState(() => _syncStatus = 'Loaded from Drive');
        _showSnack('Data loaded from Drive');
      } else {
        setState(() => _syncStatus = 'Download failed: ${result.error}');
        _showSnack('Download failed: ${result.error}');
      }
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<String?> _pickMonthFileFromDrive() async {
    final files = await widget.driveService.listDriveFiles();
    if (files.isEmpty) {
      _showSnack('No saved data found on Drive');
      return null;
    }
    if (mounted) {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select month'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: files
                  .map((f) => ListTile(
                        title: Text(f.replaceAll('.json', '')),
                        onTap: () => Navigator.pop(context, f),
                      ))
                  .toList(),
            ),
          ),
        ),
      );
      return picked;
    }
    return null;
  }

  Future<void> _handleDriveSignIn() async {
    final result = await widget.driveService.signIn();
    if (!result.success) {
      if (mounted) _showSnack('Sign-in failed: ${result.error}');
      return;
    }
    final local = await widget.driveService.loadLocalBackup();
    if (local != null) {
      if (!mounted) return;
      final useLocal = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Local Backup Found'),
          content: const Text('Load local backup or fetch from Drive?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Fetch from Drive')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Load Local')),
          ],
        ),
      );
      if (useLocal == true) {
        _applyMaster(local.master);
        widget.claimData.movements
          ..clear()
          ..addAll(local.movements);
        widget.claimData.attShifts = local.attShifts;
        widget.claimData.attManualDates = local.attManualDates;
        widget.claimData.attLocked = local.attLocked;
        widget.claimData.attOffDay = local.attOffDay;
        widget.claimData.attRotation = local.attRotation;
        widget.onDataChanged();
        setState(() {});
        _showSnack('Loaded local backup');
      } else {
        await _syncFromDrive();
      }
    }
    setState(() {});
  }

  int get _movementCount =>
      AllowanceCalculator.movementsForMonth(widget.claimData).length;
  int get _attendanceCount {
    const working = {'N', 'E', 'M', 'P', 'BOOKED'};
    var count = 0;
    AllowanceCalculator.effectiveAttShifts(widget.claimData)
        .forEach((k, v) {
      if (!working.contains(v)) return;
      final p = k.split('-');
      if (p.length < 2) return;
      final y = int.tryParse(p[0]);
      final mo = int.tryParse(p[1]);
      if (y == _selectedYear && mo == _selectedMonth) count++;
    });
    return count;
  }

  Widget _buildSummarySection(ColorScheme scheme) {
    final summary = AllowanceCalculator.computeSummary(widget.claimData);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryHeroCard(
          grandTotal: summary.grandTotal,
          activeClaims: summary.lines.length,
          movements: _movementCount,
          workingDays: _attendanceCount,
        )
            .animate()
            .fade(duration: 400.ms)
            .slideY(begin: 0.1, end: 0),
        const SizedBox(height: 12),
        if (summary.lines.isEmpty)
          Text(
            'No payable claim rows yet. Enter movements to start.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < summary.lines.length; i++)
                    SizedBox(
                      width: cardWidth,
                      child: _KpiCard(
                        index: i,
                        icon: _kpiIconFor(summary.lines[i].key),
                        label: summary.lines[i].label,
                        amount: NumberFormat.currency(
                          locale: 'en_IN',
                          symbol: '₹',
                          decimalDigits: 0,
                        ).format(summary.lines[i].amount),
                        subtitle: summary.lines[i].key == 'weightage' &&
                                summary.nightWeightageHours > 0
                            ? 'for ${summary.nightWeightageHours.toStringAsFixed(2)} hrs'
                            : null,
                      )
                          .animate(delay: (100 * i).ms)
                          .fade(duration: 400.ms)
                          .slideY(begin: 0.1, end: 0),
                    ),
                ],
              )
                  .animate()
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0);
            },
          ),
        if (summary.lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AllowancePieChart(summary: summary),
        ],
      ],
    );
  }

  static IconData _kpiIconFor(String key) {
    switch (key) {
      case 'length':
        return Icons.straighten;
      case 'cold':
        return Icons.ac_unit;
      case 'nightact':
        return Icons.dark_mode_outlined;
      case 'lock':
        return Icons.lock_outline;
      case 'navigation':
        return Icons.nightlight_round;
      case 'weightage':
        return Icons.hourglass_bottom;
      default:
        return Icons.currency_rupee;
    }
  }

  Future<void> _showThemePicker() async {
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Theme'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final t in ModernThemeId.values)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: t.seed,
                    child: Icon(t.icon,
                        color: Colors.white, size: 20),
                  ),
                  title: Text(t.label),
                  subtitle: Text(
                      t.brightness == Brightness.dark ? 'Dark' : 'Light',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                  trailing: t == widget.themeId
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () {
                    widget.onThemeChanged(t);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles switching the claim month. If a saved file already exists for the
  /// selected month, it is loaded and displayed. Otherwise the user is prompted
  /// to start a fresh claim for the new month.
  Future<void> _changeMonth(int newMonth, int newYear) async {
    final currentMonth = widget.claimData.master.month;
    final parsed = MasterData.parseMonthYear(currentMonth);
    final curM = parsed?.$2 ?? _selectedMonth;
    final curY = parsed?.$1 ?? _selectedYear;
    if (newMonth == curM && newYear == curY) return;

    // Prompt if the user has uncommitted edits on the current month.
    if (_hasUnsavedChanges) {
      final save = await _confirmDiscardChanges();
      if (!mounted) return;
      if (save == null) return;
      if (save) _saveLocal();
    }

    final label = '${MasterData.monthNames[newMonth - 1][0]}'
        '${MasterData.monthNames[newMonth - 1].substring(1).toLowerCase()} '
        '$newYear';

    // If this month was saved before, restore it instead of starting fresh.
    final saved =
        await widget.driveService.loadLocalBackup(month: MasterData.monthKey(newYear, newMonth));
    if (saved != null) {
      widget.claimData.master = saved.master;
      _applyMaster(saved.master);
      widget.claimData.movements
        ..clear()
        ..addAll(saved.movements);
      final sp = MasterData.parseMonthYear(saved.master.month);
      widget.claimData.attShifts = AllowanceCalculator.pruneFutureShifts(
          sp == null
              ? saved.attShifts
              : AllowanceCalculator.fillRoster(
                  year: sp.$1,
                  month: sp.$2,
                  offDay: saved.attOffDay,
                  rotation: saved.attRotation,
                  existing: saved.attShifts));
      widget.claimData.attManualDates = saved.attManualDates;
      widget.claimData.attLocked = saved.attLocked;
      widget.claimData.attOffDay = saved.attOffDay;
      widget.claimData.attRotation = saved.attRotation;
      widget.claimData.actingAdmDates.clear();
      widget.claimData.actingAdmDates.addAll(saved.actingAdmDates);
      setState(() {
        _selectedMonth = newMonth;
        _selectedYear = newYear;
      });
      widget.onDataChanged();
      _showSnack('Loaded $label');
      _savedBaselineGlyph = _currentEditGlyph();
      return;
    }

    if (!mounted) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new month?'),
        content: Text(
          'You selected $label.\n\n'
          'Start a fresh claim for $label? This clears movements and saved '
          'attendance for the current editing session. Your other saved '
          'months are kept unchanged, and your master details (name, '
          'designation, pay) and roster pattern are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start New'),
          ),
        ],
      ),
    );
    if (start != true) return;

    setState(() {
      _selectedMonth = newMonth;
      _selectedYear = newYear;
      final formState = _formKey.currentState;
      if (formState != null) {
        formState.save();
      }
      final values = formState?.value ?? {};
      widget.claimData.master = MasterData(
        month: MasterData.monthKey(newYear, newMonth),
        name: (values['name'] as String?)?.trim().toUpperCase() ?? '',
        designation: values['designation'] as String? ?? '',
        employee: (values['employee'] as String?)?.trim() ?? '',
        sapEmployeeId: (values['sapEmployeeId'] as String?)?.trim() ?? '',
        pay: (values['pay'] as String?)?.trim() ?? '',
        bill: (values['bill'] as String?)?.trim() ?? '',
        basic: (values['basic'] as String?)?.trim() ?? '',
        ada: (values['ada'] as String?)?.trim() ?? '',
      );
      widget.claimData.movements.clear();
      widget.claimData.attShifts.clear();
      widget.claimData.attManualDates.clear();
      widget.claimData.actingAdmDates.clear();
    });
    widget.onDataChanged();
    _showSnack('Started new claim for $label');
    _savedBaselineGlyph = _currentEditGlyph();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowance Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.update),
            tooltip: 'Check for updates',
            onPressed: () => _checkForUpdate(manual: true),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save to this device',
            onPressed: _saveLocal,
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Theme',
            onPressed: _showThemePicker,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FormBuilder(
          key: _formKey,
          initialValue: {
            'name': widget.claimData.master.name,
            'designation': _normalizeDesignation(widget.claimData.master.designation),
            'employee': widget.claimData.master.employee,
            'sapEmployeeId': widget.claimData.master.sapEmployeeId,
            'pay': widget.claimData.master.pay,
            'bill': widget.claimData.master.bill,
            'basic': widget.claimData.master.basic,
            'ada': widget.claimData.master.ada,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: 'Master Data',
                subtitle: 'Enter your profile and pay details',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 16),
              _ModernCard(
                child: Column(
                  children: [
                    _ModernMonthPicker(
                      selectedMonth: _selectedMonth,
                      selectedYear: _selectedYear,
                      savedMonths: _savedMonths,
                      onMonthChanged: (v) => _changeMonth(v, _selectedYear),
                      onYearChanged: (v) => _changeMonth(_selectedMonth, v),
                    ),
                    const SizedBox(height: 12),
                    FormBuilderTextField(
                      name: 'name',
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    FormBuilderDropdown<String>(
                      name: 'designation',
                      decoration: const InputDecoration(
                        labelText: 'Designation',
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                      items: _designationOptions
                          .map((e) => DropdownMenuItem(
                                value: e.$1,
                                child: Row(
                                  children: [
                                    Icon(e.$2, size: 20),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        e.$1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _currentDesignation = value);
                        }
                      },
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Visibility(
                      visible: _currentDesignation.isEmpty ||
                          _currentDesignation == 'BERTHING PILOT',
                      maintainState: true,
                      child: FormBuilderTextField(
                        name: 'pay',
                        decoration: InputDecoration(
                          labelText: 'Consolidated Pay (₹)',
                          prefixIcon: Icon(Icons.currency_rupee),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        validator: (v) {
                          final designation = _formKey.currentState?.value['designation'];
                          if (designation == 'BERTHING PILOT' &&
                              (v == null || v.trim().isEmpty)) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),
                    Visibility(
                      visible: _currentDesignation.isEmpty ||
                          _currentDesignation != 'BERTHING PILOT',
                      maintainState: true,
                      child: FormBuilderTextField(
                        name: 'basic',
                        decoration: InputDecoration(
                          labelText: 'Basic Pay (₹)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                    Visibility(
                      visible: _currentDesignation.isEmpty ||
                          _currentDesignation != 'BERTHING PILOT',
                      maintainState: true,
                      child: const SizedBox(height: 12),
                    ),
                    Visibility(
                      visible: _currentDesignation.isEmpty ||
                          _currentDesignation != 'BERTHING PILOT',
                      maintainState: true,
                      child: FormBuilderTextField(
                        name: 'ada',
                        decoration: InputDecoration(
                          labelText: 'ADA (₹)',
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormBuilderTextField(
                      name: 'employee',
                      decoration: InputDecoration(
                        labelText: _currentDesignation == 'BERTHING PILOT' ? 'Employee ID' : 'DPS No.',
                        prefixIcon: Icon(Icons.credit_card_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    FormBuilderTextField(
                      name: 'sapEmployeeId',
                      decoration: InputDecoration(
                        labelText: 'SAP Employee ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    FormBuilderTextField(
                      name: 'bill',
                      decoration: InputDecoration(
                        labelText: 'Bill Abstract No.',
                        prefixIcon: Icon(Icons.receipt_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saveMaster,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save Master Data'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Monthly Summary',
                subtitle: 'Claim totals & active allowances',
                icon: Icons.summarize_outlined,
              ),
              const SizedBox(height: 16),
              _buildSummarySection(scheme),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Sun Times',
                subtitle: 'Sunrise & sunset for any date',
                icon: Icons.wb_sunny_outlined,
              ),
              const SizedBox(height: 16),
              _SunTimesCard(
                date: _sunDate,
                onPickDate: (d) => setState(() => _sunDate = d),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Actions',
                subtitle: 'Navigate to other sections',
                icon: Icons.rocket_launch_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('Claim Summary'),
                          onPressed: _openSummary,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.directions_boat_rounded),
                          label: const Text('Movements'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovementScreen(
                                claimData: widget.claimData,
                                onChanged: widget.onDataChanged,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: const Text('Attendance'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceScreen(
                                claimData: widget.claimData,
                                onChanged: widget.onDataChanged,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Export Data'),
                          onPressed: _exportJson,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Import Data'),
                          onPressed: _importJson,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 62),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _SectionHeader(
                title: 'Drive Sync',
                subtitle: widget.driveService.isSignedIn
                    ? widget.driveService.currentUser?.email ?? ''
                    : 'Backup your data to Google Drive',
                icon: Icons.cloud_outlined,
              ),
              const SizedBox(height: 16),
              _ModernCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.driveService.isSignedIn)
                      if (_syncing)
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.upload),
                                label: const Text('Upload to Drive'),
                                onPressed: _syncToDrive,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.download),
                                label: const Text('Download'),
                                onPressed: _syncFromDrive,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign Out'),
                          onPressed: () {
                            widget.driveService.signOut();
                            setState(() {});
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ]
                    else
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.login),
                        label: const Text('Sign in with Google for Drive Sync'),
                        onPressed: _handleDriveSignIn,
                      ),
                    if (_syncStatus.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          _syncStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: _syncStatus.contains('fail') ||
                                    _syncStatus.contains('error')
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Developed by IamANISH',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModernCard extends StatelessWidget {
  final Widget child;

  const _ModernCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class _ModernMonthPicker extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;
  final Set<String> savedMonths;

  const _ModernMonthPicker({
    required this.selectedMonth,
    required this.selectedYear,
    required this.savedMonths,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = List.generate(
      7,
      (i) => now.year - 3 + i,
    );

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: selectedMonth,
            items: List.generate(
              12,
              (i) {
                final key = MasterData.monthKey(selectedYear, i + 1);
                final saved = savedMonths.contains(key);
                return DropdownMenuItem(
                  value: i + 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (saved) ...[
                        const Icon(Icons.check_circle,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        MasterData.monthNames[i][0] +
                            MasterData.monthNames[i]
                                .substring(1)
                                .toLowerCase(),
                      ),
                    ],
                  ),
                );
              },
            ),
            onChanged: (v) => onMonthChanged(v!),
            decoration: const InputDecoration(
              labelText: 'Month',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: selectedYear,
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
            onChanged: (v) => onYearChanged(v!),
            decoration: const InputDecoration(
              labelText: 'Year',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryHeroCard extends StatelessWidget {
  final double grandTotal;
  final int activeClaims;
  final int movements;
  final int workingDays;

  const _SummaryHeroCard({
    required this.grandTotal,
    required this.activeClaims,
    required this.movements,
    required this.workingDays,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final amount = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(grandTotal);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Grand Total',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Active claims · $activeClaims',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$movements movements · $workingDays working days',
                  textAlign: TextAlign.right,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final String amount;
  final String? subtitle;

  const _KpiCard({
    required this.index,
    required this.icon,
    required this.label,
    required this.amount,
    this.subtitle,
  });

  Color _accent(ColorScheme scheme) {
    const roles = [0, 1, 2, 3];
    switch (roles[index % roles.length]) {
      case 1:
        return scheme.secondary;
      case 2:
        return scheme.tertiary;
      case 3:
        return scheme.error;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _accent(scheme);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AllowancePieChart extends StatelessWidget {
  final ClaimSummary summary;

  const _AllowancePieChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Filter out lines with zero amount
    final lines = summary.lines.where((l) => l.amount > 0).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final total = summary.grandTotal;

    // Colors for each allowance type, matching the KPI card accents
    final colors = <Color>[
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.primary.withValues(alpha: 0.7),
      scheme.secondary.withValues(alpha: 0.7),
    ];

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final percentage = total > 0 ? (line.amount / total) * 100 : 0.0;
      final color = colors[i % colors.length];
      sections.add(
        PieChartSectionData(
          color: color,
          value: line.amount,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 50,
          titleStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          badgeWidget: percentage >= 5
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    line.label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
          badgePositionPercentageOffset: 1.15,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Allowance Distribution',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(
                    enabled: true,
                    touchCallback: (event, response) {},
                  ),
                  borderData: FlBorderData(show: false),
                ),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SunTimesCard extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onPickDate;

  const _SunTimesCard({required this.date, required this.onPickDate});

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sunTimes = AllowanceCalculator.getSunTimes(_fmtDate(date));
    final sunrise =
        sunTimes != null ? AllowanceCalculator.minToHHMM(sunTimes.$1) : '--:--';
    final sunset =
        sunTimes != null ? AllowanceCalculator.minToHHMM(sunTimes.$2) : '--:--';
    final isToday = DateTime.now().year == date.year &&
        DateTime.now().month == date.month &&
        DateTime.now().day == date.day;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          if (picked != null) onPickDate(picked);
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isToday ? 'Today — ${_fmtDate(date)}' : _fmtDate(date),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.edit_calendar_outlined,
                      size: 18, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SunTimeItem(
                      icon: Icons.wb_twilight_outlined,
                      label: 'Sunrise',
                      time: sunrise,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SunTimeItem(
                      icon: Icons.nightlight_round_outlined,
                      label: 'Sunset',
                      time: sunset,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SunTimeItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final Color color;

  const _SunTimeItem({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            time,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _downloading = false;
  String? _error;

  static const _channel = MethodChannel('com.allowance.app/install');

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final asset = widget.info.assets.firstOrNull;
      if (asset == null || asset.downloadUrl.isEmpty) {
        throw Exception('No matching APK found for this app');
      }
      final path = await UpdateService.downloadApk(
        asset,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      setState(() => _progress = 1.0);

      await _channel.invokeMethod('installApk', {'path': path});
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Download failed: $e';
          _downloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(
        _downloading ? Icons.system_update_alt : Icons.system_update,
        color: scheme.primary,
        size: 36,
      ),
      title: const Text('Update Available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${widget.info.latestVersion}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          if (widget.info.body.isNotEmpty)
            Text(widget.info.body,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (final a in widget.info.assets)
            Text('${a.name} (${(a.sizeBytes / 1048576).toStringAsFixed(1)} MB)',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              _progress != null && _progress! >= 1.0
                  ? 'Download complete. Opening installer...'
                  : 'Downloading... ${(_progress != null ? _progress! * 100 : 0).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        if (!_downloading)
          FilledButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Install Update'),
            onPressed: _downloadAndInstall,
          ),
        if (_downloading && _error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}