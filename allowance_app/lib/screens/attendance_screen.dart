import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';

class AttendanceScreen extends StatefulWidget {
  final ClaimData claimData;
  final VoidCallback onChanged;

  const AttendanceScreen({
    super.key,
    required this.claimData,
    required this.onChanged,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late int _currentMonth;
  late int _currentYear;

  static const _shiftCodes = [
    '',
    'N',
    'E',
    'M',
    'P',
    'OFF',
    'L',
    'ML',
    'COMP OFF',
    'BOOKED',
  ];

  static const _offDayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final parsed =
        MasterData.parseMonthYear(widget.claimData.master.month);
    _currentMonth = parsed?.$2 ?? now.month;
    _currentYear = parsed?.$1 ?? now.year;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _generateRosterForMonth(_currentYear, _currentMonth)) {
        widget.onChanged();
      }
    });
  }

  bool _generateRosterForMonth(int year, int month) {
    final before = Map<String, String>.of(widget.claimData.attShifts);
    final filled = AllowanceCalculator.fillRoster(
      year: year,
      month: month,
      offDay: widget.claimData.attOffDay,
      rotation: widget.claimData.attRotation,
      existing: before,
    );
    final now = DateTime.now();
    final todayDt = DateTime(now.year, now.month, now.day);

    final pruned = <String, String>{};
    filled.forEach((key, val) {
      final p = key.split('-');
      if (p.length != 3) return;
      final y = int.tryParse(p[0]);
      final mo = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || mo == null || d == null) return;
      final dt = DateTime(y, mo, d);
      if (!dt.isAfter(todayDt) || before.containsKey(key)) {
        pruned[key] = val;
      }
    });

    final added = pruned.length > before.length;
    widget.claimData.attShifts
      ..clear()
      ..addAll(pruned);
    return added;
  }

  void _prevMonth() {
    setState(() {
      _currentMonth--;
      if (_currentMonth == 0) {
        _currentMonth = 12;
        _currentYear--;
      }
    });
    _afterMonthChange();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth++;
      if (_currentMonth == 13) {
        _currentMonth = 1;
        _currentYear++;
      }
    });
    _afterMonthChange();
  }

  void _afterMonthChange() {
    if (_generateRosterForMonth(_currentYear, _currentMonth)) {
      widget.onChanged();
    }
  }

  List<DateTime> _getDaysInMonth(int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final days = <DateTime>[];
    // Pad with previous month's trailing days
    final startWeekday = first.weekday % 7; // Sun=0
    for (int i = 0; i < startWeekday; i++) {
      days.add(first.subtract(Duration(days: startWeekday - i)));
    }
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(year, month, d));
    }
    // Pad to fill last row
    while (days.length % 7 != 0) {
      days.add(last.add(Duration(days: days.length - last.day - startWeekday + 1)));
      if (days.length % 7 == 0) break;
    }
    return days;
  }

  String _dateKey(DateTime dt) => '${dt.year}-${dt.month}-${dt.day}';

  ({String code, bool isPredicted}) _shiftForDateInfo(DateTime dt) {
    final key = _dateKey(dt);
    if (widget.claimData.attShifts.containsKey(key)) {
      return (code: widget.claimData.attShifts[key]!, isPredicted: false);
    }
    final now = DateTime.now();
    final todayDt = DateTime(now.year, now.month, now.day);
    if (dt.isAfter(todayDt)) {
      final pred = AllowanceCalculator.predictRosterShift(
        dt: dt,
        offDay: widget.claimData.attOffDay,
        rotation: widget.claimData.attRotation,
      );
      if (pred.isNotEmpty) return (code: pred, isPredicted: true);
    }
    return (code: '', isPredicted: false);
  }

  String _shiftForDate(DateTime dt) => _shiftForDateInfo(dt).code;

  Color _shiftColor(String code, ColorScheme scheme) {
    switch (code) {
      case 'N':
        return _tint(scheme, const Color(0xFF3F51B5));
      case 'E':
        return _tint(scheme, const Color(0xFFEF6C00));
      case 'M':
        return _tint(scheme, const Color(0xFFF9A825));
      case 'P':
        return _tint(scheme, const Color(0xFF2E7D32));
      case 'OFF':
        return _tint(scheme, const Color(0xFF546E7A));
      case 'L':
        return _tint(scheme, const Color(0xFF1565C0));
      case 'ML':
        return _tint(scheme, const Color(0xFFC62828));
      case 'COMP OFF':
        return _tint(scheme, const Color(0xFF6A1B9A));
      case 'BOOKED':
        return _tint(scheme, const Color(0xFF00897B));
      default:
        return Colors.transparent;
    }
  }

  Color _tint(ColorScheme scheme, Color base) {
    return scheme.brightness == Brightness.dark
        ? base.withValues(alpha: 0.32)
        : base.withValues(alpha: 0.16);
  }

  void _showShiftPicker(DateTime dt) {
    final key = _dateKey(dt);
    final current = _shiftForDate(dt);
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit_calendar_outlined, color: scheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(DateFormat('EEE, MMM d, yyyy').format(dt)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _shiftCodes.map((code) {
                    final selected = code == current;
                    return ChoiceChip(
                      label: Text(
                        code.isEmpty ? 'Blank' : code,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? scheme.onPrimary : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: selected,
                      selectedColor: scheme.primary,
                      backgroundColor: _shiftColor(code, scheme),
                      side: BorderSide(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                      onSelected: (_) {
                        final wasLocked = widget.claimData.attLocked;
                        if (wasLocked) widget.claimData.attLocked = false;
                        setState(() {
                          if (code.isEmpty) {
                            widget.claimData.attShifts.remove(key);
                          } else {
                            widget.claimData.attShifts[key] = code;
                          }
                          if (!widget.claimData.attManualDates.contains(key)) {
                            widget.claimData.attManualDates.add(key);
                          }
                        });
                        widget.onChanged();
                        widget.claimData.attLocked = wasLocked;
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Acting ADM',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
                          Text('ADM duty on this date',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.claimData.actingAdmDates.contains(key),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v) {
                            if (!widget.claimData.actingAdmDates
                                .contains(key)) {
                              widget.claimData.actingAdmDates.add(key);
                            }
                          } else {
                            widget.claimData.actingAdmDates.remove(key);
                          }
                        });
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthLabel() =>
      DateFormat('MMMM yyyy').format(DateTime(_currentYear, _currentMonth));

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _autoDetectAttendance() {
    // Auto-lock just means the user must confirm before changing; don't block.
    final wasLocked = widget.claimData.attLocked;
    if (wasLocked) widget.claimData.attLocked = false;
    final byDate = <String, List<Movement>>{};
    final now = DateTime.now();
    final todayDt = DateTime(now.year, now.month, now.day);

    for (final m in widget.claimData.movements) {
      if (m.date.trim().isEmpty || m.start.trim().isEmpty) continue;
      final shiftKey = AllowanceCalculator.movementShiftDate(m, attShifts: widget.claimData.attShifts);
      if (shiftKey.isEmpty) continue;
      final parts = shiftKey.split('-');
      if (parts.length != 3) continue;
      final y = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || mo == null || d == null) continue;
      if (y != _currentYear || mo != _currentMonth) continue;

      // Do NOT auto-mark attendance for future shift dates
      final shiftDate = DateTime(y, mo, d);
      if (shiftDate.isAfter(todayDt)) continue;

      byDate.putIfAbsent(shiftKey, () => []).add(m);
    }
    bool overlaps(String start, String end, int wS, int wE) {
      final s = AllowanceCalculator.parseTimeMinutes(start);
      final e = AllowanceCalculator.parseTimeMinutes(end.isEmpty ? start : end);
      if (s == null || e == null) return false;
      var se = e;
      var ss = s;
      if (se <= ss) se += 24 * 60;
      if (wS >= 1320) {
        if (ss < wS) ss += 24 * 60;
        if (se < wS) se += 24 * 60;
      }
      return (se < wE ? se : wE) > (ss > wS ? ss : wS);
    }

    var changed = false;
    byDate.forEach((dateKey, moves) {
      var isN = false, isE = false, isM = false;
      for (final mv in moves) {
        if (mv.start.isEmpty) continue;
        final end = mv.end.isEmpty ? mv.start : mv.end;
        if (overlaps(mv.start, end, 1320, 1800)) isN = true;
        if (overlaps(mv.start, end, 840, 1320)) isE = true;
        if (overlaps(mv.start, end, 360, 840)) isM = true;
      }
      final shifts = <String>[];
      if (isN) shifts.add('N');
      if (isE) shifts.add('E');
      if (isM) shifts.add('M');
      final existing = widget.claimData.attShifts[dateKey];
      if (widget.claimData.attManualDates.contains(dateKey)) return;
      if (shifts.length == 1 &&
          (existing == null ||
              existing.isEmpty ||
              ['N', 'E', 'M'].contains(existing))) {
        widget.claimData.attShifts[dateKey] = shifts[0];
        changed = true;
      }
    });
    if (changed) {
      widget.onChanged();
      setState(() {});
      _showSnack('Attendance updated from movements');
    } else {
      _showSnack('No movements matched to update');
    }
  }

  void _applyRosterChange() {
    widget.claimData.attShifts.clear();
    widget.claimData.attManualDates.clear();
    _generateRosterForMonth(_currentYear, _currentMonth);
    widget.onChanged();
    setState(() {});
  }

  Widget _buildQuickSettings() {
    final scheme = Theme.of(context).colorScheme;
    final offDay = widget.claimData.attOffDay.isEmpty
        ? null
        : widget.claimData.attOffDay;
    final rotation = widget.claimData.attRotation.isEmpty
        ? null
        : widget.claimData.attRotation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _quickLabeled(
                  'ROSTER OFF DAY',
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: offDay,
                      isDense: true,
                      isExpanded: true,
                      hint: const Text('Off Day',
                          style: TextStyle(fontSize: 13)),
                      items: [
                        for (var d = 0; d < 7; d++)
                          DropdownMenuItem(
                              value: '$d',
                              child: Text(_offDayNames[d],
                                  style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        widget.claimData.attOffDay = v;
                        _applyRosterChange();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickLabeled(
                  'STARTING ROTATION',
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: rotation,
                      isDense: true,
                      isExpanded: true,
                      hint: const Text('Rotation',
                          style: TextStyle(fontSize: 13)),
                      items: [
                        for (final r in ['N', 'E', 'M'])
                          DropdownMenuItem(
                              value: r,
                              child: Text(
                                  {
                                    'N': 'Night',
                                    'E': 'Evening',
                                    'M': 'Morning'
                                  }[r]!,
                                  style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        widget.claimData.attRotation = v;
                        _applyRosterChange();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickLabeled(
                  'LOCK',
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Switch(
                        activeThumbColor: scheme.primary,
                        value: widget.claimData.attLocked,
                        onChanged: (v) {
                          setState(() => widget.claimData.attLocked = v);
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickLabeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = _getDaysInMonth(_currentYear, _currentMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          if (widget.claimData.attLocked)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 12, color: scheme.onErrorContainer),
                    const SizedBox(width: 4),
                    Text('Locked',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onErrorContainer)),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.bolt),
            tooltip: 'Auto-detect from movements',
            onPressed: _autoDetectAttendance,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQuickSettings(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _prevMonth),
                Column(
                  children: [
                    Text(_monthLabel(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Tap a day to set its shift',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
                IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _nextMonth),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children:
                  ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Expanded(
                        child: Center(
                            child: Text(d,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant))),
                      )).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final dt = days[index];
                final isCurrentMonthDay =
                    dt.year == _currentYear && dt.month == _currentMonth;
                final info = _shiftForDateInfo(dt);
                final shift = info.code;
                final isPredicted = info.isPredicted;
                final key = _dateKey(dt);
                final isManual =
                    widget.claimData.attManualDates.contains(key);
                final isActingAdm =
                    widget.claimData.actingAdmDates.contains(key);

                return GestureDetector(
                  onTap: isCurrentMonthDay
                      ? () => _showShiftPicker(dt)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: shift.isEmpty
                          ? (isCurrentMonthDay
                              ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
                              : Colors.transparent)
                          : (isPredicted
                              ? _shiftColor(shift, scheme).withValues(alpha: 0.08)
                              : _shiftColor(shift, scheme)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isManual
                            ? scheme.primary
                            : (isPredicted
                                ? scheme.outlineVariant.withValues(alpha: 0.25)
                                : scheme.outlineVariant.withValues(alpha: 0.4)),
                        width: isManual ? 1.8 : 0.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (isActingAdm)
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('A',
                                  style: TextStyle(
                                      fontSize: 7,
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${dt.day}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isCurrentMonthDay
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCurrentMonthDay
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant.withValues(
                                          alpha: 0.5),
                                )),
                            if (shift.isNotEmpty && !isPredicted)
                              Text(shift,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface),
                                  textAlign: TextAlign.center),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    final originalOffDay = widget.claimData.attOffDay;
    final originalRotation = widget.claimData.attRotation;
    final offDay = widget.claimData.attOffDay;
    final rotation = widget.claimData.attRotation.isNotEmpty
        ? widget.claimData.attRotation
        : 'N';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Attendance Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: offDay,
                decoration: const InputDecoration(
                    labelText: 'Roster Off Day',
                    isDense: true),
                items: [
                  '',
                  '0',
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6'
                ].map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d.isEmpty
                        ? '-- Select --'
                        : [
                            'Sunday',
                            'Monday',
                            'Tuesday',
                            'Wednesday',
                            'Thursday',
                            'Friday',
                            'Saturday'
                          ][int.parse(d)]))).toList(),
                onChanged: (v) => setDialogState(
                    () => widget.claimData.attOffDay = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: rotation,
                decoration: const InputDecoration(
                    labelText: 'Starting Rotation',
                    isDense: true),
                items: ['N', 'E', 'M']
                    .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text({
                          'N': 'Night',
                          'E': 'Evening',
                          'M': 'Morning'
                        }[r]!)))
                    .toList(),
                onChanged: (v) => setDialogState(
                    () => widget.claimData.attRotation = v!),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Lock Attendance'),
                subtitle: const Text(
                    'Prevents auto-detection (portal only)'),
                value: widget.claimData.attLocked,
                onChanged: (v) => setDialogState(
                    () => widget.claimData.attLocked = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
            FilledButton(
              onPressed: () {
                final offDayChanged = widget.claimData.attOffDay != originalOffDay;
                final rotationChanged =
                    widget.claimData.attRotation != originalRotation;
                if (offDayChanged || rotationChanged) {
                  widget.claimData.attShifts.clear();
                  widget.claimData.attManualDates.clear();
                  widget.claimData.attLocked = false;
                  _generateRosterForMonth(_currentYear, _currentMonth);
                }
                widget.onChanged();
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
