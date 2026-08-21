import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/claim_data.dart';
import '../models/master_data.dart';
import '../models/movement.dart';
import 'allowance_calculator.dart';

class ClaimPrintService {
  static const _fallbackName = 'claim';
  static const _perPage = 55;

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

  static Future<Uint8List> buildPdf(ClaimData data) async {
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: regular, bold: bold));
    final summary = AllowanceCalculator.computeSummary(data);
    final movements = AllowanceCalculator.movementsForMonth(data);

    final pages = <pw.Page>[];
    if (movements.isEmpty) {
      pages.add(_page(
          data: data,
          summary: summary,
          chunk: const [],
          showSummary: true));
    } else {
      for (var i = 0; i < movements.length; i += _perPage) {
        final chunk = movements.skip(i).take(_perPage).toList();
        final showSummary = i + _perPage >= movements.length;
        pages.add(_page(
            data: data,
            summary: summary,
            chunk: chunk,
            showSummary: showSummary));
      }
    }

    for (final page in pages) {
      doc.addPage(page);
    }
    return doc.save();
  }

  static pw.Page _page({
    required ClaimData data,
    required ClaimSummary summary,
    required List<Movement> chunk,
    required bool showSummary,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28.3, 22.7, 28.3, 22.7),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _printHeader(),
          _titleRow(data),
          _masterGrid(data),
          _movementTable(chunk, empty: chunk.isEmpty),
          if (showSummary) _summaryBox(data, summary),
        ],
      ),
    );
  }

  static String _d(String v) => v.trim().isEmpty ? '—' : v.trim();

  static String _monthLabel(String month) {
    final parsed = MasterData.parseMonthYear(month);
    if (parsed != null) return MasterData.monthLabel(parsed.$1, parsed.$2);
    return month.trim();
  }

  static pw.Widget _printHeader() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
      ),
      child: pw.Column(
        children: [
          pw.Text('SYAMA PRASAD MOOKERJEE PORT, KOLKATA',
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text('Haldia Dock Complex / Marine Office',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8.5)),
          pw.Text('Monthly Allowance Claim Register',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline)),
        ],
      ),
    );
  }

  static pw.Widget _titleRow(ClaimData data) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
      ),
      child: pw.Text(
        'Month: ${_monthLabel(data.master.month)}    Name: ${_d(data.master.name)}    '
        'Desg: ${_d(data.master.designation)}',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _masterGrid(ClaimData data) {
    final master = data.master;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _masterField('Designation', _d(master.designation)),
          _masterField('Employee / DPS ID', _d(master.employee)),
          _masterField(
              master.isBerthingPilot ? 'Consolidated Pay' : 'Basic Pay',
              _d(master.isBerthingPilot ? master.pay : master.basic)),
          _masterField('Bill Abstract No.', _d(master.bill)),
        ],
      ),
    );
  }

  static pw.Widget _masterField(String label, String value) {
    return pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _movementTable(List<Movement> chunk, {required bool empty}) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(48),
        1: pw.FlexColumnWidth(62),
        2: pw.FlexColumnWidth(48),
        3: pw.FlexColumnWidth(48),
        4: pw.FlexColumnWidth(36),
        5: pw.FlexColumnWidth(36),
        6: pw.FlexColumnWidth(28),
        7: pw.FlexColumnWidth(28),
      },
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        _tableHeader(['DATE', 'VESSEL', 'FROM BERTH', 'TO BERTH', 'START',
            'END', 'LOA', 'BEAM']),
        if (empty)
          _tableRow(const ['', '', '', '', '', '', '', ''])
        else
          for (final m in chunk)
            _tableRow([
              m.date,
              m.vessel,
              m.from,
              m.to,
              m.start,
              m.end,
              m.loa,
              m.beam,
            ]),
      ],
    );
  }

  static pw.TableRow _tableHeader(List<String> cells) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        for (final c in cells)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text(c,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 6, fontWeight: pw.FontWeight.bold)),
          ),
      ],
    );
  }

  static pw.TableRow _tableRow(List<String> cells) {
    return pw.TableRow(
      children: [
        for (final c in cells)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text(c,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6.5)),
          ),
      ],
    );
  }

  static pw.Widget _summaryBox(ClaimData data, ClaimSummary summary) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 5),
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        children: [
          pw.Text('Claim summary:',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          if (summary.lines.isEmpty)
            pw.Text('No payable claim rows yet.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7.5))
          else
            pw.Wrap(
              alignment: pw.WrapAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: [
                for (final line in summary.lines)
                  pw.Container(
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Text(
                        line.key == 'weightage' &&
                                summary.nightWeightageHours > 0
                            ? '${line.label}: ${_money.format(line.amount)} · '
                                '${summary.nightWeightageHours.toStringAsFixed(2)} hrs'
                            : '${line.label}: ${_money.format(line.amount)}',
                        style: const pw.TextStyle(fontSize: 7.5)),
                  ),
              ],
            ),
          if (summary.nightWeightageHours > 0 && !summary.hasWeightageAmount)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Text(
                    'Night Weightage: '
                    '${summary.nightWeightageHours.toStringAsFixed(2)} hrs',
                    style: const pw.TextStyle(fontSize: 7.5)),
              ),
            ),
          pw.SizedBox(height: 3),
          pw.Text('Grand total: ${_money.format(summary.grandTotal)}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          if (summary.payWarning)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                'Enter Consolidated Basic Pay to calculate Night Weightage.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.orange),
              ),
            ),
        ],
      ),
    );
  }
}
