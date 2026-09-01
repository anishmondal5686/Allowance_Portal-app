import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/claim_data.dart';
import '../models/master_data.dart';
import '../models/movement.dart';
import 'allowance_calculator.dart';

enum OfficialForm {
  lengthAndCold,
  lengthAllowance,
  nightActWeightage,
  lockToApproachJetty,
  lockToApproachJettyAdmDuty,
  nightNavigation,
  nightActWeightageAdmDuty,
  nightNavigationAdmDuty,
}

class _Fonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font devanagari;
  _Fonts(this.regular, this.bold, this.devanagari);
}

class _L {
  final String t;
  final double x;
  final double y;
  const _L(this.t, this.x, this.y);
}

class OfficialFormsService {
  static const _fallback = 'claim';
  static const _bw = 0.75;

  static Future<void> printForm(OfficialForm form, ClaimData data) async {
    final bytes = await buildFormPdf(form, data);
    final format =
        form == OfficialForm.nightNavigation && !data.master.isAdm
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4;
    await Printing.layoutPdf(
      name: pdfFileName(form, data.master.month),
      format: format,
      onLayout: (_) async => bytes,
    );
  }

  static String pdfFileName(OfficialForm form, String month) {
    final m = _clean(month);
    final base = switch (form) {
      OfficialForm.lengthAndCold => 'Length_Cold_Allowance',
      OfficialForm.lengthAllowance => 'Length_Allowance',
      OfficialForm.nightActWeightage => 'Night_Act_Weightage',
      OfficialForm.nightActWeightageAdmDuty => 'Night_Weightage_ADM_Duty',
      OfficialForm.lockToApproachJetty => 'Lock_to_App_Jetty',
      OfficialForm.lockToApproachJettyAdmDuty => 'Lock_to_App_Jetty_ADM_Duty',
      OfficialForm.nightNavigation => 'Night_Navigation',
      OfficialForm.nightNavigationAdmDuty => 'Night_Navigation_ADM_Duty',
    };
    return '${base}_$m.pdf';
  }

  static String _clean(String month) {
    final c = month
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return c.isEmpty ? _fallback : c;
  }

  /// Friendly month label with year, e.g. 'SEPTEMBER, 2026'.
  static String _monthLabel(String month) {
    final parsed = MasterData.parseMonthYear(month);
    if (parsed != null) return MasterData.monthLabel(parsed.$1, parsed.$2);
    return month.trim();
  }

  static _Fonts? _cachedFonts;

  static Future<_Fonts> _getFonts() async {
    if (_cachedFonts != null) return _cachedFonts!;
    _cachedFonts = _Fonts(
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansDevanagari.ttf')),
    );
    return _cachedFonts!;
  }

  static Future<Uint8List> buildFormPdf(OfficialForm form, ClaimData data) async {
    final fonts = await _getFonts();
    return switch (form) {
      OfficialForm.lengthAndCold => _buildLengthAndCold(data, fonts),
      OfficialForm.lengthAllowance => _buildLengthAllowance(data, fonts),
      OfficialForm.nightActWeightage => data.master.isAdm
          ? _buildNightWeightageAdm(data, fonts)
          : _buildNightActWeightage(data, fonts),
      OfficialForm.nightActWeightageAdmDuty =>
        _buildNightWeightageAdm(data, fonts),
      OfficialForm.lockToApproachJetty => _buildLock(data, fonts),
      OfficialForm.lockToApproachJettyAdmDuty =>
        _buildLock(data, fonts, admDuty: true),
      OfficialForm.nightNavigation => data.master.isAdm
          ? _buildAdmNightNavigation(data, fonts)
          : _buildNightNavigation(data, fonts),
      OfficialForm.nightNavigationAdmDuty =>
        _buildAdmNightNavigation(data, fonts),
    };
  }

  // ================================================================
  // Primitives — absolute position drawing on a margin-less page
  // ================================================================

  static pw.Widget _vLine(double x, double y0, double y1) => pw.Positioned(
        left: x,
        top: y0,
        child: pw.SizedBox(
          width: _bw,
          height: y1 - y0,
          child: pw.Container(color: PdfColors.black),
        ),
      );

  static pw.Widget _hLine(double x0, double x1, double y) => pw.Positioned(
        left: x0,
        top: y,
        child: pw.SizedBox(
          width: x1 - x0,
          height: _bw,
          child: pw.Container(color: PdfColors.black),
        ),
      );

  static pw.Widget _gray(double x, double y, double w, double h) =>
      pw.Positioned(
        left: x,
        top: y,
        child: pw.SizedBox(
          width: w,
          height: h,
          child: pw.Container(color: PdfColor.fromInt(0xFFF5F5F5)),
        ),
      );

  static pw.Widget _txt(_Fonts f, String s, double x, double y, double size,
      {bool bold = false, pw.Font? font}) {
    if (s.isEmpty) {
      return pw.Positioned(
          left: 0, top: 0, child: pw.SizedBox.shrink());
    }
    return pw.Positioned(
      left: x,
      top: y,
      child: pw.Text(s,
          style: pw.TextStyle(
              font: font ?? (bold ? f.bold : f.regular), fontSize: size)),
    );
  }

  /// Draws a uniform table grid. [merged] lists merged regions as
  /// (r1, r2, c1, c2) row/col index ranges whose interior lines are removed.
  static List<pw.Widget> _grid(List<double> ys, List<double> xs,
      {List<(int, int, int, int)> merged = const [],
      bool gray = false,
      int grayRows = 1}) {
    final out = <pw.Widget>[];
    if (gray) {
      for (var r = 0; r < grayRows && r < ys.length - 1; r++) {
        for (var c = 0; c < xs.length - 1; c++) {
          out.add(_gray(xs[c] + _bw, ys[r] + _bw,
              (xs[c + 1] - xs[c]) - 2 * _bw, (ys[r + 1] - ys[r]) - 2 * _bw));
        }
      }
    }
    for (var b = 0; b < ys.length; b++) {
      for (var c = 0; c < xs.length - 1; c++) {
        if (merged
            .any((m) => m.$1 < b && b <= m.$2 && m.$3 <= c && c <= m.$4)) {
          continue;
        }
        out.add(_hLine(xs[c], xs[c + 1], ys[b]));
      }
    }
    for (var b = 0; b < xs.length; b++) {
      for (var r = 0; r < ys.length - 1; r++) {
        if (merged
            .any((m) => m.$3 < b && b <= m.$4 && m.$1 <= r && r <= m.$2)) {
          continue;
        }
        out.add(_vLine(xs[b], ys[r], ys[r + 1]));
      }
    }
    return out;
  }

  static double _est(String s, double size, {bool bold = false}) {
    const f = 1.0;
    var w = 0.0;
    for (var i = 0; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      if (ch >= 48 && ch <= 57) {
        w += 0.555;
      } else if (ch >= 65 && ch <= 90) {
        w += 0.72;
      } else if (ch >= 97 && ch <= 122) {
        w += 0.52;
      } else if (ch == 32) {
        w += 0.3;
      } else if (ch == 46 || ch == 58 || ch == 47) {
        w += 0.28;
      } else if (ch == 44) {
        w += 0.28;
      } else if (ch == 45) {
        w += 0.5;
      } else if (ch == 40 || ch == 41) {
        w += 0.3;
      } else if (ch == 95) {
        w += 0.55;
      } else {
        w += 0.55;
      }
    }
    return w * size * (bold ? f : 1.0);
  }

  /// Left coordinate that horizontally centers [s] inside [x0, x1].
  static double _cx(List<double> cell, String s, double size,
      {bool bold = false}) {
    return (cell[0] + cell[1]) / 2 - _est(s, size, bold: bold) / 2;
  }

  /// Vertically centered text for a table data cell.
  static pw.Widget _cell(_Fonts f, String s, List<double> cell, double y,
      double size, {bool bold = false}) {
    if (s.isEmpty) {
      return pw.Positioned(
          left: 0, top: 0, child: pw.SizedBox.shrink());
    }
    return _txt(f, s, _cx(cell, s, size, bold: bold), y, size, bold: bold);
  }

  static pw.Widget _page(List<pw.Widget> children) =>
      pw.Stack(children: children);

  // ================================================================
  // 1. LENGTH & COLD MOVEMENT ALLOWANCES (A4 portrait)
  // ================================================================

  static const _lcCols = [
    [45.0, 70.5],
    [70.5, 131.2],
    [131.2, 207.0],
    [207.0, 387.8],
    [387.8, 448.5],
    [448.5, 498.8],
    [498.8, 549.8],
  ];
  /// For the ADM-duty forms: a BP/DP claiming under acting ADM shows
  /// designation "Acting ADM"; a real ADM keeps their own.
  static String _admDutyDsgn(MasterData m) =>
      m.isAdm ? m.designation : 'Acting ADM';

  /// Signed role for the bottom-right signature block, derived from the
  /// claim's designation. ADM signs as Asst. Dock Master; otherwise the
  /// exact pilot designation is shown.
  static String _signatureRole(MasterData m) {
    if (m.isAdm) return 'Asst. Dock Master';
    if (m.isBerthingPilot) return 'Berthing Pilot';
    return 'Dock Pilot';
  }

