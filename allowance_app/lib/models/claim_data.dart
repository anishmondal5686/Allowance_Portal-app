import 'master_data.dart';
import 'movement.dart';

class ClaimData {
  MasterData master;
  List<Movement> movements;
  String attOffDay;
  String attRotation;
  Map<String, String> attShifts;
  List<String> attManualDates;
  bool attLocked;

  /// Attendance dates (e.g. '2026-8-10') on which this Dock/Berthing Pilot
  /// performed ADM role work as an "Acting ADM". On these dates ADM rates,
  /// the ADM full-8h night weightage rule, and the ADM standalone forms apply.
  List<String> actingAdmDates;

  ClaimData({
    MasterData? master,
    List<Movement>? movements,
    this.attOffDay = '',
    this.attRotation = 'N',
    Map<String, String>? attShifts,
    List<String>? attManualDates,
    List<String>? actingAdmDates,
    this.attLocked = true,
  })  : master = master ?? MasterData(),
        movements = movements ?? [],
        attShifts = attShifts ?? {},
        attManualDates = attManualDates ?? [],
        actingAdmDates = actingAdmDates ?? [];

  bool isActingAdmOn(String dateKey) =>
      actingAdmDates.contains(_normKey(dateKey));

  static String _normKey(String s) {
    s = s.trim();
    if (s.isEmpty) return '';
    final dm = RegExp(r'^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$')
        .firstMatch(s);
    if (dm != null) {
      final dd = int.parse(dm.group(1)!);
      final mm = int.parse(dm.group(2)!);
      final yy = dm.group(3)!.length == 2
          ? 2000 + int.parse(dm.group(3)!)
          : int.parse(dm.group(3)!);
      return '$yy-$mm-$dd';
    }
    final ym = RegExp(r'^(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})$')
        .firstMatch(s);
    if (ym != null) {
      return '${int.parse(ym.group(1)!)}-${int.parse(ym.group(2)!)}-${int.parse(ym.group(3)!)}';
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
        'master': master.toJson(),
        'movements': movements.map((m) => m.toJson()).toList(),
        'attOffDay': attOffDay,
        'attRotation': attRotation,
        'attShifts': attShifts,
        'attManualDates': attManualDates,
        'actingAdmDates': actingAdmDates,
        'attLocked': attLocked,
      };

  factory ClaimData.fromJson(Map<String, dynamic> json) {
    final masterJson = json['master'] as Map<String, dynamic>? ?? {};
    final movementsList = json['movements'] as List<dynamic>? ?? [];

    return ClaimData(
      master: MasterData.fromJson(masterJson),
      movements: _mergeDuplicateMovements(movementsList
          .map((m) => Movement.fromJson(m as Map<String, dynamic>))
          .toList()),
      attOffDay: json['attOffDay'] as String? ?? '',
      attRotation: json['attRotation'] as String? ?? 'N',
      attShifts: (json['attShifts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      attManualDates: (json['attManualDates'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      actingAdmDates: (json['actingAdmDates'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      attLocked: json['attLocked'] as bool? ?? true,
    );
  }

  List<Movement> getMovementsForDate(String dateKey) {
    return movements.where((m) => m.date == dateKey).toList();
  }

  /// Legacy exports stored one movement as one row per allowance, each row
  /// carrying a single legacy `allowance`/`navigationType` value. Reunite rows
  /// describing the same physical movement into one entry with combined lists.
  static List<Movement> _mergeDuplicateMovements(List<Movement> movements) {
    final result = <Movement>[];
    final seen = <String, Movement>{};
    for (final m in movements) {
      final key = '${m.date}\u0000${m.vessel}\u0000${m.from}\u0000${m.to}'
          '\u0000${m.start}\u0000${m.end}';
      final existing = seen[key];
      if (existing == null) {
        seen[key] = m;
        result.add(m);
      } else {
        existing.allowances = _union(existing.allowances, m.allowances);
        existing.navigationTypes =
            _union(existing.navigationTypes, m.navigationTypes);
        if (existing.loa.isEmpty && m.loa.isNotEmpty) existing.loa = m.loa;
        if (existing.beam.isEmpty && m.beam.isNotEmpty) existing.beam = m.beam;
      }
    }
    return result;
  }

  static List<String> _union(List<String> a, List<String> b) {
    final out = <String>[...a];
    for (final s in b) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  void addMovement(Movement m) {
    movements.add(m);
  }

  void removeMovement(int index) {
    if (index >= 0 && index < movements.length) {
      movements.removeAt(index);
    }
  }

  void updateMovement(int index, Movement m) {
    if (index >= 0 && index < movements.length) {
      movements[index] = m;
    }
  }
}
