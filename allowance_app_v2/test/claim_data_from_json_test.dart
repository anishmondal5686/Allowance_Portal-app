import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';

void main() {
  group('ClaimData.fromJson legacy movement merge', () {
    test('merges rows of the same movement into one entry with combined lists',
        () {
      final json = {
        'master': {
          'month': 'MAY, 2026',
          'name': 'ANISH MONDAL',
          'designation': 'BERTHING PILOT',
          'employee': '20281',
          'pay': '83000',
          'bill': '9090',
        },
        'movements': [
          {
            'date': '07/05/2026',
            'vessel': 'DUCHESS MAGNOLIA',
            'from': '4B',
            'to': 'LOCK',
            'start': '0230',
            'end': '0430',
            'loa': '229.0',
            'beam': '32.26',
            'allowance': 'length',
            'navigationType': '',
          },
          {
            'date': '07/05/2026',
            'vessel': 'DUCHESS MAGNOLIA',
            'from': '4B',
            'to': 'LOCK',
            'start': '0230',
            'end': '0430',
            'loa': '229.0',
            'beam': '32.26',
            'allowance': 'nightact',
            'navigationType': '',
          },
          {
            'date': '07/05/2026',
            'vessel': 'DUCHESS MAGNOLIA',
            'from': '4B',
            'to': 'LOCK',
            'start': '0230',
            'end': '0430',
            'loa': '229.0',
            'beam': '32.26',
            'allowance': 'navigation',
            'navigationType': 'outward-210',
          },
          {
            'date': '07/05/2026',
            'vessel': 'DUCHESS MAGNOLIA',
            'from': 'LOCK',
            'to': 'APPROACH JETTY',
            'start': '0520',
            'end': '0550',
            'loa': '229.0',
            'beam': '32.2',
            'allowance': 'lock',
            'navigationType': '',
          },
        ],
      };

      final data = ClaimData.fromJson(json);

      expect(data.movements.length, 2);
      final leg = data.movements.first;
      expect(leg.allowances, ['length', 'nightact', 'navigation']);
      expect(leg.navigationTypes, ['outward-210']);
      final lock = data.movements[1];
      expect(lock.allowances, ['lock']);
      expect(lock.navigationTypes, isEmpty);
    });

    test('keeps distinct movements separate', () {
      final json = {
        'master': {'month': ''},
        'movements': [
          {
            'date': '03/05/2026',
            'vessel': 'SITC CEBU',
            'from': '10',
            'to': 'LOCK',
            'start': '1706',
            'end': '1842',
            'loa': '188.8',
            'beam': '32.2',
            'allowance': 'length',
            'navigationType': '',
          },
          {
            'date': '03/05/2026',
            'vessel': 'SITC CEBU',
            'from': '10',
            'to': 'LOCK',
            'start': '1706',
            'end': '1842',
            'loa': '188.8',
            'beam': '32.2',
            'allowances': ['navigation'],
            'navigationTypes': ['outward-180-210'],
          },
          {
            'date': '03/05/2026',
            'vessel': 'SITC CEBU',
            'from': 'LOCK',
            'to': 'APPROACH JETTY',
            'start': '1906',
            'end': '1930',
            'loa': '188.9',
            'beam': '32.2',
            'allowance': 'lock',
            'navigationType': '',
          },
        ],
      };

      final data = ClaimData.fromJson(json);

      expect(data.movements.length, 2);
      final leg = data.movements.first;
      expect(leg.allowances, ['length', 'navigation']);
      expect(leg.navigationTypes, ['outward-180-210']);
    });

    test('leaves modern list-format data untouched', () {
      final json = {
        'master': {'month': ''},
        'movements': [
          {
            'date': '01/09/26',
            'vessel': 'MV DEEP SAGAR 01',
            'from': 'OFF',
            'to': 'LOCK',
            'start': '06:00',
            'end': '08:00',
            'loa': '185',
            'beam': '32',
            'allowances': ['length'],
            'navigationTypes': [],
          },
          {
            'date': '01/09/26',
            'vessel': 'MV DEEP SAGAR 01',
            'from': 'LOCK',
            'to': '2',
            'start': '08:15',
            'end': '09:00',
            'loa': '185',
            'beam': '32',
            'allowances': ['length'],
            'navigationTypes': [],
          },
        ],
      };

      final data = ClaimData.fromJson(json);

      expect(data.movements.length, 2);
      expect(data.movements.first.allowances, ['length']);
    });
  });
}