  /// Bottom-right signature label. ADM (or ADM-duty) forms sign as the
  /// Assistant Dock Master; ordinary pilot forms keep "Signature of the".
  static String _signatureLabel(bool admDuty) =>
      admDuty ? 'Signature of ADM' : 'Signature of the';

  static const _lcXs = [45.0, 70.5, 131.2, 207.0, 387.8, 448.5, 498.8, 549.8];
  static const _lcRows = [
    159.8, 176.2, 193.5, 210.8, 228.0, 245.2, 262.5, 279.8, 297.0, 314.2,
    331.5, 348.8, 366.0, 383.2, 400.5, 417.8, 435.0, 452.2, 469.5, 486.8,
    504.0, 521.2,
  ];
  static const _coldRows = [541.5, 558.0, 575.2, 592.5, 609.8, 627.0, 644.2];
  static const _lcHeaderLabels = [
    _L('SL.', 52.0, 164.6),
    _L('DATE', 90.4, 164.6),
    _L('START / END', 143.9, 164.6),
    _L('NAME OF VESSELS', 259.2, 164.6),
    _L('LENGTH (M)', 394.8, 164.6),
    _L('FROM', 462.3, 164.6),
    _L('TO', 519.0, 164.6),
  ];
  static const _coldHeaderLabels = [
    _L('SL.', 52.0, 546.4),
    _L('DATE', 90.4, 546.4),
    _L('START / END', 143.9, 546.4),
    _L('NAME OF VESSELS', 259.2, 546.4),
    _L('LENGTH', 402.1, 546.4),
    _L('FROM', 462.3, 546.4),
    _L('TO', 519.0, 546.4),
  ];

