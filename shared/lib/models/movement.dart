class Movement {
  String date;
  String vessel;
  String from;
  String to;
  String start;
  String end;
  String loa;
  String beam;
  List<String> allowances;
  List<String> navigationTypes;

  Movement({
    this.date = '',
    this.vessel = '',
    this.from = '',
    this.to = '',
    this.start = '',
    this.end = '',
    this.loa = '',
    this.beam = '',
    List<String>? allowances,
    List<String>? navigationTypes,
    String? allowance,
    String? navigationType,
  })  : allowances = allowances ??
            (allowance != null && allowance.isNotEmpty ? [allowance] : []),
        navigationTypes = navigationTypes ??
            (navigationType != null && navigationType.isNotEmpty
                ? [navigationType]
                : []);

  bool hasAllowance(String allowance) => allowances.contains(allowance);

  bool hasNavigationType(String type) => navigationTypes.contains(type);

  Map<String, dynamic> toJson() => {
        'date': date,
        'vessel': vessel,
        'from': from,
        'to': to,
        'start': start,
        'end': end,
        'loa': loa,
        'beam': beam,
        'allowances': allowances,
        'navigationTypes': navigationTypes,
      };

  factory Movement.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) {
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    final legacyAllowance = json['allowance'] as String? ?? '';
    final legacyNavType = json['navigationType'] as String? ?? '';

    return Movement(
      date: json['date'] as String? ?? '',
      vessel: json['vessel'] as String? ?? '',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      start: json['start'] as String? ?? '',
      end: json['end'] as String? ?? '',
      loa: json['loa'] as String? ?? '',
      beam: json['beam'] as String? ?? '',
      allowances: strList(json['allowances']).isNotEmpty
          ? strList(json['allowances'])
          : (legacyAllowance.isNotEmpty ? [legacyAllowance] : []),
      navigationTypes: strList(json['navigationTypes']).isNotEmpty
          ? strList(json['navigationTypes'])
          : (legacyNavType.isNotEmpty ? [legacyNavType] : []),
    );
  }

  Movement copy() => Movement(
        date: date,
        vessel: vessel,
        from: from,
        to: to,
        start: start,
        end: end,
        loa: loa,
        beam: beam,
        allowances: List.of(allowances),
        navigationTypes: List.of(navigationTypes),
      );
}
