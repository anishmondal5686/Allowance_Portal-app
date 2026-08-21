import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';

void main() {
  test('generate 50 fake movements and report the computed summary', () async {
    final rows = <List<String>>[
      // date, vessel, from, to, start, end, loa, beam
      ['01/09/26', 'MV DEEP SAGAR 01', 'OFF', 'LOCK', '06:00', '08:00', '185', '32'],
      ['01/09/26', 'MV DEEP SAGAR 01', 'LOCK', '2', '08:15', '09:00', '185', '32'],
      ['01/09/26', 'MV JAL VIJAY', 'LOCK', 'APPROACH JETTY', '09:00', '10:30', '180', '30'],
      ['02/09/26', 'MV HANSA PRADEEP', '2', '3', '09:00', '10:00', '185', '32'],
      ['02/09/26', 'MV SAGAR SHREYA', 'LOCK', 'APPROACH JETTY', '10:00', '11:30', '182', '31'],
      ['02/09/26', 'MV DEEP SAGAR 01', '3', 'LOCK', '16:00', '17:00', '185', '32'],
      ['03/09/26', 'MV SAGAR SHREYA', 'LOCK', '3', '14:00', '14:45', '182', '31'],
      ['03/09/26', 'MV DEEP SAGAR 01', 'LOCK', 'OFF', '17:30', '18:30', '185', '32'],
      ['04/09/26', 'MV JAL DHARA', 'OFF', 'LOCK', '22:30', '00:30', '200', '33'],
      ['04/09/26', 'MV JAL DHARA', 'LOCK', '7', '00:45', '01:30', '200', '33'],
      ['04/09/26', 'MV RATNA KIRAN', 'LOCK', 'APPROACH JETTY', '08:00', '09:30', '190', '32'],
      ['05/09/26', 'MV SINDHU NANDINI', '4', '4a', '11:00', '12:00', '170', '28'],
      ['05/09/26', 'MV RATNA KIRAN', '6', 'LOCK', '18:00', '19:00', '190', '31'],
      ['06/09/26', 'MV VIJAY DURGA', '7', '8', '14:00', '15:00', '188', '31'],
      ['06/09/26', 'MV PUSHP RAJ', 'LOCK', 'APPROACH JETTY', '23:00', '00:30', '185', '31'],
      ['07/09/26', 'MV JAL TARANG', '4a', '4b', '09:30', '10:30', '190', '33'],
      ['07/09/26', 'MV VIJAY DURGA', '8', 'LOCK', '22:00', '23:00', '200', '33'],
      ['08/09/26', 'MV SAGAR PRABHA', 'OFF', 'LOCK', '10:00', '12:00', '190', '31'],
      ['08/09/26', 'MV SAGAR PRABHA', 'LOCK', '4a', '12:15', '13:00', '190', '31'],
      ['08/09/26', 'MV JAL TARANG', 'LOCK', 'OFF', '13:00', '14:00', '190', '31'],
      ['09/09/26', 'MV ANANDA JYOTI', 'LOCK', '6', '16:00', '16:45', '195', '32'],
      ['09/09/26', 'MV PUSHP RAJ', 'LOCK', 'APPROACH JETTY', '11:00', '12:30', '195', '33'],
      ['10/09/26', 'MV SAGAR PRABHA', '5', '6', '13:00', '14:00', '178', '30'],
      ['10/09/26', 'MV ANANDA JYOTI', '9', 'LOCK', '09:00', '10:00', '195', '32'],
      ['11/09/26', 'MV JAL KRANTI', '8', '9', '15:00', '16:00', '200', '32'],
      ['11/09/26', 'MV RATNA PRABHA', 'LOCK', 'APPROACH JETTY', '07:30', '09:00', '188', '32'],
      ['12/09/26', 'MV SINDHU GOPI', '4b', '5', '10:00', '11:00', '182', '31'],
      ['13/09/26', 'MV MAHARANI', 'OFF', 'LOCK', '23:00', '01:00', '210', '34'],
      ['13/09/26', 'MV MAHARANI', 'LOCK', '11', '01:15', '02:00', '210', '34'],
      ['14/09/26', 'MV GANGA DEEP', '10', 'LOCK', '23:30', '00:30', '205', '34'],
      ['14/09/26', 'MV MAHARANI', 'LOCK', 'APPROACH JETTY', '10:30', '12:00', '200', '34'],
      ['15/09/26', 'MV SWARNA JYOTI', '10', '11', '09:00', '10:00', '195', '34'],
      ['15/09/26', 'MV GANGA DEEP', 'LOCK', 'OFF', '22:30', '23:30', '200', '33'],
      ['16/09/26', 'MV JAGAT NANDINI', '11', '12', '14:00', '15:00', '185', '30'],
      ['17/09/26', 'MV MEENAKSHI', '12', '13', '11:00', '12:00', '178', '29'],
      ['17/09/26', 'MV SWARNA JYOTI', 'LOCK', 'APPROACH JETTY', '22:00', '23:30', '182', '30'],
      ['18/09/26', 'MV SAMUDRA MITRA', 'OFF', 'LOCK', '08:30', '10:30', '178', '30'],
      ['18/09/26', 'MV SAMUDRA MITRA', 'LOCK', '5', '10:45', '11:30', '178', '30'],
      ['19/09/26', 'MV JAL RASHMI', '9', '10', '13:30', '14:30', '190', '33'],
      ['19/09/26', 'MV MEENAKSHI', '11', 'LOCK', '11:00', '12:00', '182', '31'],
      ['20/09/26', 'MV DEEP SHIKHA', 'LOCK', 'APPROACH JETTY', '09:30', '11:00', '190', '33'],
      ['22/09/26', 'MV JAL SAMPADA', '13', '2', '10:00', '11:00', '188', '32'],
      ['22/09/26', 'MV RATNA SAGAR', 'LOCK', 'APPROACH JETTY', '12:00', '13:30', '178', '29'],
      ['23/09/26', 'MV VIJAY AMIT', '12', 'LOCK', '21:00', '22:00', '188', '32'],
      ['23/09/26', 'MV VIJAY AMIT', 'LOCK', 'OFF', '02:00', '03:00', '188', '32'],
      ['24/09/26', 'MV SAGAR DEEP', 'OFF', 'LOCK', '21:30', '23:30', '205', '33'],
      ['24/09/26', 'MV SAGAR DEEP', 'LOCK', '13', '23:45', '00:30', '205', '33'],
      ['25/09/26', 'MV ANANDA DURGA', 'LOCK', 'APPROACH JETTY', '10:00', '11:30', '185', '32'],
      ['26/09/26', 'MV JALADHAR', '13', 'LOCK', '13:00', '14:00', '178', '30'],
      ['27/09/26', 'MV MEENA PRABHA', 'LOCK', 'APPROACH JETTY', '11:30', '13:00', '195', '33'],
    ];

    expect(rows.length, 50);

    final data = ClaimData(
      master: MasterData(
        month: '2026-09',
        name: 'anish mondal',
        designation: 'berthing pilot',
        employee: '20281',
        pay: '83000',
        bill: '9090',
      ),
      attOffDay: '2',
      attRotation: 'M',
      attShifts: {},
      attManualDates: [],
      attLocked: true,
    );

    for (final r in rows) {
      final mv = Movement(
        date: r[0],
        vessel: r[1],
        from: r[2],
        to: r[3],
        start: r[4],
        end: r[5],
        loa: r[6],
        beam: r[7],
      );
      final det = AllowanceCalculator.autoDetect(movement: mv);
      data.movements.add(Movement(
        date: mv.date,
        vessel: mv.vessel,
        from: mv.from,
        to: mv.to,
        start: mv.start,
        end: mv.end,
        loa: mv.loa,
        beam: mv.beam,
        allowances: det.applicable,
        navigationTypes: det.navTypes,
      ));
    }

    final summary = AllowanceCalculator.computeSummary(data);
    for (final l in summary.lines) {
      // ignore: avoid_print
      print('LINE ${l.label} = ${l.amount}');
    }
    // ignore: avoid_print
    print('GRAND = ${summary.grandTotal}');

    final counts = <String, int>{};
    for (final m in data.movements) {
      for (final a in m.allowances) {
        counts[a] = (counts[a] ?? 0) + 1;
      }
    }
    // ignore: avoid_print
    print('COUNTS $counts');

    final outDir = Directory(r'C:\Users\way2m\AppData\Local\Temp\opencode');
    final f = File('${outDir.path}\\fake_data_50.json');
    f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data.toJson()));
    // ignore: avoid_print
    print('WROTE ${f.path}');
  });
}