  static Future<Uint8List> _buildLengthAndCold(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    final moves = AllowanceCalculator.movementsForMonth(data);
    final length = moves
        .where((m) =>
            m.hasAllowance('length') &&
            (double.tryParse(m.loa) ?? 0) >= 175.26 &&
            !acting.contains(AllowanceCalculator.normDateKey(m.date)))
        .toList();
    final cold = moves
        .where((m) =>
            m.hasAllowance('cold') &&
            !acting.contains(AllowanceCalculator.normDateKey(m.date)))
        .toList();
    final pages = math.max(
        1,
        math.max((length.length / 20).ceil(), (cold.length / 5).ceil()));
    final m = data.master;
    for (var p = 0; p < pages; p++) {
      final lChunk = length.skip(p * 20).take(20).toList();
      final cChunk = cold.skip(p * 5).take(5).toList();
      final w = <pw.Widget>[];
      w.add(_txt(f, 'HALDIA DOCK COMPLEX', 200.7, 33.7, 15.0, bold: true));
      w.add(_txt(f, 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA', 145.1, 53.0, 12.75,
          bold: true));
      w.add(_txt(f, 'MARINE OFFICE', 259.3, 70.7, 9.75, bold: true));
      w.add(_txt(
          f,
          'Claim form for the Payment of Length and Cold Movement Allowances',
          141.1,
          86.0,
          9.38,
          bold: true));
      w.add(_txt(f, 'Month:', 45.4, 108.0, 8.25, bold: true));
      w.add(_txt(f, _monthLabel(m.month), 77.2, 108.0, 9.5, bold: true));
      w.add(_txt(f, 'Name:', 217.6, 106.0, 8.25, bold: true));
      w.add(_txt(f, m.name, 247.5, 106.0, 9.5, bold: true));
      w.add(_txt(f, 'Dsgn.:', 389.9, 106.0, 8.25, bold: true));
      w.add(_txt(f, m.designation, 420.0, 106.0, 9.5, bold: true));
      w.add(_txt(
          f,
          m.isBerthingPilot ? 'Consolidated Pay:' : 'Pay Rs.:',
          45.4,
          129.0,
          8.25,
          bold: true));
      w.add(_txt(f, m.payLine, 121.5, 129.0, 9.5, bold: true));
      w.add(_txt(f, 'Bill Abst no:', 217.6, 127.0, 8.25, bold: true));
      w.add(_txt(f, m.bill, 270.7, 127.0, 9.5, bold: true));
      w.add(_txt(f, 'Emp I.D:', 389.9, 127.0, 8.25, bold: true));
      w.add(_txt(f, m.employee, 427.5, 127.0, 9.5, bold: true));
      w.add(_txt(
          f,
          '(1) LENGTH ALLOWANCE ( Code - 077 )'
          '  ( Minimum length - 175.26 meters ) ( Rs. 310.00 per act. )',
          121.7,
          147.4,
          8.62,
          bold: true));
      w.addAll(_grid(_lcRows, _lcXs, gray: true, grayRows: 1));
      for (final l in _lcHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.88, bold: true));
      }
      for (var i = 0; i < 20; i++) {
        final mv = i < lChunk.length ? lChunk[i] : null;
        final y = 180.8 + i * 17.25;
        w.add(_cell(f, mv == null ? '' : '${p * 20 + i + 1}', _lcCols[0], y, 8.25));
        w.add(_cell(f, mv?.date ?? '', _lcCols[1], y, 8.25));
        w.add(_cell(f, mv == null ? '' : _startEnd(mv), _lcCols[2], y, 8.25));
        w.add(_cell(f, mv?.vessel ?? '', _lcCols[3], y, 8.25));
        w.add(_cell(f, mv?.loa ?? '', _lcCols[4], y, 8.25));
        w.add(_cell(f, mv?.from ?? '', _lcCols[5], y, 8.25));
        w.add(_cell(f, mv?.to ?? '', _lcCols[6], y, 8.25));
      }
      w.add(_txt(
          f,
          '(2) COLD MOVEMENT ALLOWANCE ( Code - 072 ) ( Rs. 160.00 per act. )',
          160.5,
          529.2,
          8.62,
          bold: true));
      w.addAll(_grid(_coldRows, _lcXs, gray: true, grayRows: 1));
      for (final l in _coldHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.88, bold: true));
      }
      for (var i = 0; i < 5; i++) {
        final mv = i < cChunk.length ? cChunk[i] : null;
        final y = 562.5 + i * 17.25;
        w.add(_cell(f, mv == null ? '' : '${p * 5 + i + 1}', _lcCols[0], y, 8.25));
        w.add(_cell(f, mv?.date ?? '', _lcCols[1], y, 8.25));
        w.add(_cell(f, mv == null ? '' : _startEnd(mv), _lcCols[2], y, 8.25));
        w.add(_cell(f, mv?.vessel ?? '', _lcCols[3], y, 8.25));
        w.add(_cell(f, mv?.loa ?? '', _lcCols[4], y, 8.25));
        w.add(_cell(f, mv?.from ?? '', _lcCols[5], y, 8.25));
        w.add(_cell(f, mv?.to ?? '', _lcCols[6], y, 8.25));
      }
      w.add(_txt(f, 'The Manager (P&IR)', 45.4, 670.1, 7.88));
      w.add(_txt(f, 'Haldia Dock Complex', 45.4, 681.4, 7.88));
      w.add(
          _txt(f, 'Forwarded for necessary action at the earliest.', 45.4, 691.9, 7.88));
      w.add(_cell(f, 'The Manager, Marine', [380.0, 550.2], 670.1, 7.88,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct', [380.0, 550.2],
          681.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Manager', [45.0, 210.0], 733.9, 7.88, bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [45.0, 210.0], 744.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [45.0, 210.0], 754.9, 7.88,
          bold: true));
      w.add(_cell(f, 'Asstt. Dock Master', [210.0, 380.0], 733.9, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [210.0, 380.0], 744.4, 7.88,
          bold: true));
      w.add(_cell(f, _signatureLabel(m.isAdm), [380.0, 550.2], 733.9, 7.88,
          bold: true));
      w.add(_cell(f, _signatureRole(m), [380.0, 550.2], 744.4, 7.88,
          bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  // ================================================================
  // 1b. LENGTH ALLOWANCE ONLY — ADM variant (no Cold table)
  // ================================================================
  static Future<Uint8List> _buildLengthAllowance(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    final moves = AllowanceCalculator.movementsForMonth(data);
    // Real ADM → every length movement; BP/DP → acting-ADM-date lengths only
    // (same pattern as the ADM-duty night forms).
    final length = moves
        .where((m) =>
            m.hasAllowance('length') &&
            (double.tryParse(m.loa) ?? 0) >= 175.26 &&
            (data.master.isAdm ||
                acting.contains(AllowanceCalculator.movementShiftDate(m))))
        .toList();
    final pages = math.max(1, (length.length / 20).ceil());
    final m = data.master;
    for (var p = 0; p < pages; p++) {
      final chunk = length.skip(p * 20).take(20).toList();
      final w = <pw.Widget>[];
      w.add(_txt(f, 'HALDIA DOCK COMPLEX', 200.7, 33.7, 15.0, bold: true));
      w.add(_txt(f, 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA', 145.1, 53.0, 12.75,
          bold: true));
      w.add(_txt(f, 'MARINE OFFICE', 259.3, 70.7, 9.75, bold: true));
      w.add(_txt(
          f,
          'Claim form for the Payment of Length Allowance',
          155.0,
          86.0,
          10.0,
          bold: true));
      w.add(_txt(f, 'Month:', 45.4, 108.0, 8.25, bold: true));
      w.add(_txt(f, _monthLabel(m.month), 77.2, 108.0, 9.5, bold: true));
      w.add(_txt(f, 'Name:', 217.6, 106.0, 8.25, bold: true));
      w.add(_txt(f, m.name, 247.5, 106.0, 9.5, bold: true));
      w.add(_txt(f, 'Dsgn.:', 389.9, 106.0, 8.25, bold: true));
      w.add(_txt(f, _admDutyDsgn(m), 420.0, 106.0, 9.5, bold: true));
      w.add(_txt(
          f,
          m.isBerthingPilot ? 'Consolidated Pay:' : 'Pay Rs.:',
          45.4,
          129.0,
          8.25,
          bold: true));
      w.add(_txt(f, m.payLine, 121.5, 129.0, 9.5, bold: true));
      w.add(_txt(f, 'Bill Abst no:', 217.6, 127.0, 8.25, bold: true));
      w.add(_txt(f, m.bill, 270.7, 127.0, 9.5, bold: true));
      w.add(_txt(f, 'Emp I.D:', 389.9, 127.0, 8.25, bold: true));
      w.add(_txt(f, m.employee, 427.5, 127.0, 9.5, bold: true));
      w.add(_txt(
          f,
          '(1) LENGTH ALLOWANCE ( Code - 077 )'
          '  ( Minimum length - 175.26 meters ) ( Rs. 310.00 per act. )',
          121.7,
          147.4,
          8.62,
          bold: true));
      w.addAll(_grid(_lcRows, _lcXs, gray: true, grayRows: 1));
      for (final l in _lcHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.88, bold: true));
      }
      for (var i = 0; i < 20; i++) {
        final mv = i < chunk.length ? chunk[i] : null;
        final y = 180.8 + i * 17.25;
        w.add(_cell(f, mv == null ? '' : '${p * 20 + i + 1}', _lcCols[0], y, 8.25));
        w.add(_cell(f, mv?.date ?? '', _lcCols[1], y, 8.25));
        w.add(_cell(f, mv == null ? '' : _startEnd(mv), _lcCols[2], y, 8.25));
        w.add(_cell(f, mv?.vessel ?? '', _lcCols[3], y, 8.25));
        w.add(_cell(f, mv?.loa ?? '', _lcCols[4], y, 8.25));
        w.add(_cell(f, mv?.from ?? '', _lcCols[5], y, 8.25));
        w.add(_cell(f, mv?.to ?? '', _lcCols[6], y, 8.25));
      }
      // Footer kept at its original position (no Cold table above it).
      w.add(_txt(f, 'The Manager (P&IR)', 45.4, 670.1, 7.88));
      w.add(_txt(f, 'Haldia Dock Complex', 45.4, 681.4, 7.88));
      w.add(
          _txt(f, 'Forwarded for necessary action at the earliest.', 45.4, 691.9, 7.88));
      w.add(_cell(f, 'The Manager, Marine', [380.0, 550.2], 670.1, 7.88,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct', [380.0, 550.2],
          681.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Manager', [45.0, 210.0], 733.9, 7.88, bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [45.0, 210.0], 744.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [45.0, 210.0], 754.9, 7.88,
          bold: true));
      w.add(_cell(f, 'Asstt. Dock Master', [210.0, 380.0], 733.9, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [210.0, 380.0], 744.4, 7.88,
          bold: true));
      w.add(_cell(f, _signatureLabel(m.isAdm), [380.0, 550.2], 733.9, 7.88,
          bold: true));
      w.add(_cell(f, _signatureRole(m), [380.0, 550.2], 744.4, 7.88,
          bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  static String _startEnd(Movement m) {
    if (m.start.isNotEmpty && m.end.isNotEmpty) return '${m.start} / ${m.end}';
    return m.start.isNotEmpty ? m.start : m.end;
  }

  // ================================================================
  // 2. NIGHT ACT & NIGHT WEIGHTAGE ALLOWANCES (A4 portrait)
  // ================================================================

  static const _naCols = [
    [22.5, 50.2],
    [50.2, 116.2],
    [116.2, 198.8],
    [198.8, 396.0],
    [396.0, 462.0],
    [462.0, 517.5],
    [517.5, 572.2],
  ];
  static const _naXs = [22.5, 50.2, 116.2, 198.8, 396.0, 462.0, 517.5, 572.2];
  static const _naRows = [
    158.2, 175.5, 192.8, 210.0, 227.2, 244.5, 261.8, 279.0, 296.2, 313.5,
    330.8, 348.0,
  ];
  static const _naHeaderLabels = [
    _L('SL.', 30.9, 159.0),
    _L('NO.', 30.1, 167.2),
    _L('DATE', 73.5, 163.5),
    _L('START / END', 134.4, 163.5),
    _L('NAME OF VESSELS', 262.1, 163.5),
    _L('LENGTH (M)', 407.5, 163.5),
    _L('FROM', 479.0, 163.5),
    _L('TO', 539.8, 163.5),
  ];
  static const _nwCols = [
    [22.5, 55.5],
    [55.5, 143.2],
    [143.2, 209.2],
    [209.2, 330.0],
    [330.0, 451.5],
    [451.5, 572.2],
  ];
  static const _nwXs = [22.5, 55.5, 143.2, 209.2, 330.0, 451.5, 572.2];
  static const _nwRows = [
    374.2, 390.0, 407.2, 424.5, 441.8, 459.0, 476.2, 493.5, 510.8, 528.0,
    545.2, 562.5, 579.8, 597.0, 614.2, 631.5, 648.8,
  ];
  static const _nwHeaderLabels = [
    _L('SL. NO.', 26.0, 378.7),
    _L('DATE', 90.0, 378.7),
    _L('WATCH', 163.4, 378.7),
    _L('FROM', 259.2, 378.7),
    _L('TO', 386.0, 378.7),
    _L('TIME', 503.0, 378.7),
  ];

  static Future<Uint8List> _buildNightActWeightage(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    final acts = AllowanceCalculator.movementsForMonth(data)
        .where((m) =>
            m.hasAllowance('nightact') &&
            !acting.contains(AllowanceCalculator.movementShiftDate(m)))
        .toList();
    final gaps = _nightWeightageGaps(data);
    final pages = math.max(
        1,
        math.max((acts.length / 10).ceil(), (gaps.length / 15).ceil()));
    final m = data.master;
    for (var p = 0; p < pages; p++) {
      final aChunk = acts.skip(p * 10).take(10).toList();
      final gChunk = gaps.skip(p * 15).take(15).toList();
      final totalMins = gChunk.fold<int>(0, (s, g) => s + (g.e - g.s));
      final w = <pw.Widget>[];
      w.add(_txt(f, 'स्यामा प्रसाद मुखर्जी, कोलकाता', 225.2, 22.4, 11.25,
          font: f.devanagari));
      w.add(_txt(f, 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA', 153.6, 38.6, 12.0,
          bold: true));
      w.add(_txt(f, 'हल्दिया गोदी परिसर / HALDIA DOCK COMPLEX', 185.6, 54.7,
          10.5,
          font: f.devanagari));
      w.add(_txt(f, 'MARINE OFFICE', 262.2, 71.4, 9.0, bold: true));
      w.add(_txt(
          f,
          'Claim form for the Payment of Night Act Allowance and '
          'Night Weightage Allowance',
          112.4,
          86.0,
          9.38,
          bold: true));
      w.add(_txt(f, 'For the Month of:', 22.7, 108.0, 8.25, bold: true));
      w.add(_txt(f, _monthLabel(m.month), 95.2, 108.0, 9.5, bold: true));
      w.add(_txt(f, 'Name:', 209.6, 108.0, 8.25, bold: true));
      w.add(_txt(f, m.name, 239.2, 108.0, 9.5, bold: true));
      w.add(_txt(f, 'Designation:', 396.4, 108.0, 8.25, bold: true));
      w.add(_txt(f, m.designation, 450.8, 108.0, 9.5, bold: true));
      w.add(_txt(
          f,
          m.isBerthingPilot ? 'Consolidated Pay Rs.:' : 'Pay Rs.:',
          22.7,
          129.0,
          8.25,
          bold: true));
      w.add(_txt(f, m.payLine, 114.0, 129.0, 9.5, bold: true));
      w.add(_txt(f, 'Bill Abst. No.:', 209.6, 129.0, 8.25, bold: true));
      w.add(_txt(f, m.bill, 267.7, 129.0, 9.5, bold: true));
      w.add(_txt(f, 'Emp I.D :', 396.4, 129.0, 8.25, bold: true));
      w.add(_txt(f, m.employee, 436.5, 129.0, 9.5, bold: true));
      w.add(_txt(f, '(1) NIGHT ACT ALLOWANCE (Code - 082)', 213.3, 145.9, 8.62,
          bold: true));
      w.addAll(_grid(_naRows, _naXs, gray: true, grayRows: 1));
      for (final l in _naHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.5, bold: true));
      }
      for (var i = 0; i < 10; i++) {
        final mv = i < aChunk.length ? aChunk[i] : null;
        final y = 180.4 + i * 17.3;
        w.add(_cell(f, mv == null ? '' : '${p * 10 + i + 1}', _naCols[0], y, 7.88));
        w.add(_cell(f, mv?.date ?? '', _naCols[1], y, 7.88));
        w.add(_cell(f, mv == null ? '' : _startEnd(mv), _naCols[2], y, 7.88));
        w.add(_cell(f, mv?.vessel ?? '', _naCols[3], y, 7.88));
        w.add(_cell(f, mv?.loa ?? '', _naCols[4], y, 7.88));
        w.add(_cell(f, mv?.from ?? '', _naCols[5], y, 7.88));
        w.add(_cell(f, mv?.to ?? '', _naCols[6], y, 7.88));
      }
      w.add(_txt(f, '(2) NIGHT WEIGHTAGE ALLOWANCE (CODE \u2013 023)', 195.7, 352.9,
          8.62,
          bold: true));
      w.add(_txt(f, '(minutes app. per hour from 2200 hrs. to 0600 hrs.)',
          216.9, 363.3, 7.12));
      w.addAll(_grid(_nwRows, _nwXs, gray: true, grayRows: 1));
      for (final l in _nwHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.5, bold: true));
      }
      for (var i = 0; i < 15; i++) {
        final g = i < gChunk.length ? gChunk[i] : null;
        final y = 394.9 + i * 17.2;
        final by = 394.5 + i * 17.2;
        w.add(_cell(f, g == null ? '' : '${p * 15 + i + 1}', _nwCols[0], y, 7.88));
        w.add(_cell(f, g?.date ?? '', _nwCols[1], y, 7.88));
        w.add(_cell(
            f, g == null ? '' : 'NIGHT', _nwCols[2], by, 8.25, bold: true));
        w.add(_cell(f, g == null ? '' : _nwTimeText(g.s, g.date), _nwCols[3], y,
            7.88));
        w.add(_cell(f, g == null ? '' : _nwTimeText(g.e, g.date), _nwCols[4], y,
            7.88));
        w.add(_cell(f, g == null ? '' : _durText(g.e - g.s), _nwCols[5], by,
            8.25,
            bold: true));
      }
      w.add(_txt(f, 'Total Time', 445.9, 657.8, 8.25, bold: true));
      w.add(_txt(
          f,
          totalMins == 0 ? '' : (totalMins / 60).toStringAsFixed(2),
          _cx([498.0, 554.0], totalMins == 0 ? '' : (totalMins / 60).toStringAsFixed(2), 8.25,
              bold: true),
          657.8,
          8.25,
          bold: true));
      w.add(_txt(f, 'hrs.', 554.7, 657.8, 8.25, bold: true));
      w.add(_txt(f, 'The Manager, (P&IR) Haldia Dock Complex', 22.7, 728.6, 7.88));
      w.add(_txt(f, 'Forwarded for necessary action at the earliest', 22.7,
          739.1, 7.88));
      w.add(_cell(f, 'The Manager (M.O.), HDC', [390.0, 572.7], 728.6, 7.88,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct', [390.0, 572.7],
          739.1, 7.88,
          bold: true));
      w.add(_cell(f, 'Manager', [22.7, 200.0], 786.4, 7.88, bold: true));
      w.add(_cell(f, 'Marine Ops. Division', [22.7, 200.0], 796.5, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [22.7, 200.0], 806.6, 7.88,
          bold: true));
      w.add(_cell(f, 'Deputy Dock Master,', [200.0, 325.0], 786.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Marine Ops. Division', [200.0, 325.0], 796.5, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [200.0, 325.0], 806.6, 7.88,
          bold: true));
      w.add(_cell(f, 'Asst. Dock Master', [325.0, 450.0], 786.4, 7.88,
          bold: true));
      w.add(_cell(f, 'Marine Ops. Division', [325.0, 450.0], 796.5, 7.88,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [325.0, 450.0], 806.6, 7.88,
          bold: true));
      final sigLine1 = _signatureLabel(data.master.isAdm);
      final sigLine2 = _signatureRole(data.master);
      w.add(_cell(f, sigLine1, [450.0, 572.7], 786.4, 7.88, bold: true));
      w.add(_cell(f, sigLine2, [450.0, 572.7], 796.5, 7.88, bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  // ================================================================
  // NIGHT WEIGHTAGE (ADM standalone form per "ADM ALLOWANCE NEW FORM"
  // docx): "Claim form for the payment for Night Weightage Allowances"
  // with Basic/ADA fields and a 10-row table. Used when isAdm.
  // ================================================================

  static const _nwAdmRows = [
    218.0, 236.0, 253.4, 270.8, 288.2, 305.6, 323.0, 340.4, 357.8, 375.2,
    392.6,
  ];

  static Future<Uint8List> _buildNightWeightageAdm(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final gaps = _nightWeightageGaps(data, admDuty: true);
    final pages = math.max(1, (gaps.length / 10).ceil());
    final m = data.master;
    for (var p = 0; p < pages; p++) {
      final gChunk = gaps.skip(p * 10).take(10).toList();
      final totalMins = gChunk.fold<int>(0, (s, g) => s + (g.e - g.s));
      final totalHrs = totalMins == 0 ? '' : (totalMins / 60).toStringAsFixed(2);
      final days = totalMins == 0 ? '' : (totalMins / 60 / 48).toStringAsFixed(2);
      final w = <pw.Widget>[];
      w.add(_txt(f, 'स्यामा प्रसाद मुखर्जी, कोलकाता', 225.2, 22.4, 11.25,
          font: f.devanagari));
      w.add(_txt(f, 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA', 153.6, 38.6, 12.0,
          bold: true));
      w.add(_txt(f, 'हल्दिया गोदी परिसर / HALDIA DOCK COMPLEX', 185.6, 54.7,
          10.5,
          font: f.devanagari));
      w.add(_txt(f, 'MARINE OFFICE HALDIA', 262.2, 71.4, 9.0, bold: true));
      w.add(_txt(
          f,
          'Claim form for the payment for Night Weightage Allowances',
          112.4,
          88.0,
          9.38,
          bold: true));
      w.add(_txt(f, 'For the Month of:', 22.7, 110.0, 8.25, bold: true));
      w.add(_txt(f, _monthLabel(m.month), 95.2, 110.0, 9.5, bold: true));
      w.add(_txt(f, 'Name :', 22.7, 132.0, 8.25, bold: true));
      w.add(_txt(f, m.name, 58.0, 132.0, 9.5, bold: true));
      w.add(_txt(f, 'Designation :', 311.2, 132.0, 8.25, bold: true));
      w.add(_txt(f, _admDutyDsgn(m), 385.0, 132.0, 9.5, bold: true));
      w.add(_txt(f, 'Bill abst. :', 22.7, 153.0, 8.25, bold: true));
      w.add(_txt(f, m.bill, 78.0, 153.0, 9.5, bold: true));
      w.add(_txt(f, 'DPS No.', 311.2, 153.0, 8.25, bold: true));
      w.add(_txt(f, m.employee, 365.0, 153.0, 9.5, bold: true));
      if (m.isAdm) {
        w.add(_txt(f, 'Basic \u2013 Rs.', 22.7, 174.0, 8.25, bold: true));
        w.add(_txt(f, '${m.basic}/-', 90.0, 174.0, 9.5, bold: true));
        w.add(_txt(f, 'ADA \u2013 Rs.', 311.2, 174.0, 8.25, bold: true));
        w.add(_txt(f, '${m.ada}/-', 385.0, 174.0, 9.5, bold: true));
      } else {
        w.add(_txt(
            f, 'Consolidated Pay \u2013 Rs.', 22.7, 174.0, 8.25, bold: true));
        w.add(_txt(f, '${m.pay}/-', 140.0, 174.0, 9.5, bold: true));
      }
      const nwTitle = 'NIGHT WEIGHTAGE ALLOWANCE ( CODE \u2013 023 )';
      w.add(_txt(
          f,
          nwTitle,
          _cx([22.5, 572.2], nwTitle, 8.62, bold: true),
          200.0,
          8.62,
          bold: true));
      w.addAll(_grid(_nwAdmRows, _nwXs, gray: true, grayRows: 1));
      const hl = [
        _L('SL. NO.', 26.0, 224),
        _L('DATE', 90.0, 224),
        _L('WATCH', 163.4, 224),
        _L('FROM', 259.2, 224),
        _L('TO', 386.0, 224),
        _L('TIME', 503.0, 224),
      ];
      for (final l in hl) {
        w.add(_txt(f, l.t, l.x, l.y, 7.5, bold: true));
      }
      for (var i = 0; i < 10; i++) {
        final g = i < gChunk.length ? gChunk[i] : null;
        final y = 236.0 + i * 17.4;
        w.add(_cell(f, g == null ? '' : '${p * 10 + i + 1}', _nwCols[0], y, 7.88));
        w.add(_cell(f, g?.date ?? '', _nwCols[1], y, 7.88));
        w.add(
            _cell(f, g == null ? '' : 'NIGHT', _nwCols[2], y, 8.25, bold: true));
        w.add(_cell(f, g == null ? '' : _nwTimeText(g.s, g.date), _nwCols[3], y,
            7.88));
        w.add(_cell(f, g == null ? '' : _nwTimeText(g.e, g.date), _nwCols[4], y,
            7.88));
        w.add(_cell(f, g == null ? '' : _durText(g.e - g.s), _nwCols[5], y,
            8.25,
            bold: true));
      }
      w.add(_txt(f, 'Total Time', 445.9, 412.0, 8.25, bold: true));
      w.add(_txt(
          f,
          totalHrs,
          _cx([498.0, 554.0], totalHrs, 8.25, bold: true),
          412.0,
          8.25,
          bold: true));
      w.add(_txt(f, 'hrs.', 554.7, 412.0, 8.25, bold: true));
      w.add(_txt(
          f, 'Time for Night weightage : $totalHrs Hours / 48 = $days Days.',
          22.7, 428.0, 8.25));
      w.add(_txt(f, 'The Manager ( P & IR )', 22.7, 690.0, 8.25));
      w.add(_txt(f, 'Forwarded for necessary action.', 22.7, 704.0, 8.25));
      w.add(_cell(f, 'The Manager (M.O.), HDC', [390.0, 572.7], 690.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct', [390.0, 572.7],
          704.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Manager', [22.7, 200.0], 775.0, 8.25, bold: true));
      w.add(_cell(f, 'Marine Ops. Division', [22.7, 200.0], 789.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [22.7, 200.0], 803.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Deputy Dock Master', [200.0, 390.0], 775.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [200.0, 390.0], 789.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Signature of ADM', [390.0, 572.7], 775.0, 8.25,
          bold: true));
      w.add(_cell(f, 'Asst. Dock Master', [390.0, 572.7], 789.0, 8.25,
          bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  /// True when [dk] (`yyyy-M-d` key) belongs to a future month after the current month.
  static bool _isFutureKey(String dk) {
    final p = dk.split('-');
    if (p.length != 3) return false;
    final y = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    if (y == 0 || m == 0) return false;
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final dtMonthStart = DateTime(y, m, 1);
    return dtMonthStart.isAfter(currentMonthStart);
  }

  /// Normalized date keys for dates the person acted as ADM.
  static Set<String> _actingDateKeys(ClaimData data) {
    final s = <String>{};
    for (final d in data.actingAdmDates) {
      final k = AllowanceCalculator.normDateKey(d);
      if (k.isNotEmpty) s.add(k);
    }
    return s;
  }

  /// Night Weightage gaps — ported exactly from the webapp form.
  /// With [admDuty] true, produces the ADM standalone form rows: a full
  /// 8-hr watch for every ADM-duty night (all N nights for a real ADM,
  /// otherwise only the Acting ADM dates). Otherwise produces the person's
  /// own form rows: gap-based time for their own nights (excluding dates
  /// performed as ADM).
  static List<({String date, int s, int e})> _nightWeightageGaps(ClaimData data,
      {bool admDuty = false}) {
    const ns = 22 * 60;
    const ne = 6 * 60 + 24 * 60;

    int? timeToAbs(String t) {
      if (t.trim().isEmpty) return null;
      final clean = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.isEmpty) return null;
      int hrs, mins;
      if (clean.length <= 2) {
        hrs = int.parse(clean);
        mins = 0;
      } else if (clean.length == 3) {
        hrs = int.parse(clean[0]);
        mins = int.parse(clean.substring(1));
      } else {
        hrs = int.parse(clean.substring(0, 2));
        mins = int.parse(clean.substring(2, 4));
      }
      if (hrs > 24 || mins >= 60) return null;
      return hrs * 60 + mins;
    }

    int? parseTm(String t) {
      final c = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (c.isEmpty) return null;
      final padded =
          c.substring(0, math.min(4, c.length)).padLeft(4, '0');
      final h = int.parse(padded.substring(0, 2));
      final m = int.parse(padded.substring(2, 4));
      if (h > 24 || m >= 60) return null;
      return h * 60 + m;
    }

    final monthMoves = AllowanceCalculator.movementsForMonth(data);
    final monthShifts = AllowanceCalculator.effectiveAttShifts(data);
    final shiftMoves = <String, List<Movement>>{};
    for (final mv in monthMoves) {
      if ((!mv.hasAllowance('nightact') && !mv.hasAllowance('lock')) ||
          mv.date.trim().isEmpty ||
          mv.start.trim().isEmpty) {
        continue;
      }
      final dk = AllowanceCalculator.normDateKey(mv.date);
      final sMin = parseTm(mv.start);
      final att = monthShifts[dk];
      String shiftKey;
      if (sMin == null) {
        shiftKey = dk;
      } else if (sMin < 330) {
        shiftKey = AllowanceCalculator.prevDateKey(dk);
      } else if (sMin < 360) {
        if (att == 'M' || att == 'E') continue;
        shiftKey = AllowanceCalculator.prevDateKey(dk);
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
      shiftMoves.putIfAbsent(shiftKey, () => []).add(mv);
    }
    final attNDates = <String>{};
    monthShifts.forEach((dateKey, shift) {
      if (shift != 'N') return;
      final dk = AllowanceCalculator.normDateKey(dateKey);
      if (dk.isEmpty || _isFutureKey(dk)) return;
      attNDates.add(dk);
      shiftMoves.putIfAbsent(dk, () => []);
    });

    // ADM rule: a night shift earns the full 8 hrs as night weightage time
    // regardless of movements (movement allowances are claimed separately).
    if (admDuty) {
      final acting = _actingDateKeys(data);
      final dutyDates = data.master.isAdm
          ? attNDates
          : attNDates.where(acting.contains).toSet();
      final fullNights = <({String date, int s, int e})>[];
      for (final dk in dutyDates) {
        final parts = dk.split('-');
        final displayDate =
            '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}'
            '/${parts[0].substring(2)}';
        fullNights.add((date: displayDate, s: ns, e: ne));
      }
      return fullNights;
    }

    final acting = _actingDateKeys(data);
    final ownNDates = data.master.isAdm
        ? attNDates
        : attNDates.where((d) => !acting.contains(d)).toSet();
    final allGaps = <({String date, int s, int e})>[];
    for (final shiftKey in shiftMoves.keys) {
      if (!ownNDates.contains(shiftKey)) continue;
      final shiftActs = shiftMoves[shiftKey]!
          .where((mv) => mv.start.trim().isNotEmpty && mv.end.trim().isNotEmpty)
          .toList();
      final parts = shiftKey.split('-');
      final displayDate = '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}'
          '/${parts[0].substring(2)}';
      if (shiftActs.isEmpty) {
        allGaps.add((date: displayDate, s: ns, e: ne));
        continue;
      }
      final parsed = <({int s, int e})>[];
      for (final mv in shiftActs) {
        var s = timeToAbs(mv.start);
        var e = timeToAbs(mv.end);
        if (s == null || e == null) continue;
        if (s < 6 * 60) s += 24 * 60;
        if (e < 6 * 60) e += 24 * 60;
        if (e < s) e += 24 * 60;
        s = math.max(ns, s);
        e = math.min(ne, e);
        if (s < e) parsed.add((s: s, e: e));
      }
      parsed.sort((a, b) => a.s - b.s);
      var lastEnd = ns;
      for (final mv in parsed) {
        if (mv.s > lastEnd) {
          allGaps.add((date: displayDate, s: lastEnd, e: mv.s));
        }
        lastEnd = math.max(lastEnd, mv.e);
      }
      if (lastEnd < ne) {
        allGaps.add((date: displayDate, s: lastEnd, e: ne));
      }
    }
    allGaps.sort((a, b) {
      final pa = a.date.split(RegExp(r'[\/.\-]'));
      final pb = b.date.split(RegExp(r'[\/.\-]'));
      final ya = pa[2].length == 2 ? 2000 + int.parse(pa[2]) : int.parse(pa[2]);
      final yb = pb[2].length == 2 ? 2000 + int.parse(pb[2]) : int.parse(pb[2]);
      final da = DateTime(ya, int.parse(pa[1]), int.parse(pa[0])).millisecondsSinceEpoch;
      final db = DateTime(yb, int.parse(pb[1]), int.parse(pb[0])).millisecondsSinceEpoch;
      if (da != db) return da.compareTo(db);
      return a.s - b.s;
    });
    return allGaps;
  }

  static String _absMinutesToTime(int totalMins) {
    final h = (totalMins ~/ 60) % 24;
    final m = totalMins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // Time cell for the night weightage table: matches the webapp's display,
  // appending the next day in brackets when the time falls past midnight.
  static String _nwTimeText(int absMins, String displayDate) {
    final t = _absMinutesToTime(absMins);
    if ((absMins ~/ 60) % 24 <= 6) {
      final parts = displayDate.split('/');
      if (parts.length == 3) {
        final d = int.parse(parts[0]);
        final mo = int.parse(parts[1]);
        final y = 2000 + int.parse(parts[2]);
        final dt = DateTime(y, mo, d).add(const Duration(days: 1));
        final nd = '${dt.day.toString().padLeft(2, '0')}'
            '/${dt.month.toString().padLeft(2, '0')}'
            '/${(dt.year % 100).toString().padLeft(2, '0')}';
        return '$t ($nd)';
      }
    }
    return t;
  }

  static String _durText(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return '$h hrs ${m.toString().padLeft(2, '0')} min';
  }

  // ================================================================
  // 3. LOCK TO APPROACH JETTY (A4 portrait)
  // ================================================================

  static const _lockCols = [
    [39.8, 69.8],
    [69.8, 152.2],
    [152.2, 322.5],
    [322.5, 438.8],
    [438.8, 555.0],
  ];
  static const _lockXs = [39.8, 69.8, 152.2, 322.5, 438.8, 555.0];
  static const _lockRows = [
    275.2, 304.5, 328.5, 352.5, 376.5, 400.5, 424.5, 448.5, 472.5, 496.5,
    520.5, 544.5,
  ];
  static const _lockHeaderLabels = [
    _L('SL.', 48.7, 280.9),
    _L('NO.', 48.4, 290.6),
    _L('DATE', 100.7, 286.1),
    _L('NAME OF VESSEL', 202.4, 286.1),
    _L('STARTING TIME FROM', 336.4, 280.9),
    _L('LOCK', 369.9, 290.6),
    _L('MADE FAST TIME', 460.5, 280.9),
    _L('AT APP. JETTY', 465.1, 290.6),
  ];

  static Future<Uint8List> _buildLock(ClaimData data, _Fonts f,
      {bool admDuty = false}) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    bool onActing(Movement mv) =>
        acting.contains(AllowanceCalculator.movementShiftDate(mv));
    final items = AllowanceCalculator.movementsForMonth(data)
        .where((m) =>
            m.hasAllowance('lock') &&
            (admDuty
                ? onActing(m)
                : (data.master.isAdm || !onActing(m))))
        .toList();
    final pages = math.max(1, (items.length / 10).ceil());
    final m = data.master;
    final parsed = MasterData.parseMonthYear(m.month);
    final monthName = parsed != null
        ? MasterData.monthNames[parsed.$2 - 1]
        : m.month
            .replaceAll(RegExp(r',?\s*(?:19|20)\d{2}\s*$'), '')
            .trim();
    final year = parsed != null
        ? (parsed.$1 % 100).toString()
        : m.month.contains(RegExp(r'(?:19|20)\d{2}'))
            ? RegExp(r'(?:19|20)(\d{2})').firstMatch(m.month)!.group(1)!
            : '';
    for (var p = 0; p < pages; p++) {
      final chunk = items.skip(p * 10).take(10).toList();
      final w = <pw.Widget>[];
      w.add(_txt(f, 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA', 162.7, 35.6, 11.25,
          bold: true));
      w.add(_txt(f, 'HALDIA DOCK COMPLEX', 225.4, 51.3, 11.25, bold: true));
      w.add(_txt(f, 'Code No. 067', 39.7, 73.3, 9.38, bold: true));
      w.add(_txt(f, 'Dated: ', 440.9, 73.3, 9.38, bold: true));
      w.add(_hLine(473.2, 555.8, 84.0));
      w.add(_txt(f, 'MARINE OFFICE', 482.7, 87.5, 9.38, bold: true));
      w.add(_txt(f, 'CLAIM FORM FOR THE PAYMENT OF', 202.5, 109.7, 10.5,
          bold: true));
      w.add(_txt(
          f,
          'LOCK TO APPROACH JETTY (WITHOUT RIVER PILOT) ALLOWANCE',
          122.5,
          124.0,
          10.5,
          bold: true));
      w.add(_txt(f, 'For the Month of', 193.9, 143.8, 9.38, bold: true));
      w.add(_txt(f, monthName, 273.8, 143.8, 11.5, bold: true));
      w.add(_txt(f, '20', 360.9, 143.8, 9.38, bold: true));
      w.add(_txt(f, year, 377.2, 143.8, 11.5, bold: true));
      w.add(_txt(f, 'Name:', 39.7, 171.8, 9.0, bold: true));
      w.add(_txt(f, m.name, 72.8, 171.8, 11.5, bold: true));
      w.add(_txt(f, 'Designation:', 311.2, 171.8, 9.0, bold: true));
      w.add(_txt(
          f,
          admDuty ? _admDutyDsgn(m) : m.designation,
          371.2,
          171.8,
          11.5,
          bold: true));
      w.add(_txt(f, 'Pay Rs.', 39.7, 194.3, 9.0, bold: true));
      w.add(_txt(f, '${m.payLine}/-', 78.0, 194.3, 11.5, bold: true));
      w.add(_txt(f, 'Bill Abst. No.:', 180.0, 194.3, 9.0, bold: true));
      w.add(_txt(f, m.bill, 250.0, 194.3, 11.5, bold: true));
      w.add(_txt(f, 'DPS/Employee No.:', 311.2, 194.3, 9.0, bold: true));
      w.add(_txt(f, m.employee, 401.2, 194.3, 11.5, bold: true));
      w.add(_txt(
          f,
          '(1) LOCK TO APPROACH JETTY (WITHOUT RIVER PILOT) (CODE - 067)',
          144.5,
          241.6,
          9.0,
          bold: true));
      w.add(_txt(
          f,
          '(Rs. 1000/- for Dock Pilot/Berthing Pilot and Rs. 1500/- '
          'for Assistant Dock Master per Movement)',
          106.9,
          255.0,
          8.25));
      w.addAll(_grid(_lockRows, _lockXs));
      for (final l in _lockHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 7.88, bold: true));
      }
      for (var i = 0; i < 10; i++) {
        final mv = i < chunk.length ? chunk[i] : null;
        final y = 312.4 + i * 24.0;
        w.add(_cell(f, mv == null ? '' : '${p * 10 + i + 1}.', _lockCols[0], y, 8.62));
        w.add(_cell(f, mv?.date ?? '', _lockCols[1], y, 8.62));
        w.add(_cell(f, mv?.vessel ?? '', _lockCols[2], y, 8.62));
        w.add(_cell(f, mv?.start ?? '', _lockCols[3], y, 8.62));
        w.add(_cell(f, mv?.end ?? '', _lockCols[4], y, 8.62));
      }
      w.add(_txt(f, 'The Manager (P&IR), Haldia Dock Complex.', 39.7, 590.7,
          8.62,
          bold: true));
      w.add(_txt(f, 'Forwarded for necessary action at the earliest.', 39.7,
          605.7, 8.62,
          bold: true));
      w.add(_cell(f, 'The Manager (M.O.), HDC', [370.0, 555.5], 590.7, 8.62,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct.', [370.0, 555.5],
          605.7, 8.62,
          bold: true));
      w.add(_cell(f, 'Manager', [39.7, 200.0], 650.7, 8.62, bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [39.7, 200.0], 664.2, 8.62,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [39.7, 200.0], 676.9, 8.62,
          bold: true));
      w.add(_cell(f, 'Dy./Asst. Dock Master,', [200.0, 370.0], 650.7, 8.62,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [200.0, 370.0], 664.2, 8.62,
          bold: true));
      final isAdmDuty = admDuty || data.master.isAdm;
      final sigLine1 = _signatureLabel(isAdmDuty);
      final sigLine2 =
          admDuty ? 'Asst. Dock Master' : _signatureRole(data.master);
      w.add(_cell(f, sigLine1, [370.0, 555.5], 650.7, 8.62, bold: true));
      w.add(_cell(f, sigLine2, [370.0, 555.5], 664.2, 8.62, bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  // ================================================================
  // 4. NIGHT NAVIGATION (A4 LANDSCAPE)
  // ================================================================

  static const _navCols = [
    [28.5, 54.8],
    [54.8, 118.5],
    [118.5, 318.0],
    [318.0, 370.5],
    [370.5, 423.0],
    [423.0, 464.2],
    [464.2, 505.5],
    [505.5, 595.5],
    [595.5, 730.5],
    [730.5, 813.0],
  ];
  static const _navXs = [
    28.5, 54.8, 118.5, 318.0, 370.5, 423.0, 464.2, 505.5, 595.5, 730.5, 813.0,
  ];
  static const _navRows = [
    89.2, 106.5, 123.8, 142.5, 161.2, 180.0, 198.8, 217.5, 236.2, 255.0,
    273.8, 292.5, 311.2,
  ];
  static const _navHeaderLabels = [
    _L('SL.', 35.4, 97.5),
    _L('NO.', 34.5, 106.5),
    _L('DATE', 75.9, 102.0),
    _L('NAME OF THE VESSEL', 172.8, 102.0),
    _L('MOVEMENT', 347.2, 93.8),
    _L('TIME (24 HRS)', 436.6, 93.8),
    _L('LENGTH/BEAM OF', 513.9, 97.5),
    _L('THE VESSEL', 525.4, 106.5),
    _L('INWARD/OUTWARD/DOUBLE', 605.8, 97.5),
    _L('BANKING/UNBANKING', 617.9, 106.5),
    _L('SUNRISE/SUNSET', 736.1, 97.5),
    _L('TIME (24 HRS)', 744.1, 106.5),
    _L('FROM', 332.6, 111.0),
    _L('TO', 391.6, 111.0),
    _L('FROM', 432.0, 111.0),
    _L('TO', 479.8, 111.0),
  ];
  static const _navMerged = [
    (0, 1, 0, 0), // SL. / NO.
    (0, 1, 1, 1), // DATE
    (0, 1, 2, 2), // NAME OF THE VESSEL
    (0, 0, 3, 4), // MOVEMENT (From/To)
    (0, 0, 5, 6), // TIME (24 HRS) (From/To)
    (0, 1, 7, 7), // LENGTH/BEAM OF THE VESSEL
    (0, 1, 8, 8), // INWARD/OUTWARD/DOUBLE BANKING/UNBANKING
    (0, 1, 9, 9), // SUNRISE/SUNSET TIME (24 HRS)
  ];

  static Future<Uint8List> _buildNightNavigation(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    final items = <(Movement, String)>[];
    for (final mv in AllowanceCalculator.movementsForMonth(data)) {
      if (!mv.hasAllowance('navigation')) continue;
      if (acting.contains(AllowanceCalculator.normDateKey(mv.date))) continue;
      if (mv.navigationTypes.isNotEmpty) {
        for (final t in mv.navigationTypes) {
          items.add((mv, _navTypeLabel(t)));
        }
      } else {
        items.add((mv, _navType(mv)));
        final dual = _navDualType(mv);
        if (dual != null) items.add((mv.copy(), dual));
      }
    }
    final pages = math.max(1, (items.length / 10).ceil());
    final m = data.master;
    for (var p = 0; p < pages; p++) {
      final chunk = items.skip(p * 10).take(10).toList();
      final w = <pw.Widget>[];
      w.add(_txt(f, 'K.P.P./8000 Sheets/03-2011', 28.3, 28.5, 8.25, bold: true));
      w.add(_txt(f, 'Code No.-44060036', 738.2, 28.5, 8.25, bold: true));
      w.add(_txt(
          f,
          'COMPENSATION FOR NIGHT NAVIGATION FOR THE MONTH OF ',
          166.6,
          40.9,
          12.0,
          bold: true));
      final monthLabel = _monthLabel(m.month);
      w.add(_txt(f, monthLabel,
          615.75 - _est(monthLabel, 12.0) / 2, 40.9, 12.0, bold: true));
      w.add(_txt(f, 'Name:', 28.3, 67.6, 9.0, bold: true));
      w.add(_txt(f, m.name, 57.8, 67.6, 11.5, bold: true));
      w.add(_txt(f, 'Designation:', 345.6, 67.6, 9.0, bold: true));
      w.add(_txt(f, m.designation, 402.1, 67.6, 11.5, bold: true));
      w.add(_txt(f, 'Emp. I.D :', 662.8, 67.6, 9.0, bold: true));
      w.add(_txt(f, m.employee, 706.3, 67.6, 11.5, bold: true));
      w.addAll(_grid(_navRows, _navXs, merged: _navMerged));
      for (final l in _navHeaderLabels) {
        w.add(_txt(f, l.t, l.x, l.y, 8.25, bold: true));
      }
      for (var i = 0; i < 10; i++) {
        final entry = i < chunk.length ? chunk[i] : null;
        final y = 129.0 + i * 18.75;
        final cells = entry == null
            ? ['', '', '', '', '', '', '', '', '', '']
            : _navCells(entry.$1, p * 10 + i + 1, entry.$2);
        for (var c = 0; c < 10; c++) {
          w.add(_cell(f, cells[c], _navCols[c], y, 8.25));
        }
      }
      w.add(_txt(f, 'The Manager (P & IR)', 28.3, 343.5, 8.25, bold: true));
      w.add(_txt(f, 'Haldia Dock Complex', 28.3, 354.8, 8.25, bold: true));
      w.add(_txt(f, 'Forwarded for necessary action at the earliest.', 28.3,
          382.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Manager', [28.5, 240.0], 431.3, 8.25, bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [28.5, 240.0], 442.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [28.5, 240.0], 454.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Dy. Dock Master', [240.0, 400.0], 431.3, 8.25,
          bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [240.0, 400.0], 442.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [240.0, 400.0], 454.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Asst. Dock Master', [400.0, 560.0], 431.3, 8.25,
          bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [400.0, 560.0], 442.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [400.0, 560.0], 454.5, 8.25,
          bold: true));
      w.add(_cell(f, 'Signature of the', [560.0, 813.0], 431.3, 8.25,
          bold: true));
      w.add(_cell(f, _signatureRole(m), [560.0, 813.0], 442.5, 8.25,
          bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  static bool _isOutwardNav(Movement mv) {
    if (mv.navigationTypes.isNotEmpty) {
      return mv.navigationTypes.any((t) =>
          t == 'outward-180-210' || t == 'outward-210' || t == 'outward-beam');
    }
    return mv.hasAllowance('navigation') && _navType(mv) == 'OUTWARD';
  }

  static bool _isInwardNav(Movement mv) {
    if (mv.navigationTypes.isNotEmpty) {
      return mv.navigationTypes.contains('inward-210');
    }
    return mv.hasAllowance('navigation') && _navType(mv) == 'INWARD';
  }

  static void _ajCells(List<pw.Widget> w, _Fonts f, List<String> cells,
      List<List<double>> cols, double y) {
    for (var c = 0; c < cols.length; c++) {
      w.add(_cell(f, cells[c], cols[c], y, 8.25));
    }
  }

  // ================================================================
  // 5. ADM NIGHT NAVIGATION ALLOWANCE (A4 portrait)
  //    Per "ADM ALLOWANCE NEW FORM.docx": header, section A (OUTWARD,
  //    CODE- 097) and section B (INWARD, CODE – 097) only. Lock-to-approach
  //    jetty movements go to the separate Lock form (Code 067). Rates per
  //    the official form: outward 675/1010, inward 540.
  // ================================================================

  static const _ajNavXs = [
    39.8, 66.0, 128.0, 222.0, 270.0, 318.0, 400.0, 474.0, 555.5,
  ];
  static const _ajNavCols = [
    [39.8, 66.0],
    [66.0, 128.0],
    [128.0, 222.0],
    [222.0, 270.0],
    [270.0, 318.0],
    [318.0, 400.0],
    [400.0, 474.0],
    [474.0, 555.5],
  ];
  static const _ajSecAYs = [
    258.0, 272.0, 286.0, 300.0, 314.0, 328.0, 342.0, 356.0, 370.0, 384.0,
    398.0, 412.0, 426.0,
  ];
  static const _ajSecBYs = [
    492.0, 506.0, 520.0, 534.0, 548.0, 562.0, 576.0, 590.0, 604.0, 618.0,
    632.0,
  ];

  static Future<Uint8List> _buildAdmNightNavigation(ClaimData data, _Fonts f) {
    final doc = pw.Document();
    final acting = _actingDateKeys(data);
    final moves = AllowanceCalculator.movementsForMonth(data)
        .where((mv) =>
            data.master.isAdm ||
            acting.contains(AllowanceCalculator.movementShiftDate(mv)))
        .toList();
    final outward = moves.where(_isOutwardNav).toList();
    final inward = moves.where(_isInwardNav).toList();
    final pages = math.max(
        1,
        math.max((outward.length / 12).ceil(),
            (inward.length / 10).ceil()));
    final m = data.master;
    final parsed = MasterData.parseMonthYear(m.month);
    final monthName = parsed != null
        ? MasterData.monthNames[parsed.$2 - 1]
        : m.month
            .replaceAll(RegExp(r',?\s*(?:19|20)\d{2}\s*$'), '')
            .trim();
    final year = parsed != null
        ? (parsed.$1 % 100).toString()
        : m.month.contains(RegExp(r'(?:19|20)\d{2}'))
            ? RegExp(r'(?:19|20)(\d{2})').firstMatch(m.month)!.group(1)!
            : '';
    String sunStr(String date) {
      final t = AllowanceCalculator.getSunTimes(date);
      if (t == null) return '';
      return '${_minToHHMM(t.$1)} / ${_minToHHMM(t.$2)}';
    }

    const dev1 = 'स्यामा प्रसाद मुखर्जी, कोलकाता';
    const devEng = 'SYAMA PRASAD MOOKERJEE PORT, KOLKATA';
    const dev2 =
        '\u0939\u0932\u094d\u0926\u093f\u092f\u093e \u0917\u094b\u0926\u0940 '
        '\u092a\u0930\u093f\u0938\u0930 / HALDIA DOCK COMPLEX';

    for (var p = 0; p < pages; p++) {
      final a = outward.skip(p * 12).take(12).toList();
      final b = inward.skip(p * 10).take(10).toList();
      final w = <pw.Widget>[];
      w.add(_txt(f, dev1, 224.0, 24, 11.5, bold: true, font: f.devanagari));
      w.add(_txt(f, devEng, 152.0, 38, 11.5, bold: true));
      w.add(_txt(f, dev2, 181.0, 52, 11.0, bold: true, font: f.devanagari));
      w.add(_txt(f, 'MARINE OFFICE HALDIA', 230.0, 66, 10.0, bold: true));
      w.add(_txt(f, 'Dated: ', 440.9, 78, 9.0, bold: true));
      w.add(_hLine(474.0, 510.0, 90.0));
      w.add(_txt(f, '20', 512.5, 78, 9.0, bold: true));
      w.add(_hLine(524.0, 555.5, 90.0));
      w.addAll(_grid([16.0, 36.0], [445.0, 555.5]));
      w.add(_cell(f, 'Code No. 44060025', [445.0, 555.5], 26, 8.5, bold: true));
      w.add(_txt(
          f,
          'CLAIM FORM FOR THE PAYMENT OF NIGHT NAVIGATION ALLOWANCE',
          109.0,
          98,
          10.0,
          bold: true));
      w.add(_txt(f, 'For the Month of', 39.8, 128, 9.0, bold: true));
      w.add(_txt(f, monthName, 118.0, 128, 11.5, bold: true));
      w.add(_txt(f, '20', 210.0, 128, 9.0, bold: true));
      w.add(_txt(f, year, 225.0, 128, 11.5, bold: true));
      w.add(_txt(f, 'Name:', 39.8, 150, 9.0, bold: true));
      w.add(_txt(f, m.name, 72.8, 150, 11.5, bold: true));
      w.add(_txt(f, 'Designation:', 311.2, 150, 9.0, bold: true));
      w.add(_txt(f, _admDutyDsgn(m), 371.2, 150, 11.5, bold: true));
      w.add(_txt(f, 'Bill Abst. No.:', 39.8, 172, 9.0, bold: true));
      w.add(_txt(f, m.bill, 103.5, 172, 11.5, bold: true));
      w.add(_txt(f, 'DPS/Employee No.:', 311.2, 172, 9.0, bold: true));
      w.add(_txt(f, m.employee, 401.2, 172, 11.5, bold: true));
      w.add(_txt(
          f, '(A)  OUTWARD MOVEMENT ALLOWANCE (CODE- 097)', 39.8, 216, 9.0,
          bold: true));
      w.add(_txt(
          f,
          '(i)  Rs. 675 for length from 180 mtrs. Or beam above 30.5 mtrs '
          'irrespective of length',
          39.8,
          229,
          8.0));
      w.add(_txt(
          f, '(ii)  Rs. 1010 for length of 210 mtrs and onwards',
          39.8, 241, 8.0));
      w.addAll(_grid(_ajSecAYs, _ajNavXs));
      const ah = [
        'SL.NO',
        'DATE',
        'NAME OF VESSEL',
        'LENGTH',
        'BEAM',
        'TAKING OVER TIME',
        'MADE FAST TIME',
        'SUN R/S',
      ];
      for (var c = 0; c < ah.length; c++) {
        w.add(_cell(f, ah[c], _ajNavCols[c], 258, c == 7 ? 7.0 : 8.0,
            bold: true));
      }
      for (var i = 0; i < 12; i++) {
        final mv = i < a.length ? a[i] : null;
        final cells = mv == null
            ? ['', '', '', '', '', '', '', '']
            : [
                '${p * 12 + i + 1}.',
                mv.date,
                mv.vessel,
                mv.loa,
                mv.beam,
                mv.start,
                mv.end,
                sunStr(mv.date),
              ];
        _ajCells(w, f, cells, _ajNavCols, 272 + i * 14);
      }
      w.add(_txt(
          f, '(B)  INWARD MOVEMENT ALLOWANCES (CODE \u2013 097)', 39.8, 462,
          9.0, bold: true));
      w.add(_txt(
          f, 'Rs.540/- for length of 210 metres and onwards.', 39.8, 475, 8.0));
      w.addAll(_grid(_ajSecBYs, _ajNavXs));
      const bh = [
        'SL.NO.',
        'DATE',
        'NAME OF VESSEL',
        'LENGTH',
        'BEAM',
        'MOVEMENT STARTED',
        'OUT OF LOCK',
        'SUN S/R',
      ];
      for (var c = 0; c < bh.length; c++) {
        w.add(_cell(f, bh[c], _ajNavCols[c], 492, c == 7 ? 7.0 : 8.0,
            bold: true));
      }
      for (var i = 0; i < 10; i++) {
        final mv = i < b.length ? b[i] : null;
        final cells = mv == null
            ? ['', '', '', '', '', '', '', '']
            : [
                '${p * 10 + i + 1}.',
                mv.date,
                mv.vessel,
                mv.loa,
                mv.beam,
                mv.start,
                mv.end,
                sunStr(mv.date),
              ];
        _ajCells(w, f, cells, _ajNavCols, 506 + i * 14);
      }
      w.add(_txt(f, 'The Manager (P&IR), Haldia Dock Complex.', 39.8, 695,
          8.62, bold: true));
      w.add(_txt(f, 'Forwarded for necessary action', 39.8,
          712, 8.62, bold: true));
      w.add(_cell(f, 'The Manager (M.O.), HDC', [350.2, 555.5], 695, 8.62,
          bold: true));
      w.add(_cell(f, 'Certified that the statement is correct.', [350.2, 555.5],
          712, 8.62, bold: true));
      w.add(_cell(f, 'Manager', [39.8, 195.0], 748, 8.25, bold: true));
      w.add(_cell(f, 'Marine Ops. Division,', [39.8, 195.0], 761, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [39.8, 195.0], 774, 8.25,
          bold: true));
      w.add(_cell(f, 'Deputy Dock Master', [195.0, 350.2], 748, 8.25,
          bold: true));
      w.add(_cell(f, 'Haldia Dock Complex', [195.0, 350.2], 761, 8.25,
          bold: true));
      w.add(_cell(f, 'Signature of ADM', [350.2, 555.5], 748, 8.25,
          bold: true));
      w.add(_cell(f, 'Asst. Dock Master', [350.2, 555.5], 761, 8.25,
          bold: true));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(w),
      ));
    }
    return doc.save();
  }

  static String? _navDualType(Movement mv) {
    final from = mv.from.toUpperCase();
    final to = mv.to.toUpperCase();
    final fromOff = from.contains('OFF');
    final toOff = to.contains('OFF');
    final fromLock = from.contains('LOCK');
    final toLock = to.contains('LOCK');
    if (fromOff && toOff) return 'DOUBLE BANKING';
    if (fromOff && toLock) return 'OUTWARD';
    if (fromLock && toOff) return 'DOUBLE BANKING';
    return null;
  }

  static String _navType(Movement mv) {
    final from = mv.from.toUpperCase();
    final to = mv.to.toUpperCase();
    final fromOff = from.contains('OFF');
    final toOff = to.contains('OFF');
    final fromLock = from.contains('LOCK');
    final toLock = to.contains('LOCK');
    if (fromOff && toOff) return 'UNBANKING';
    if (fromOff && toLock) return 'UNBANKING';
    if (fromLock && toOff) return 'INWARD';
    if (toLock) return 'OUTWARD';
    if (fromLock) return 'INWARD';
    if (toOff) return 'DOUBLE BANKING';
    if (fromOff) return 'UNBANKING';
    return mv.navigationTypes.isNotEmpty
        ? _navTypeLabel(mv.navigationTypes.first)
        : '';
  }

  static String _navTypeLabel(String navigationType) {
    return switch (navigationType) {
      'outward-180-210' || 'outward-210' || 'outward-beam' => 'OUTWARD',
      'inward-210' => 'INWARD',
      'double-banking' || 'unbanking' => navigationType == 'double-banking'
          ? 'DOUBLE BANKING'
          : 'UNBANKING',
      _ => navigationType.toUpperCase(),
    };
  }

  static List<String> _navCells(Movement mv, int sl, String type) {
    final dim = mv.loa + (mv.beam.isNotEmpty ? ' / ${mv.beam}' : '');
    String sun = '';
    final t = AllowanceCalculator.getSunTimes(mv.date);
    if (t != null) {
      sun = '${_minToHHMM(t.$1)} / ${_minToHHMM(t.$2)}';
    }
    return [
      '$sl',
      mv.date,
      mv.vessel,
      mv.from,
      mv.to,
      mv.start,
      mv.end,
      dim,
      type,
      sun,
    ];
  }

  static String _minToHHMM(int mins) {
    final h = (mins ~/ 60) % 24;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
