class MasterData {
  String month;
  String name;
  String designation;
  String employee;
  String pay;
  String bill;
  String basic;
  String ada;

  MasterData({
    this.month = '',
    this.name = '',
    this.designation = '',
    this.employee = '',
    this.pay = '',
    this.bill = '',
    this.basic = '',
    this.ada = '',
  });

  /// Whether the designation identifies an Assistant Dock Master (ADM),
  /// who is paid at ADM-specific allowance rates.
  bool get isAdm {
    final d = designation.toUpperCase();
    return d.contains('ASSISTANT DOCK MASTER') ||
        d.contains('ASST. DOCK MASTER') ||
        d.contains('ASSTT. DOCK MASTER') ||
        RegExp(r'\bADM\b').hasMatch(d);
  }

  /// Whether the designation is the contractual Berthing Pilot post,
  /// which is paid a consolidated pay rather than basic + ADA.
  bool get isBerthingPilot {
    return designation.toUpperCase().contains('BERTHING');
  }

  /// Pay figure to print on a single-pay-line form: consolidated pay for
  /// the Berthing Pilot (contractual), basic pay for regular posts
  /// (Dock Pilot / ADM).
  String get payLine => isBerthingPilot ? pay : basic;

  Map<String, dynamic> toJson() => {
        'month': month,
        'name': name,
        'designation': designation,
        'employee': employee,
        'pay': pay,
        'bill': bill,
        'basic': basic,
        'ada': ada,
      };

  factory MasterData.fromJson(Map<String, dynamic> json) => MasterData(
        month: json['month'] as String? ?? '',
        name: json['name'] as String? ?? '',
        designation: json['designation'] as String? ?? '',
        employee: json['employee'] as String? ?? '',
        pay: json['pay'] as String? ?? '',
        bill: json['bill'] as String? ?? '',
        basic: json['basic'] as String? ?? '',
        ada: json['ada'] as String? ?? '',
      );

  MasterData copy() => MasterData(
        month: month,
        name: name,
        designation: designation,
        employee: employee,
        pay: pay,
        bill: bill,
        basic: basic,
        ada: ada,
      );

  static const monthNames = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  /// Parses a month string like '2026-09', '2026/9', 'JULY, 2026' or
  /// 'September 2026' into (year, month). Returns null if unparseable.
  static (int, int)? parseMonthYear(String month) {
    final s = month.trim();
    if (s.isEmpty) return null;

    var m = RegExp(r'^(\d{4})[\/\-.](\d{1,2})$').firstMatch(s);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) return (y, mo);
    }
    m = RegExp(r'^(\d{1,2})[\/\-.](\d{4})$').firstMatch(s);
    if (m != null) {
      final mo = int.tryParse(m.group(1)!);
      final y = int.tryParse(m.group(2)!);
      if (y != null && mo != null && mo >= 1 && mo <= 12) return (y, mo);
    }
    final upper = s.toUpperCase();
    for (var i = 0; i < monthNames.length; i++) {
      if (upper.contains(monthNames[i])) {
        final ym = RegExp(r'(?:19|20)\d{2}').firstMatch(s);
        if (ym == null) return null;
        final y = int.tryParse(ym.group(0)!);
        if (y == null) return null;
        return (y, i + 1);
      }
    }
    return null;
  }

  /// Canonical key, e.g. '2026-09'.
  static String monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  /// Friendly label, e.g. 'SEPTEMBER, 2026'.
  static String monthLabel(int year, int month) =>
      '${monthNames[month - 1]}, $year';

  /// Friendly label from any supported month string, e.g. 'SEPTEMBER, 2026'.
  /// Returns the trimmed input when it can't be parsed.
  static String displayMonth(String month) {
    final parsed = parseMonthYear(month);
    if (parsed != null) return monthLabel(parsed.$1, parsed.$2);
    return month.trim();
  }
}
