import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:allowance_shared/services/update_service.dart';
import 'package:allowance_app_v2/services/local_store.dart';
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
  final VoidCallback onDataChanged;
  final ModernThemeId themeId;
  final ValueChanged<ModernThemeId> onThemeChanged;
  final String appVersion;
  final LocalStore? localStore;

  const DashboardScreen({
    super.key,
    required this.claimData,
    required this.onDataChanged,
    required this.themeId,
    required this.onThemeChanged,
    required this.appVersion,
    this.localStore,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _masterDataKey = GlobalKey();
  late int _selectedMonth;
  late int _selectedYear;
  String _currentDesignation = '';
  late DateTime _sunDate;

  late final LocalStore _localStore = widget.localStore ?? LocalStore();
  Set<String> _savedMonths = {};

  static const _designationOptions = [
    ('BERTHING PILOT', LucideIcons.ship),
    ('DOCK PILOT', LucideIcons.anchor),
    ('ADM', LucideIcons.contact),
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
    });
    _refreshSavedMonths();
  }

  Future<void> _refreshSavedMonths() async {
    try {
      final list = await _localStore.listSavedMonths();
      if (!mounted) return;
      setState(() => _savedMonths = list.toSet());
    } catch (_) {
      // Storage may be unavailable (e.g. in widget tests); just skip markers.
    }
  }

  Future<void> _checkForUpdate({bool manual = false}) async {
    final info = await UpdateService.checkForUpdate(widget.appVersion,
        appVariant: 'v2');
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

  /// Commits the master form to [claimData]. Returns false when validation
  /// fails, in which case nothing was written and callers must not treat the
  /// form as saved.
  bool _saveMaster() {
    final formState = _formKey.currentState;
    if (formState == null || !formState.saveAndValidate()) return false;
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
    return true;
  }

  void _applyMaster(MasterData m) {
    final parsed = MasterData.parseMonthYear(m.month);
    _selectedYear = parsed?.$1 ?? DateTime.now().year;
    _selectedMonth = parsed?.$2 ?? DateTime.now().month;
    // FormBuilder fields will be updated via initialValue on rebuild
    _suppressDirty = true;
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
    _suppressDirty = false;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// True until the profile fields every official form needs are filled in.
  /// Drives the first-run hint above the daily actions.
  bool get _isProfileIncomplete {
    final m = widget.claimData.master;
    return m.name.trim().isEmpty ||
        m.designation.trim().isEmpty ||
        m.employee.trim().isEmpty ||
        m.sapEmployeeId.trim().isEmpty ||
        m.bill.trim().isEmpty;
  }

  void _scrollToMasterData() {
    final target = _masterDataKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  /// True while the master form holds edits that have not been written to the
  /// device. Movements, attendance and the claim summary all persist through
  /// [DashboardScreen.onDataChanged] from their own screens, so the profile
  /// fields are the only genuinely unsaved data on this screen.
  ///
  /// This is a plain flag rather than a serialization comparison because
  /// `PopScope.canPop` is evaluated during build, and the glyph-based check
  /// this replaced called `FormState.save()` from that path, which triggers
  /// validation mid-build.
  bool _dirty = false;

  /// Set while patching form fields programmatically so the resulting
  /// `FormBuilder.onChanged` is not counted as a user edit.
  bool _suppressDirty = false;

  void _markDirty() {
    if (_suppressDirty || _dirty) return;
    setState(() => _dirty = true);
  }

  /// Call after the form has been repopulated from a freshly loaded claim, or
  /// after the master form has actually been written out, so whatever is on
  /// screen is by definition what is stored.
  void _markClean() {
    if (!_dirty) return;
    setState(() => _dirty = false);
  }

  /// Intercepts a back gesture or system back while the master form has
  /// uncommitted edits. Reuses the same three-way dialog as the month
  /// switcher: null cancels, false discards, true saves first.
  ///
  /// The dashboard is the root route, so `Navigator.pop()` cannot dismiss it:
  /// `maybePop` reports that nothing was popped and `handlePopRoute` falls
  /// straight through to `SystemNavigator.pop()`, which would exit the app and
  /// skip this prompt entirely. Leaving therefore has to be requested
  /// explicitly once the user has confirmed.
  Future<void> _confirmExit() async {
    if (_dirty) {
      final save = await _confirmDiscardChanges();
      if (!mounted) return;
      if (save == null) return;
      if (save) _saveLocal();
    }
    await SystemNavigator.pop();
  }

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
    if (_saveMaster()) _markClean();
    _showSnack('Saved to this device');
  }

  /// Pushes a child screen. It deliberately leaves [dirty] alone: the Movements
  /// and Attendance screens persist their own data but never commit the master
  /// form, so a pending master edit is still pending on return. This is what
  /// keeps the flag honest — the previous implementation compared a
  /// serialization of the whole claim against a baseline captured at build
  /// time, which went stale as soon as a child screen saved anything and made
  /// back and the month switcher prompt about work that was already stored.
  Future<void> _pushChild(Widget screen) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _openSummary() async {
    _saveMaster();
    await _pushChild(ClaimSummaryScreen(
      claimData: widget.claimData,
      onChanged: widget.onDataChanged,
    ));
  }

  Future<void> _openMovements() => _pushChild(MovementScreen(
        claimData: widget.claimData,
        onChanged: widget.onDataChanged,
      ));

  Future<void> _openAttendance() => _pushChild(AttendanceScreen(
        claimData: widget.claimData,
        onChanged: widget.onDataChanged,
      ));

  Future<void> _exportJson() async {
    _saveMaster();
    try {
      final jsonStr = const JsonEncoder.withIndent('  ')
          .convert(widget.claimData.toJson());
      final dir = await getTemporaryDirectory();
      final name = widget.claimData.master.month.isNotEmpty
          ? LocalStore.monthFileName(widget.claimData.master.month)
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

  int get _movementCount =>
      AllowanceCalculator.movementsForMonth(widget.claimData).length;

  /// Human label for the selected claim month, e.g. 'August 2026'.
  String get _monthLabel {
    final name = MasterData.monthNames[_selectedMonth - 1];
    return '${name[0]}${name.substring(1).toLowerCase()} $_selectedYear';
  }  int get _attendanceCount {
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

  Widget _buildSummaryBody(ColorScheme scheme, ClaimSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          AllowancePieChart(summary: summary),
        ],
      ],
    );
  }

  static IconData _kpiIconFor(String key) {
    switch (key) {
      case 'length':
        return LucideIcons.ruler;
      case 'cold':
        return LucideIcons.snowflake;
      case 'nightact':
        return LucideIcons.moonStar;
      case 'lock':
        return LucideIcons.lock;
      case 'navigation':
        return LucideIcons.navigation;
      case 'weightage':
        return LucideIcons.hourglass;
      default:
        return LucideIcons.indianRupee;
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
    if (_dirty) {
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
        await _localStore.load(month: MasterData.monthKey(newYear, newMonth));
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
    _markClean();
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
    _markClean();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = AllowanceCalculator.computeSummary(widget.claimData);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Allowance Portal'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Check for updates',
            onPressed: () => _checkForUpdate(manual: true),
          ),
          IconButton(
            icon: const Icon(LucideIcons.save),
            tooltip: 'Save to this device',
            onPressed: _saveLocal,
          ),
          IconButton(
            icon: const Icon(LucideIcons.palette),
            tooltip: 'Theme',
            onPressed: _showThemePicker,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FormBuilder(
          key: _formKey,
          onChanged: _markDirty,
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
              _WalletHeroCard(
                summary: summary,
                movements: _movementCount,
                workingDays: _attendanceCount,
                monthLabel: _monthLabel,
              )
                  .animate()
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.08, end: 0),
              const SizedBox(height: 12),
              _ModernCard(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: _ModernMonthPicker(
                  selectedMonth: _selectedMonth,
                  selectedYear: _selectedYear,
                  savedMonths: _savedMonths,
                  onMonthChanged: (v) => _changeMonth(v, _selectedYear),
                  onYearChanged: (v) => _changeMonth(_selectedMonth, v),
                ),
              )
                  .animate(delay: 60.ms)
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.08, end: 0),
              if (_isProfileIncomplete) ...[
                const SizedBox(height: 12),
                _ProfileHint(onTap: _scrollToMasterData),
              ],
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Daily Actions',
                subtitle: 'Log movements, review the claim, mark attendance',
                icon: LucideIcons.zap,
              ),
              const SizedBox(height: 16),
              _DailyActionTiles(
                onMovements: _openMovements,
                onSummary: _openSummary,
                onAttendance: _openAttendance,
                movementsCaption: '$_movementCount jobs',
                summaryCaption: 'Review & print',
                attendanceCaption: '$_attendanceCount days',
              )
                  .animate(delay: 120.ms)
                  .fade(duration: 400.ms)
                  .slideY(begin: 0.08, end: 0),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.upload),
                      label: const Text('Export Data'),
                      onPressed: _exportJson,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.download),
                      label: const Text('Import Data'),
                      onPressed: _importJson,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Monthly Summary',
                subtitle: 'Claim totals & active allowances',
                icon: LucideIcons.pieChart,
              ),
              const SizedBox(height: 16),
              _buildSummaryBody(scheme, summary),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Sun Times',
                subtitle: 'Sunrise & sunset for any date',
                icon: LucideIcons.sun,
              ),
              const SizedBox(height: 16),
              _SunTimesCard(
                date: _sunDate,
                onPickDate: (d) => setState(() => _sunDate = d),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(
                title: 'Master Data',
                subtitle: 'Enter your profile and pay details',
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 16),
              _ModernCard(
                key: _masterDataKey,
                child: Column(
                  children: [
                    FormBuilderTextField(
                      name: 'name',
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(LucideIcons.user),
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
                        prefixIcon: Icon(LucideIcons.briefcase),
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
                          prefixIcon: Icon(LucideIcons.indianRupee),
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
                          prefixIcon: Icon(LucideIcons.wallet),
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
                          prefixIcon: Icon(LucideIcons.landmark),
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
                        prefixIcon: Icon(LucideIcons.creditCard),
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
                        prefixIcon: Icon(LucideIcons.contact),
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
                        prefixIcon: Icon(LucideIcons.receipt),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        if (_saveMaster()) _markClean();
                      },
                      icon: const Icon(LucideIcons.save),
                      label: const Text('Save Master Data'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
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
      ),
    );
  }
}

/// First-run nudge: every official form needs the profile fields, so point the
/// user at Master Data instead of letting them discover it after filling a
/// movement register.
class _ProfileHint extends StatelessWidget {
  final VoidCallback onTap;

  const _ProfileHint({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 16,
          cornerSmoothing: 0.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(LucideIcons.info, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Finish your profile in Master Data to print official forms.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight,
                  color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three things a pilot opens every day, as one equal row of squircle
/// tiles with a live caption each (jobs logged, claim state, roster days).
/// Movements leads by colour rather than by size so all three stay the same
/// shape and nothing reflows when a label wraps to two lines.
class _DailyActionTiles extends StatelessWidget {
  final VoidCallback onMovements;
  final VoidCallback onSummary;
  final VoidCallback onAttendance;
  final String movementsCaption;
  final String summaryCaption;
  final String attendanceCaption;

  const _DailyActionTiles({
    required this.onMovements,
    required this.onSummary,
    required this.onAttendance,
    required this.movementsCaption,
    required this.summaryCaption,
    required this.attendanceCaption,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionTile(
              icon: LucideIcons.ship,
              label: 'Movements',
              caption: movementsCaption,
              onTap: onMovements,
              primary: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: LucideIcons.receipt,
              label: 'Claim Summary',
              caption: summaryCaption,
              onTap: onSummary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: LucideIcons.calendarDays,
              label: 'Attendance',
              caption: attendanceCaption,
              onTap: onAttendance,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final bool primary;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        primary ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = primary ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: background,
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 20,
          cornerSmoothing: 0.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: foreground),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.75),
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
          decoration: ShapeDecoration(
            color: scheme.primaryContainer,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 12,
                cornerSmoothing: 0.6,
              ),
            ),
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
                style: GoogleFonts.poppins(
                  textStyle: Theme.of(context).textTheme.headlineSmall,
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
  final EdgeInsetsGeometry padding;

  const _ModernCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 20,
          cornerSmoothing: 0.6,
        ),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
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

/// E-wallet balance hero: a gradient squircle card with the claim month, the
/// grand total in Poppins, the active-claims pill and roster mini-stats.
/// Keeps the 'Grand Total' label and 'Active claims · N' pill the summary
/// tests assert on.
class _WalletHeroCard extends StatelessWidget {
  final ClaimSummary summary;
  final int movements;
  final int workingDays;
  final String monthLabel;

  const _WalletHeroCard({
    required this.summary,
    required this.movements,
    required this.workingDays,
    required this.monthLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final amount = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(summary.grandTotal);
    final onHero = scheme.onPrimaryContainer;

    return Material(
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 24,
          cornerSmoothing: 0.6,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              scheme.secondaryContainer,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monthLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: onHero.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Grand Total',
                          style: textTheme.bodyMedium?.copyWith(
                            color: onHero.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          amount,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: GoogleFonts.poppins(
                            textStyle: textTheme.displaySmall,
                            color: onHero,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: ShapeDecoration(
                      color: scheme.primary.withValues(alpha: 0.85),
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 16,
                          cornerSmoothing: 0.6,
                        ),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.wallet,
                      size: 28,
                      color: scheme.onPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Active claims · ${summary.lines.length}',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$movements jobs · $workingDays days',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: onHero.withValues(alpha: 0.8),
                      ),
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
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 20,
          cornerSmoothing: 0.6,
        ),
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
                  decoration: ShapeDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerRadius: 10,
                        cornerSmoothing: 0.6,
                      ),
                    ),
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
              style: GoogleFonts.poppins(
                textStyle: textTheme.titleLarge,
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

class AllowancePieChart extends StatelessWidget {
  final ClaimSummary summary;

  const AllowancePieChart({super.key, required this.summary});

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
                // fl_chart animates data.sections with an implicit tween but
                // rebuilds badge children from the new list, so growing the
                // section count mid-animation makes RenderPieChart.badgeWidgetPaint
                // index past the end (RangeError, range 0..1: 2). Keying on the
                // count makes Flutter swap the chart instead of animating it.
                key: ValueKey<int>(lines.length),
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
      elevation: 0,
      shape: SmoothRectangleBorder(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 20,
          cornerSmoothing: 0.6,
        ),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                  Icon(LucideIcons.calendarDays,
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
                  Icon(LucideIcons.calendarCheck,
                      size: 18, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SunTimeItem(
                      icon: LucideIcons.sunrise,
                      label: 'Sunrise',
                      time: sunrise,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SunTimeItem(
                      icon: LucideIcons.sunset,
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
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.1),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(
            cornerRadius: 14,
            cornerSmoothing: 0.6,
          ),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              textStyle: Theme.of(context).textTheme.headlineSmall,
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