import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/claim_data.dart';
import '../models/master_data.dart';
import '../models/movement.dart';
import '../services/allowance_calculator.dart';

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _TimeTextFormatter extends TextInputFormatter {
  const _TimeTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clamped = digits.length > 4 ? digits.substring(0, 4) : digits;
    return TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
  }
}

class _DecimalTextFormatter extends TextInputFormatter {
  const _DecimalTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    final firstDot = text.indexOf('.');
    if (firstDot >= 0) {
      text = text.substring(0, firstDot + 1) +
          text.substring(firstDot + 1).replaceAll('.', '');
    }
    return newValue.copyWith(text: text);
  }
}

class MovementScreen extends StatefulWidget {
  final ClaimData claimData;
  final VoidCallback onChanged;

  const MovementScreen({
    super.key,
    required this.claimData,
    required this.onChanged,
  });

  @override
  State<MovementScreen> createState() => _MovementScreenState();
}

class _MovementScreenState extends State<MovementScreen> {
  final _fmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final movements =
        AllowanceCalculator.movementsForMonth(widget.claimData);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movement Register'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Movement',
        onPressed: () => _editMovement(context),
        child: const Icon(Icons.add),
      ),
      body: movements.isEmpty
          ? _EmptyState(
              message: widget.claimData.movements.isEmpty
                  ? 'No movements yet.\nTap the + button to add your first movement.'
                  : 'No movements for the selected month.',
              icon: Icons.directions_boat_outlined,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: movements.length,
              itemBuilder: (context, index) {
                final m = movements[index];
                final amount = m.allowances.fold<double>(
                    0,
                    (sum, a) =>
                        sum +
                        AllowanceCalculator.amountFor(
                            allowance: a,
                            movement: m,
                            adm: widget.claimData.master.isAdm ||
                                widget.claimData.isActingAdmOn(m.date)));
                return _MovementCard(
                  movement: m,
                  amount: amount,
                  amountText: _fmt.format(amount),
                  allowanceLabel: _allowanceLabel(m.allowances,
                      adm: widget.claimData.master.isAdm ||
                          widget.claimData.isActingAdmOn(m.date)),
                  navLabel: _navLabel(m.navigationTypes),
                  scheme: scheme,
                  onEdit: () => _editMovement(context, existing: m),
                  onDelete: () => _deleteMovement(m),
                );
              },
            ),
    );
  }

  String _allowanceLabel(List<String> a, {required bool adm}) {
    final names = <String>[];
    for (final key in a) {
      if (adm && (key == 'nightact' || key == 'cold')) continue;
      names.add(switch (key) {
        'length' => 'Length',
        'cold' => 'Cold-Move',
        'nightact' => 'Night Act',
        'lock' => 'Lock to App. Jetty & vice versa',
        'navigation' => 'Night Nav',
        _ => '',
      });
    }
    return names.where((n) => n.isNotEmpty).join(', ');
  }

  String _navLabel(List<String> n) {
    final names = <String>[];
    for (final key in n) {
      names.add(switch (key) {
        'outward-180-210' => 'Out 180-210',
        'outward-210' => 'Out ≥210',
        'outward-beam' => 'Out Beam≥30.5',
        'inward-210' => 'In ≥210',
        'double-banking' => 'Dbl Banking',
        'unbanking' => 'Unbanking',
        _ => key,
      });
    }
    return names.join(', ');
  }

  void _deleteMovement(Movement m) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: scheme.error),
        title: const Text('Delete Movement'),
        content: Text('Delete ${m.vessel} on ${m.date}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () {
              final i = widget.claimData.movements.indexOf(m);
              if (i >= 0) widget.claimData.removeMovement(i);
              widget.onChanged();
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _editMovement(BuildContext context, {Movement? existing}) async {
    final isNew = existing == null;
    final current = existing ?? Movement();
    final now = DateTime.now();
    final parsed = MasterData.parseMonthYear(widget.claimData.master.month);
    final year = parsed?.$1 ?? now.year;
    final month = parsed?.$2 ?? now.month;

    final result = await showDialog<Movement>(
      context: context,
      builder: (_) => _MovementFormDialog(
        existing: current,
        title: isNew ? 'Add Movement' : 'Edit Movement',
        year: year,
        month: month,
        claimData: widget.claimData,
      ),
    );

    if (result != null) {
      if (isNew) {
        widget.claimData.addMovement(result);
      } else {
        final i = widget.claimData.movements.indexOf(current);
        if (i >= 0) widget.claimData.updateMovement(i, result);
      }
      widget.onChanged();
    }
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const _EmptyState({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  final Movement movement;
  final double amount;
  final String amountText;
  final String allowanceLabel;
  final String navLabel;
  final ColorScheme scheme;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MovementCard({
    required this.movement,
    required this.amount,
    required this.amountText,
    required this.allowanceLabel,
    required this.navLabel,
    required this.scheme,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasNav = movement.navigationTypes.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    movement.date,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    movement.vessel,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.arrow_forward_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${movement.from} → ${movement.to}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${movement.start} - ${movement.end}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 16),
                if (movement.loa.isNotEmpty) ...[
                  Icon(Icons.straighten_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${movement.loa} m',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
            if (allowanceLabel.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    text: allowanceLabel,
                    color: scheme.tertiaryContainer,
                    textColor: scheme.onTertiaryContainer,
                  ),
                  if (hasNav)
                    _Chip(
                      text: navLabel,
                      color: scheme.secondaryContainer,
                      textColor: scheme.onSecondaryContainer,
                    ),
                ],
              ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                if (amount > 0)
                  Text(
                    amountText,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.text,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _MovementFormDialog extends StatefulWidget {
  final Movement existing;
  final String title;
  final int year;
  final int month;
  final ClaimData claimData;

  const _MovementFormDialog({
    required this.existing,
    required this.title,
    required this.year,
    required this.month,
    required this.claimData,
  });

  @override
  State<_MovementFormDialog> createState() => _MovementFormDialogState();
}

class _MovementFormDialogState extends State<_MovementFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  late TextEditingController _vesselCtrl;
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  late TextEditingController _loaCtrl;
  late TextEditingController _beamCtrl;
  final Set<String> _allowances = {};
  final Set<String> _navTypes = {};
  String _detectInfo = '';
  double _computedAmount = 0;
  final _fmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _dateFmt = DateFormat('dd/MM/yyyy');

  static const _allowanceOptions = [
    'length',
    'cold',
    'nightact',
    'lock',
    'navigation',
  ];

  static const _navOptions = [
    'outward-180-210',
    'outward-210',
    'outward-beam',
    'inward-210',
    'double-banking',
    'unbanking',
  ];

  static const _admAllowanceOptions = [
    'length',
    'lock',
    'navigation',
  ];

  static const _admNavOptions = [
    'outward-180-210',
    'outward-210',
    'outward-beam',
    'inward-210',
  ];

  bool get _isAdm =>
      widget.claimData.master.isAdm ||
      widget.claimData.isActingAdmOn(
          '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}');

  List<String> get _allowanceChoices =>
      _isAdm ? _admAllowanceOptions : _allowanceOptions;

  List<String> get _navChoices => _isAdm ? _admNavOptions : _navOptions;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _selectedDate =
        _parseExistingDate(e.date) ?? _fallbackDate();
    _vesselCtrl = TextEditingController(text: e.vessel);
    _fromCtrl = TextEditingController(text: e.from);
    _toCtrl = TextEditingController(text: e.to);
    _startCtrl = TextEditingController(text: e.start);
    _endCtrl = TextEditingController(text: e.end);
    _loaCtrl = TextEditingController(text: e.loa);
    _beamCtrl = TextEditingController(text: e.beam);
    _allowances.addAll(e.allowances.where(_allowanceChoices.contains));
    _navTypes.addAll(e.navigationTypes.where(_navChoices.contains));
    if (_allowances.isNotEmpty) _updateAmount();
  }

  Movement _buildMovement() => Movement(
        date: _dateFmt.format(_selectedDate),
        vessel: _vesselCtrl.text.trim(),
        from: _fromCtrl.text.trim(),
        to: _toCtrl.text.trim(),
        start: _startCtrl.text.trim(),
        end: _endCtrl.text.trim(),
        loa: _loaCtrl.text.trim(),
        beam: _beamCtrl.text.trim(),
        allowances: _allowances.toList(),
        navigationTypes: _navTypes.toList(),
      );

  void _autoDetect() {
    final result =
        AllowanceCalculator.autoDetect(movement: _buildMovement());
    setState(() {
      _allowances
        ..clear()
        ..addAll(result.applicable);
      _navTypes
        ..clear()
        ..addAll(result.navTypes);
      _detectInfo = result.applicable.isEmpty
          ? 'No allowances detected'
          : 'Detected: ${result.applicable.join(', ')}';
      _updateAmount();
    });
  }

  void _updateAmount() {
    final adm = widget.claimData.master.isAdm ||
        widget.claimData.isActingAdmOn(
            AllowanceCalculator.movementShiftDate(_buildMovement()));
    _computedAmount = _allowances.fold(
        0,
        (sum, a) =>
            sum +
            AllowanceCalculator.amountFor(
                allowance: a, movement: _buildMovement(), adm: adm));
  }

  @override
  void dispose() {
    _vesselCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _loaCtrl.dispose();
    _beamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.title.contains('Edit') ? Icons.edit_outlined : Icons.add,
              color: scheme.primary, size: 24),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDateField(),
              _buildField(
                _vesselCtrl,
                'Vessel Name',
                prefixIcon: Icons.directions_boat_outlined,
                inputFormatters: const [_UpperCaseTextFormatter()],
                textCapitalization: TextCapitalization.characters,
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _fromCtrl,
                      'From Berth',
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildField(
                      _toCtrl,
                      'To Berth',
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _startCtrl,
                      'Start (HHMM)',
                      prefixIcon: Icons.schedule_outlined,
                      inputFormatters: const [_TimeTextFormatter()],
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildField(
                      _endCtrl,
                      'End (HHMM)',
                      prefixIcon: Icons.timer_outlined,
                      inputFormatters: const [_TimeTextFormatter()],
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              _buildSunHint(_selectedDate),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _loaCtrl,
                      'LOA (m)',
                      prefixIcon: Icons.straighten_outlined,
                      inputFormatters: const [_DecimalTextFormatter()],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildField(
                      _beamCtrl,
                      'Beam (m)',
                      prefixIcon: Icons.width_wide_outlined,
                      inputFormatters: const [_DecimalTextFormatter()],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.claimData.master.isBerthingPilot) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _autoDetect,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto-detect allowances'),
                  ),
                ),
                if (_detectInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _detectInfo,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _SectionLabel(
                icon: Icons.tune_rounded,
                text: 'Allowances',
                helper:
                    'Select the allowances applicable to this movement',
                scheme: scheme,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _allowanceChoices)
                    FilterChip(
                      label: Text(_chipLabel(a)),
                      selected: _allowances.contains(a),
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _allowances.add(a);
                        } else {
                          _allowances.remove(a);
                        }
                        _updateAmount();
                      }),
                    ),
                ],
              ),
              if (_allowances.contains('navigation')) ...[
                const SizedBox(height: 16),
                _SectionLabel(
                  icon: Icons.navigation_outlined,
                  text: 'Navigation Type',
                  helper: 'Choose the type of navigation movement',
                  scheme: scheme,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in _navChoices)
                      FilterChip(
                        label: Text(_navChipLabel(n)),
                        selected: _navTypes.contains(n),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _navTypes.add(n);
                          } else {
                            _navTypes.remove(n);
                          }
                          _updateAmount();
                        }),
                      ),
                  ],
                ),
              ],
              if (_allowances.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.currency_rupee_rounded,
                          color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('Amount: ',
                          style: TextStyle(fontSize: 15)),
                      Text(_fmt.format(_computedAmount),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _buildMovement());
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Save'),
        ),
      ],
    );
  }

  String _chipLabel(String a) {
    return switch (a) {
      'length' => 'Length',
      'cold' => 'Cold Move',
      'nightact' => 'Night Act',
      'lock' => 'Lock to App. Jetty & vice versa',
      'navigation' => 'Night Nav',
      _ => a,
    };
  }

  String _navChipLabel(String n) {
    return switch (n) {
      'outward-180-210' => 'Out 180-210',
      'outward-210' => 'Out ≥210',
      'outward-beam' => 'Out Beam≥30.5',
      'inward-210' => 'In ≥210',
      'double-banking' => 'Dbl Banking',
      'unbanking' => 'Unbanking',
      _ => n,
    };
  }

  DateTime? _parseExistingDate(String s) {
    if (s.trim().isEmpty) return null;
    final key = AllowanceCalculator.normDateKey(s);
    final p = key.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final mo = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  DateTime _fallbackDate() {
    final now = DateTime.now();
    if (now.year == widget.year && now.month == widget.month) return now;
    return DateTime(widget.year, widget.month, 1);
  }

  Widget _buildDateField() {
    final lastDay = DateTime(widget.year, widget.month + 1, 0).day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(widget.year, widget.month, 1),
            lastDate: DateTime(widget.year, widget.month, lastDay),
          );
          if (picked != null) {
            setState(() {
              _selectedDate = picked;
              _allowances.removeWhere((a) => !_allowanceChoices.contains(a));
              _navTypes.removeWhere((n) => !_navChoices.contains(n));
              _updateAmount();
            });
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date',
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(
            _dateFmt.format(_selectedDate),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    IconData? prefixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: ctrl,
        textCapitalization: textCapitalization,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        ),
      ),
    );
  }

  Widget _buildSunHint(DateTime date) {
    final fmt = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    final sun = AllowanceCalculator.getSunTimes(fmt);
    if (sun == null) return const SizedBox.shrink();
    final rise = AllowanceCalculator.minToHHMM(sun.$1);
    final set = AllowanceCalculator.minToHHMM(sun.$2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_twilight_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(rise, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            Icon(Icons.nightlight_round_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(set, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final String helper;
  final ColorScheme scheme;

  const _SectionLabel({
    required this.icon,
    required this.text,
    required this.helper,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                helper,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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