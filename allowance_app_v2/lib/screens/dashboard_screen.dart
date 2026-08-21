import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
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

  const DashboardScreen({
    super.key,
    required this.claimData,
    required this.onDataChanged,
    required this.themeId,
    required this.onThemeChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _empCtrl;
  late TextEditingController _payCtrl;
  late TextEditingController _billCtrl;
  late TextEditingController _basicCtrl;
  late TextEditingController _adaCtrl;
  late int _selectedMonth;
  late int _selectedYear;
  late String _designation;
  late DateTime _sunDate;

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
    _sunDate = now;
    _nameCtrl = TextEditingController(text: m.name);
    _designation = _normalizeDesignation(m.designation);
    _empCtrl = TextEditingController(text: m.employee);
    _payCtrl = TextEditingController(text: m.pay);
    _billCtrl = TextEditingController(text: m.bill);
    _basicCtrl = TextEditingController(text: m.basic);
    _adaCtrl = TextEditingController(text: m.ada);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _empCtrl.dispose();
    _payCtrl.dispose();
    _billCtrl.dispose();
    _basicCtrl.dispose();
    _adaCtrl.dispose();
    super.dispose();
  }

  void _saveMaster() {
    widget.claimData.master = MasterData(
      month: MasterData.monthKey(_selectedYear, _selectedMonth),
      name: _nameCtrl.text.trim().toUpperCase(),
      designation: _designation,
      employee: _empCtrl.text.trim(),
      pay: _payCtrl.text.trim(),
      bill: _billCtrl.text.trim(),
      basic: _basicCtrl.text.trim(),
      ada: _adaCtrl.text.trim(),
    );
    widget.onDataChanged();
    _showSnack('Master data saved');
  }

  void _applyMaster(MasterData m) {
    final parsed = MasterData.parseMonthYear(m.month);
    _selectedYear = parsed?.$1 ?? DateTime.now().year;
    _selectedMonth = parsed?.$2 ?? DateTime.now().month;
    _nameCtrl.text = m.name;
    _designation = _normalizeDesignation(m.designation);
    _empCtrl.text = m.employee;
    _payCtrl.text = m.pay;
    _billCtrl.text = m.bill;
    _basicCtrl.text = m.basic;
    _adaCtrl.text = m.ada;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _saveLocal() {
    _saveMaster();
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
      widget.claimData.attShifts = parsed == null
          ? data.attShifts
          : AllowanceCalculator.fillRoster(
              year: parsed.$1,
              month: parsed.$2,
              offDay: data.attOffDay,
              rotation: data.attRotation,
              existing: data.attShifts);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowance Portal'),
        actions: [
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
        child: Form(
          key: _formKey,
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
                      onMonthChanged: (v) => setState(() => _selectedMonth = v),
                      onYearChanged: (v) => setState(() => _selectedYear = v),
                    ),
                    const SizedBox(height: 12),
                    _ModernTextField(
                      controller: _nameCtrl,
                      label: 'Full Name',
                      prefixIcon: Icons.badge_outlined,
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    _ModernDropdown<String>(
                      label: 'Designation',
                      value: _designation,
                      prefixIcon: Icons.work_outline,
                      items: _designationOptions
                          .map((e) => DropdownMenuItem(
                                value: e.$1,
                                child: Row(
                                  children: [
                                    Icon(e.$2, size: 20),
                                    const SizedBox(width: 12),
                                    Text(e.$1),
                                  ],
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _designation = v!),
                    ),
                    const SizedBox(height: 12),
                    if (_designation == 'BERTHING PILOT')
                      _ModernTextField(
                        controller: _payCtrl,
                        label: 'Consolidated Pay (₹)',
                        prefixIcon: Icons.currency_rupee,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      )
                    else ...[
                      _ModernTextField(
                        controller: _basicCtrl,
                        label: 'Basic Pay (₹)',
                        prefixIcon: Icons.payments_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ModernTextField(
                        controller: _adaCtrl,
                        label: 'ADA (₹)',
                        prefixIcon: Icons.account_balance_wallet_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _ModernTextField(
                      controller: _empCtrl,
                      label:
                          _designation == 'BERTHING PILOT' ? 'Employee ID' : 'DPS No.',
                      prefixIcon: Icons.credit_card_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    _ModernTextField(
                      controller: _billCtrl,
                      label: 'Bill Abstract No.',
                      prefixIcon: Icons.receipt_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                title: 'Quick Stats',
                subtitle: 'Overview of current month',
                icon: Icons.analytics_outlined,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Movements',
                      value: '$_movementCount',
                      icon: Icons.directions_boat_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Working Days',
                      value: '$_attendanceCount',
                      icon: Icons.calendar_month_rounded,
                      color: scheme.secondary,
                    ),
                  ),
                ],
              ),
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
                    child: FilledButton.icon(
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('Claim Summary'),
                      onPressed: _openSummary,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Export Data'),
                      onPressed: _exportJson,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
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
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import JSON'),
                onPressed: _importJson,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
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

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon),
      ),
    );
  }
}

class _ModernDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final IconData prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _ModernDropdown({
    required this.label,
    required this.value,
    required this.prefixIcon,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon),
      ),
    );
  }
}

class _ModernMonthPicker extends StatelessWidget {
  final int selectedMonth;
  final int selectedYear;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;

  const _ModernMonthPicker({
    required this.selectedMonth,
    required this.selectedYear,
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
            initialValue: selectedMonth,
            items: List.generate(
              12,
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text(
                  MasterData.monthNames[i][0] +
                      MasterData.monthNames[i].substring(1).toLowerCase(),
                ),
              ),
            ),
            onChanged: (v) => onMonthChanged(v!),
            decoration: const InputDecoration(
              labelText: 'Month',
              prefixIcon: Icon(Icons.calendar_month_rounded),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: selectedYear,
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
            onChanged: (v) => onYearChanged(v!),
            decoration: const InputDecoration(
              labelText: 'Year',
              prefixIcon: Icon(Icons.event_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                  Text(
                    isToday ? 'Today — ${_fmtDate(date)}' : _fmtDate(date),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
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