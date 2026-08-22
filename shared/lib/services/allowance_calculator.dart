import '../models/claim_data.dart';
import '../models/master_data.dart';
import '../models/movement.dart';
import 'sun_table.dart';

class AutoDetectResult {
  final String allowance;
  final List<String> applicable;
  final List<String> navTypes;

  AutoDetectResult({
    required this.allowance,
    required this.applicable,
    this.navTypes = const [],
  });

  String get navigationType => navTypes.isNotEmpty ? navTypes.first : '';
}

class ClaimSummaryLine {
  final String key;
  final String label;
  final double amount;

  ClaimSummaryLine(this.key, this.label, this.amount);
}

class ClaimSummary {
  final List<ClaimSummaryLine> lines;
  final double grandTotal;
  final bool payWarning;

  /// Total night weightage time in hours. Set for an ADM claim, whose night
  /// weightage is credited as time (hours) rather than a pay-based amount.
  final double nightWeightageHours;

  /// True when the night weightage is shown as an amount line (Berthing Pilot).
  bool get hasWeightageAmount => lines.any((l) => l.key == 'weightage');

  ClaimSummary({
    required this.lines,
    required this.grandTotal,
    required this.payWarning,
    this.nightWeightageHours = 0,
  });
}

class AllowanceCalculator {
  static const int minPerNight = 480;

  static const Map<String, String> allowanceLabels = {
    'length': 'Length Allowance',
    'cold': 'Cold Movement',
    'nightact': 'Night Act',
    'lock': 'Lock to Approach Jetty',
    'navigation': 'Night Navigation',
    'weightage': 'Night Weightage',
  };

  static const List<String> _displayOrder = [
    'length',
    'cold',
    'nightact',
    'lock',
    'navigation',
    'weightage',
  ];

  static int? _parseTimeLoose(String t) {
    if (t.isEmpty) return null;
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    final c = digits.length > 4 ? digits.substring(0, 4) : digits.padLeft(4, '0');
    return int.parse(c.substring(0, 2)) * 60 + int.parse(c.substring(2, 4));
  }

  static int? _parseTimeStrict(String t) {
    if (t.isEmpty) return null;
    final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
    final c = digits.length > 4 ? digits.substring(0, 4) : digits.padLeft(4, '0');
    final h = int.parse(c.substring(0, 2));
    final m = int.parse(c.substring(2, 4));
    if (h > 24 || m >= 60) return null;
    return h * 60 + m;
  }

  static int? parseTimeMinutes(String t) => _parseTimeStrict(t);

  static String normDateKey(String s) {
    s = s.trim();
    if (s.isEmpty) return '';
    final dm = RegExp(r'^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$').firstMatch(s);
    if (dm != null) {
      final dd = int.parse(dm.group(1)!);
      final mm = int.parse(dm.group(2)!);
      final yy = dm.group(3)!.length == 2 ? 2000 + int.parse(dm.group(3)!) : int.parse(dm.group(3)!);
      return '$yy-$mm-$dd';
    }
    final ym = RegExp(r'^(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})$').firstMatch(s);
    if (ym != null) {
      return '${int.parse(ym.group(1)!)}-${int.parse(ym.group(2)!)}-${int.parse(ym.group(3)!)}';
    }
    return s;
  }

  static String prevDateKey(String dk) {
    final p = dk.split('-');
    if (p.length != 3) return dk;
    final y = int.tryParse(p[0]);
    final mo = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || mo == null || d == null) return dk;
    final dt = DateTime(y, mo, d).subtract(const Duration(days: 1));
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  /// Calendar-date key of the shift [m] belongs to. A night shift runs
  /// 22:00 on its date to 06:00 the next day. Movements starting before
  /// 05:30 are attributed to the previous date's night shift. Movements
  /// between 05:30 and 06:00 belong to the previous night shift if previous date
  /// attendance was 'N' (a pilot working night shift cannot do morning shift next day).
  /// Otherwise, respects 'M' or 'E' attendance on the movement date.
  static String movementShiftDate(Movement m, {Map<String, String>? attShifts}) {
    final dk = normDateKey(m.date.trim());
    if (dk.isEmpty) return dk;
    final sMin = _parseTimeStrict(m.start);
    if (sMin == null) return dk;
    if (sMin < 330) return prevDateKey(dk);
    if (sMin < 360) {
      if (attShifts != null) {
        final prevDk = prevDateKey(dk);
        if (attShifts[prevDk] == 'N') return prevDk;
        final att = attShifts[dk];
        if (att == 'M' || att == 'E') return dk;
      }
      return prevDateKey(dk);
    }
    return dk;
  }

