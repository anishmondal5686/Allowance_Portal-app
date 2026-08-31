import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/claim_data.dart';
import '../models/master_data.dart';
import 'allowance_calculator.dart';

class ClaimPrintService {
  static const _fallbackName = 'claim';

  static final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static String pdfFileName(String month) {
    final cleaned = month
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'Allowance_Claim_${cleaned.isEmpty ? _fallbackName : cleaned}.pdf';
  }

  static Future<void> printClaim(ClaimData data) async {
    final bytes = await buildPdf(data);
    await Printing.layoutPdf(
      name: pdfFileName(data.master.month),
      onLayout: (_) async => bytes,
    );
  }

  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> _getTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    _cachedTheme = pw.ThemeData.withFont(base: regular, bold: bold);
    return _cachedTheme!;
  }

  static Future<Uint8List> buildPdf(ClaimData data) async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);
    final sheet = AllowanceCalculator.calcSheet(data);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28.3, 22.7, 28.3, 22.7),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _headerBlock(data, sheet),
          _table(
            title: sheet.isAdm
                ? 'CALCULATION SHEET OF MARINE ALLOWANCES FOR ADM'
                : 'CALCULATION SHEET OF MARINE ALLOWANCES FOR DP/BP',
            rows: sheet.baseRows,
          ),
          if (sheet.hasActing) ...[
            pw.SizedBox(height: 6),
            _table(
              title: 'ACTING ADM ALLOWANCES',
              rows: sheet.actingRows,
            ),
          ],
          pw.SizedBox(height: 6),
          _grandTotalRow(sheet),
        ],
      ),
    ));
    return doc.save();
  }

  static String _d(String v) => v.trim().isEmpty ? '—' : v.trim();

  static String _monthLabel(String month) {
    final parsed = MasterData.parseMonthYear(month);
    if (parsed != null) return MasterData.monthLabel(parsed.$1, parsed.$2);
    return month.trim();
  }

  static pw.Widget _headerBlock(ClaimData data, CalcSheet sheet) {
    final m = data.master;
    final isBP = m.isBerthingPilot;
    final payValue = isBP ? _d(m.pay) : _d(m.basic);
    final secondRight = sheet.isAdm ? _d(m.ada) : '';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          sheet.isAdm
              ? 'CALCULATION SHEET OF MARINE ALLOWANCES FOR ADM'
              : 'CALCULATION SHEET OF MARINE ALLOWANCES FOR DP/BP',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(30),
            1: pw.FlexColumnWidth(50),
            2: pw.FlexColumnWidth(30),
            3: pw.FlexColumnWidth(50),
          },
          border: pw.TableBorder.all(color: PdfColors.black),
          children: [
            _kvRow2('NAME', _d(m.name), 'MONTH/YEAR',
                _monthLabel(data.master.month)),
            _kvRow2('DESIGNATION', _d(m.designation), 'PAY', payValue),
            _kvRow2('EMPLOYEE NO', _d(m.employee), 'ADA', secondRight),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.TableRow _kvRow2(String l1, String v1, String l2, String v2) {
    pw.Container cell(String label, String value, {bool isLabel = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
        color: isLabel ? PdfColors.grey200 : null,
        child: pw.Text(
            isLabel ? label : (value.isEmpty ? '' : value),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );
    }

    return pw.TableRow(
      children: [
        cell(l1, '', isLabel: true),
        cell('', v1),
        cell(l2, '', isLabel: true),
        cell('', v2),
      ],
    );
  }

  static pw.Widget _table({
    required String title,
    required List<CalcSheetRow> rows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(10),
            1: pw.FlexColumnWidth(52),
            2: pw.FlexColumnWidth(14),
            3: pw.FlexColumnWidth(12),
            4: pw.FlexColumnWidth(12),
            5: pw.FlexColumnWidth(12),
            6: pw.FlexColumnWidth(15),
          },
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.75),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            _calHead(),
            for (var i = 0; i < rows.length; i++)
              _calRow(i + 1, rows[i]),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _calHead() {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        for (final c in const [
          'SL NO',
          'CATAGORY',
          'RATE CHART',
          'CODE (OLD)',
          'CODE (SAP-NEW)',
          'TOTAL NO OF MOVEMENTS',
          'TOTAL AMOUNT',
        ])
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 2, vertical: 3),
            child: pw.Text(c,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
          ),
      ],
    );
  }

  static pw.TableRow _calRow(int sl, CalcSheetRow row) {
    if (row.isWeightage) {
      return pw.TableRow(
        children: [
          _calCell('$sl'),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: pw.Text(row.category,
                style: const pw.TextStyle(fontSize: 7)),
          ),
          _calCell(row.rateChart),
          _calCell(row.oldCode),
          _calCell(row.sapCode),
          _calCell(row.hours == 0 ? '' : '${row.hours.toStringAsFixed(2)} HRS'),
          _calCell(row.amount == 0 ? '' : _money.format(row.amount)),
        ],
      );
    }
    return pw.TableRow(
      children: [
        _calCell('$sl'),
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Text(row.category,
              style: const pw.TextStyle(fontSize: 7)),
        ),
        _calCell(row.rateChart),
        _calCell(row.oldCode),
        _calCell(row.sapCode),
        _calCell(row.count == 0 ? '' : '${row.count}'),
        _calCell(
            row.amount == 0 ? '' : _money.format(row.amount)),
      ],
    );
  }

  static pw.Widget _grandTotalRow(CalcSheet sheet) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text('GRAND TOTAL',
                style: pw.TextStyle(
                    fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(sheet.weightageAmount == 0
              ? '(Except Night Weightage)'
              : '',
              style: pw.TextStyle(
                  fontSize: 6.5, color: PdfColors.grey800)),
          pw.SizedBox(width: 12),
          pw.Text(_money.format(sheet.grandTotal),
              style: pw.TextStyle(
                  fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Container _calCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7)),
    );
  }
}
