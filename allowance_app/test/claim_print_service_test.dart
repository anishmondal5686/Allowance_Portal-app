import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/models/movement.dart';
import 'package:allowance_shared/services/claim_print_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pdfFileName', () {
    test('sanitises month into a file name', () {
      expect(ClaimPrintService.pdfFileName('JULY, 2026'),
          'Allowance_Claim_JULY_2026.pdf');
      expect(ClaimPrintService.pdfFileName('August 2026'),
          'Allowance_Claim_August_2026.pdf');
    });

    test('falls back when month is blank', () {
      expect(ClaimPrintService.pdfFileName('   '),
          'Allowance_Claim_claim.pdf');
    });
  });

  group('buildPdf', () {
    test('produces a valid PDF header with claim data', () async {
      final data = ClaimData(
        master: MasterData(
          month: 'JULY, 2026',
          name: 'A Pilot',
          designation: 'Berthing Pilot',
          employee: 'EMP 123',
          sapEmployeeId: '50007941',
          pay: '100000',
          bill: 'BILL 1',
        ),
      );
      data.movements.add(Movement(
          date: '10/07/26',
          vessel: 'MV TEST',
          from: 'B1',
          to: 'B2',
          start: '23:00',
          end: '01:00',
          loa: '180',
          beam: '32',
          allowance: 'nightact'));

      final bytes = await ClaimPrintService.buildPdf(data);

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('dump calc sheet to disk for PDF verification', () async {
      final dir = Directory(
          r'C:\Users\way2m\AppData\Local\Temp\opencode\gen');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final data = ClaimData(
        master: MasterData(
          month: 'JULY, 2026',
          name: 'A Pilot',
          designation: 'Berthing Pilot',
          employee: 'EMP 123',
          sapEmployeeId: '50007941',
          pay: '100000',
          bill: 'BILL 1',
        ),
        attShifts: {'2026-07-11': 'N'},
      );
      for (var i = 1; i <= 3; i++) {
        data.movements.add(Movement(
            date: '1$i/07/26',
            vessel: 'MV ROW $i',
            from: 'OFF',
            to: 'B2',
            start: '22:00',
            end: '23:30',
            loa: '180',
            beam: '32',
            allowance: 'nightact'));
      }
      data.movements.add(Movement(
          date: '11/07/26',
          vessel: 'MV TEST',
          from: 'B1',
          to: 'B2',
          start: '23:00',
          end: '01:00',
          loa: '180',
          beam: '32',
          allowance: 'length'));
      final f = File('${dir.path}\\calc_sheet.pdf');
      f.writeAsBytesSync(await ClaimPrintService.buildPdf(data));
      expect(f.lengthSync(), greaterThan(500));
    });

    test('builds an empty PDF when there are no movements', () async {
      final bytes =
          await ClaimPrintService.buildPdf(ClaimData(master: MasterData()));
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('paginates a large register without errors', () async {
      final data = ClaimData(
          master: MasterData(month: 'AUGUST, 2026', pay: '50000'));
      for (var i = 0; i < 120; i++) {
        data.movements.add(Movement(
            date: '01/08/26',
            vessel: 'MV $i',
            from: 'A',
            to: 'B',
            start: '10:00',
            end: '11:00',
            loa: '180',
            beam: '32',
            allowance: 'length'));
      }
      final bytes = await ClaimPrintService.buildPdf(data);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