  static String getPrevDateStr(String dateStr) {
    final m = RegExp(r'^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$').firstMatch(dateStr);
    if (m == null) return '';
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = m.group(3)!.length == 2 ? 2000 + int.parse(m.group(3)!) : int.parse(m.group(3)!);
    final dt = DateTime(y, mo - 1, d).subtract(const Duration(days: 1));
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  static (int, int)? getSunTimes(String dateStr) {
    final m = RegExp(r'^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$').firstMatch(dateStr);
    if (m == null) return null;
    final dd = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    final yy = m.group(3)!.length == 2 ? 2000 + int.parse(m.group(3)!) : int.parse(m.group(3)!);
    final dt = DateTime(yy, mm - 1, dd);
    final doy = dt.difference(DateTime(yy, 0, 0)).inDays;
    if (doy < 1 || doy > 365) return null;
    return (sunriseMinutes[doy - 1], sunsetMinutes[doy - 1]);
  }

  /// Format minutes-since-midnight to 'HH:MM' (24h).
  static String minToHHMM(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static int calcNightOverlapMinutes(String startTime, String endTime) {
    final s = _parseTimeLoose(startTime);
    if (s == null) return 0;
    final e = _parseTimeLoose(endTime);
    const nightStart = 22 * 60;
    const nightEnd = 6 * 60 + 24 * 60;
    var segStart = s;
    var segEnd = e ?? s;
    if (segEnd < segStart) segEnd += 24 * 60;
    if (segStart < nightStart) segStart += 24 * 60;
    if (segEnd < nightStart) segEnd += 24 * 60;
    final v = (segEnd < nightEnd ? segEnd : nightEnd) - (segStart > nightStart ? segStart : nightStart);
    return v < 0 ? 0 : v;
  }

  static bool calcNightNavOverlap(String startTime, String endTime, String dateStr) {
    final s = _parseTimeLoose(startTime);
    if (s == null) return false;
    final e = _parseTimeLoose(endTime);
    final sun = getSunTimes(dateStr);
    if (sun == null) return false;
    final navStart = sun.$2 + 30;
    final navEnd = sun.$1 - 30 + 24 * 60;
    if (s < 360) {
      final prevSun = getSunTimes(getPrevDateStr(dateStr));
      if (prevSun != null) {
        final prevNavStart = prevSun.$2 + 30;
        final prevNavEnd = prevSun.$1 - 30 + 24 * 60;
        final segStart = s + 24 * 60;
        final segEnd = e != null ? e + 24 * 60 : segStart;
        if ((segEnd < prevNavEnd ? segEnd : prevNavEnd) > (segStart > prevNavStart ? segStart : prevNavStart)) {
          return true;
        }
      }
      var segStart = s;
      var segEnd = e ?? s;
      if (segEnd < segStart) segEnd += 24 * 60;
      return (segEnd < navEnd ? segEnd : navEnd) > (segStart > navStart ? segStart : navStart);
    }
    var segStart = s;
    var segEnd = e ?? s;
    if (segEnd < segStart) segEnd += 24 * 60;
    return (segEnd < navEnd ? segEnd : navEnd) > (segStart > navStart ? segStart : navStart);
  }

  static double lengthAmount(double loa) => loa >= 175.26 ? 310 : 0;

  static double coldAmount() => 160;

  static double nightActAmount(double loa) =>
      loa >= 175.26 ? 205 : 135;

  static double lockAmount({bool adm = false}) => adm ? 1500 : 1000;

  static double navigationAmount(String navType, double loa, double beam,
      {bool adm = false}) {
    switch (navType) {
      case 'outward-180-210':
        return loa >= 180 ? (adm ? 675 : 540) : 0;
      case 'outward-210':
        return loa >= 210 ? (adm ? 1010 : 810) : 0;
      case 'outward-beam':
        return beam >= 30.5 ? (adm ? 675 : 540) : 0;
      case 'inward-210':
        return loa >= 210 ? 540 : 0;
      case 'double-banking':
        return 540;
      case 'unbanking':
        return 540;
      default:
        return 0;
    }
  }

  static double amountFor({
    required String allowance,
    required Movement movement,
    bool adm = false,
  }) {
    final loa = double.tryParse(movement.loa) ?? 0;
    final beam = double.tryParse(movement.beam) ?? 0;
    switch (allowance) {
      case 'length':
        // ADM (and BP acting as ADM) also earns the length allowance at the
        // same rate; only cold / nightact remain BP-DP-only.
        return lengthAmount(loa);
      case 'cold':
        return adm ? 0 : coldAmount();
      case 'nightact':
        return adm ? 0 : nightActAmount(loa);
      case 'lock':
        return lockAmount(adm: adm);
      case 'navigation':
        if (movement.navigationTypes.isEmpty) {
          return navigationAmount('', loa, beam, adm: adm);
        }
        return movement.navigationTypes.fold(
            0,
            (sum, t) =>
                sum + navigationAmount(t, loa, beam, adm: adm));
      default:
        return 0;
    }
  }

  static AutoDetectResult autoDetect({required Movement movement}) {
    final loa = double.tryParse(movement.loa) ?? 0;
    final beam = double.tryParse(movement.beam) ?? 0;
    final from = movement.from.toUpperCase();
    final to = movement.to.toUpperCase();
    final applicable = <String>[];

    final isApproachJetty =
        RegExp(r'(APPROACH\s*JETTY|APP\.?\s*JETTY)').hasMatch;
    final lockToJetty = from.contains('LOCK') && isApproachJetty(to);
    final jettyToLock = isApproachJetty(from) && to.contains('LOCK');
    if (lockToJetty || jettyToLock) {
      return AutoDetectResult(allowance: 'lock', applicable: ['lock']);
    }

    final hasLength = loa >= 175.26;
    if (hasLength) applicable.add('length');

    final hasNight = calcNightOverlapMinutes(movement.start, movement.end) > 0;
    if (hasNight) applicable.add('nightact');

    final hasNavNight =
        calcNightNavOverlap(movement.start, movement.end, movement.date);
    final hasLock = from.contains('LOCK') || to.contains('LOCK');
    final isOutward = to.contains('LOCK');
    final isFromLock = from.contains('LOCK');
    final lockNav = hasNavNight &&
        hasLock &&
        ((isOutward && (loa >= 180 || beam >= 30.5)) || (isFromLock && loa >= 210));
    final hasOffOrigin = RegExp(r'\bOFF\b').hasMatch(from);
    final hasOffDest = RegExp(r'\bOFF\b').hasMatch(to);
    final offNav = hasNavNight && (hasOffOrigin || hasOffDest);
    final shouldNav = lockNav || offNav;

    final navTypes = <String>[];
    if (shouldNav) {
      if (offNav) {
        if (hasOffOrigin) navTypes.add('unbanking');
        if (hasOffDest) navTypes.add('double-banking');
      }
      if (lockNav) {
        if (to.contains('LOCK')) {
          if (loa >= 210) {
            navTypes.add('outward-210');
          } else if (loa >= 180) {
            navTypes.add('outward-180-210');
          } else if (beam >= 30.5) {
            navTypes.add('outward-beam');
          }
        }
        if (from.contains('LOCK')) {
          if (loa >= 210) navTypes.add('inward-210');
        }
      }
      applicable.add('navigation');
    }

    String primary;
    if (shouldNav) {
      primary = 'navigation';
    } else if (hasNight) {
      primary = 'nightact';
    } else if (hasLength) {
      primary = 'length';
    } else {
      primary = '';
    }
    return AutoDetectResult(
      allowance: primary,
      applicable: applicable,
      navTypes: navTypes,
    );
  }

  /// True when [dk] (`yyyy-M-d` key) belongs to a future month after the current month.
  static bool _isFutureKey(String dk) {
    final p = dk.split('-');
    if (p.length != 3 || p.any((e) => int.tryParse(e) == null)) return false;
    final y = int.parse(p[0]);
    final m = int.parse(p[1]);
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final dtMonthStart = DateTime(y, m, 1);
    return dtMonthStart.isAfter(currentMonthStart);
  }

  static int calcNightWeightageMinutes({
    required List<Movement> movements,
    required Map<String, String> attShifts,
    bool locked = true,
    bool fullNights = false,
    Set<String> actingAdmDates = const {},
  }) {
    if (!locked) return 0;
    final nDates = <String>{};
    attShifts.forEach((dateKey, shift) {
      if (shift == 'N') nDates.add(normDateKey(dateKey));
    });
    // Future dates earn no weightage.
    nDates.removeWhere(_isFutureKey);
    if (fullNights) return nDates.length * minPerNight;
    final acting = <String>{};
    for (final d in actingAdmDates) {
      final k = normDateKey(d);
      if (k.isNotEmpty && !_isFutureKey(k)) acting.add(k);
    }
    final byShift = <String, int>{};
    for (final m in movements) {
      final rawDate = m.date.trim();
      if (rawDate.isEmpty ||
          !(m.hasAllowance('nightact') || m.hasAllowance('lock'))) {
        continue;
      }
      final dk = normDateKey(rawDate);
      final sMin = _parseTimeStrict(m.start);
      final att = attShifts[dk];
      String shiftKey;
      if (sMin == null) {
        shiftKey = dk;
      } else if (sMin < 330) {
        shiftKey = prevDateKey(dk);
      } else if (sMin < 360) {
        if (att == 'M' || att == 'E') continue;
        shiftKey = prevDateKey(dk);
      } else if (sMin >= 1320) {
        shiftKey = dk;
      } else if (sMin >= 1290) {
        if (att == 'E') continue;
        shiftKey = dk;
      } else if (sMin >= 810 && sMin < 840) {
        if (att == 'E') continue;
        shiftKey = dk;
      } else {
        shiftKey = dk;
      }
      byShift[shiftKey] = (byShift[shiftKey] ?? 0) + calcNightOverlapMinutes(m.start, m.end);
    }
    attShifts.forEach((dateKey, shift) {
      if (shift != 'N') return;
      final date = normDateKey(dateKey);
      byShift.putIfAbsent(date, () => 0);
    });
    var total = 0;
    for (final entry in byShift.entries) {
      if (!nDates.contains(entry.key)) continue;
      if (acting.contains(entry.key)) {
        total += minPerNight;
        continue;
      }
      final activeMins = entry.value;
      total += (minPerNight - activeMins) < 0 ? 0 : (minPerNight - activeMins);
    }
    return total;
  }

  static bool hasWeightage({
    required List<Movement> movements,
    required Map<String, String> attShifts,
    bool locked = true,
  }) {
    if (!locked) return false;
    return attShifts.values.contains('N');
  }

  static double nightWeightageAmount({
    required double pay,
    required List<Movement> movements,
    required Map<String, String> attShifts,
    bool locked = true,
    bool fullNights = false,
    Set<String> actingAdmDates = const {},
  }) {
    if (!locked) return 0;
    final minutes = calcNightWeightageMinutes(
        movements: movements,
        attShifts: attShifts,
        locked: locked,
        fullNights: fullNights,
        actingAdmDates: actingAdmDates);
    final hours = minutes / 60.0;
    return (hours / 1440.0) * pay;
  }

  /// Movements whose date falls within the claim month (master.month).
  /// Returns all movements when the month can't be parsed (e.g. empty).
  static List<Movement> movementsForMonth(ClaimData data) {
    final parsed = MasterData.parseMonthYear(data.master.month);
    List<Movement> out;
    if (parsed == null) {
      out = data.movements.toList();
    } else {
      final (y, mo) = parsed;
      out = data.movements.where((m) {
        final p = normDateKey(m.date.trim()).split('-');
        if (p.length != 3) return false;
        final my = int.tryParse(p[0]);
        final mm = int.tryParse(p[1]);
        return my == y && mm == mo;
      }).toList();
    }
    out.sort((a, b) {
      final pa = normDateKey(a.date.trim()).split('-');
      final pb = normDateKey(b.date.trim()).split('-');
      final ay = pa.length == 3 ? int.tryParse(pa[0]) ?? 0 : 0;
      final am = pa.length == 3 ? int.tryParse(pa[1]) ?? 0 : 0;
      final ad = pa.length == 3 ? int.tryParse(pa[2]) ?? 0 : 0;
      final by = pb.length == 3 ? int.tryParse(pb[0]) ?? 0 : 0;
      final bm = pb.length == 3 ? int.tryParse(pb[1]) ?? 0 : 0;
      final bd = pb.length == 3 ? int.tryParse(pb[2]) ?? 0 : 0;
      final cy = ay.compareTo(by);
      if (cy != 0) return cy;
      final cm = am.compareTo(bm);
      if (cm != 0) return cm;
      return ad.compareTo(bd);
    });
    return out;
  }

  /// Attendance shifts whose key falls within the claim month.
  /// Returns all shifts when the month can't be parsed (e.g. empty).
  static Map<String, String> attShiftsForMonth(ClaimData data) {
    final parsed = MasterData.parseMonthYear(data.master.month);
    if (parsed == null) return data.attShifts;
    final (y, mo) = parsed;
    final out = <String, String>{};
    data.attShifts.forEach((k, v) {
      final p = k.split('-');
      if (p.length != 3) return;
      final ky = int.tryParse(p[0]);
      final km = int.tryParse(p[1]);
      if (ky == y && km == mo) out[k] = v;
    });
    return out;
  }

  /// Fills in the weekly attendance roster for [year]/[month] exactly like the
  /// webapp: off days become 'OFF', all other missing dates get the rotation
  /// shift (M/E/N) advancing by calendar week. Existing entries are preserved.
  static Map<String, String> fillRoster({
    required int year,
    required int month,
    required String offDay,
    required String rotation,
    required Map<String, String> existing,
  }) {
    final out = Map<String, String>.of(existing);
    if (offDay.isEmpty && rotation.isEmpty) return out;
    final offDayNum = offDay.isNotEmpty ? int.tryParse(offDay) : null;
    const rot = {'N': 'E', 'E': 'M', 'M': 'N'};
    final totalDays = DateTime(year, month + 1, 0).day;
    for (var d = 1; d <= totalDays; d++) {
      final key = '$year-$month-$d';
      if (out.containsKey(key)) continue;
      final dow = DateTime(year, month, d).weekday % 7;
      if (offDayNum != null && dow == offDayNum) {
        out[key] = 'OFF';
      } else if (rotation.isNotEmpty) {
        final weekIndex = (d - 1) ~/ 7;
        var shift = rotation;
        for (var w = 0; w < weekIndex; w++) {
          shift = rot[shift] ?? shift;
        }
        out[key] = shift;
      }
    }
    return out;
  }

  /// Effective attendance shifts for the claim month: the stored shifts plus
  /// any roster dates auto-filled from off day / starting rotation, so the
  /// night weightage output matches the webapp.
  static Map<String, String> effectiveAttShifts(ClaimData data) {
    final parsed = MasterData.parseMonthYear(data.master.month);
    if (parsed == null) return attShiftsForMonth(data);
    final (y, mo) = parsed;
    return fillRoster(
      year: y,
      month: mo,
      offDay: data.attOffDay,
      rotation: data.attRotation,
      existing: attShiftsForMonth(data),
    );
  }

  static ClaimSummary computeSummary(ClaimData data) {
    final pay = data.master.isBerthingPilot
        ? double.tryParse(
                  data.master.pay.replaceAll(RegExp(r'[^0-9.]'), '')) ??
              0
        : (double.tryParse(
                    data.master.basic.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                0) +
            (double.tryParse(data.master.ada.replaceAll(RegExp(r'[^0-9.]'), '')) ??
                0);
    final movements = movementsForMonth(data);
    final attShifts = effectiveAttShifts(data);
    final totals = <String, double>{};
    for (final m in movements) {
      for (final a in m.allowances) {
        final amt = amountFor(
            allowance: a,
            movement: m,
            adm: data.master.isAdm ||
                data.isActingAdmOn(movementShiftDate(m)));
        if (amt > 0) totals[a] = (totals[a] ?? 0) + amt;
      }
    }
    final hasW = hasWeightage(
        movements: movements,
        attShifts: attShifts,
        locked: data.attLocked);
    // Only the contractual Berthing Pilot gets a pay-based night weightage
    // amount; regular posts (Dock Pilot, ADM) are credited by time (hours).
    final timeOnly = !data.master.isBerthingPilot;
    final payWarning = hasW && pay == 0 && !timeOnly;
    var nightWeightageHours = 0.0;
    if (hasW) {
      final weightMinutes = calcNightWeightageMinutes(
          movements: movements,
          attShifts: attShifts,
          locked: data.attLocked,
          fullNights: data.master.isAdm,
          actingAdmDates: data.actingAdmDates.toSet());
      nightWeightageHours = weightMinutes / 60.0;
      if (!timeOnly && !payWarning) {
        totals['weightage'] = ((weightMinutes / 60.0) / 1440.0) * pay;
      }
    }
    final lines = <ClaimSummaryLine>[];
    var grandTotal = 0.0;
    for (final key in _displayOrder) {
      final amt = totals[key] ?? 0;
      if (amt == 0) continue;
      lines.add(ClaimSummaryLine(key, allowanceLabels[key] ?? key, amt));
      grandTotal += amt;
    }
    return ClaimSummary(
        lines: lines,
        grandTotal: grandTotal,
        payWarning: payWarning,
        nightWeightageHours: nightWeightageHours);
  }
}
