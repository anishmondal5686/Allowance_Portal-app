import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/services/official_forms_service.dart';

class OfficialFormsScreen extends StatelessWidget {
  final ClaimData claimData;

  const OfficialFormsScreen({super.key, required this.claimData});

  List<(OfficialForm, String)> get _tabs {
    final t = <(OfficialForm, String)>[
      if (!claimData.master.isAdm)
        (OfficialForm.lengthAndCold, 'Length & Cold')
      else
        (OfficialForm.lengthAllowance, 'Length'),
      (OfficialForm.nightActWeightage, 'Night Act & Weightage'),
      (OfficialForm.lockToApproachJetty, 'Lock to Jetty'),
      (OfficialForm.nightNavigation, 'Night Navigation'),
    ];
    if (claimData.actingAdmDates.isNotEmpty) {
      if (!claimData.master.isAdm) {
        t.insert(2, (OfficialForm.lengthAllowance, 'Length (ADM Duty)'));
        final lockIdx =
            t.indexWhere((e) => e.$1 == OfficialForm.lockToApproachJetty);
        t.insert(lockIdx + 1, (OfficialForm.lockToApproachJettyAdmDuty,
            'Lock to Jetty (ADM Duty)'));
      }
      t.insert(3,
          (OfficialForm.nightActWeightageAdmDuty, 'Night Weightage (ADM Duty)'));
      t.add(
          (OfficialForm.nightNavigationAdmDuty, 'Night Navigation (ADM Duty)'));
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Official Allowance Forms'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$2)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in tabs)
              _FormPreview(claimData: claimData, form: t.$1),
          ],
        ),
      ),
    );
  }
}

class _FormPreview extends StatefulWidget {
  final ClaimData claimData;
  final OfficialForm form;

  const _FormPreview({required this.claimData, required this.form});

  @override
  State<_FormPreview> createState() => _FormPreviewState();
}

class _FormPreviewState extends State<_FormPreview> {
  static const _minScale = 1.0;
  static const _maxScale = 8.0;
  static const _zoomStep = 1.5;

  late final Future<PdfDocument> _document;
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _document = PdfDocument.openData(
      OfficialFormsService.buildFormPdf(widget.form, widget.claimData),
    );
    _controller = PdfControllerPinch(document: _document);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    try {
      final current = _controller.zoomRatio;
      final target = (current * factor).clamp(_minScale, _maxScale);
      if (target == current) return;
      final center = _controller.viewRect.center;
      final k = target / current;
      final next = Matrix4.translationValues(center.dx, center.dy, 0)
        ..multiply(Matrix4.diagonal3Values(k, k, 1.0))
        ..multiply(Matrix4.translationValues(-center.dx, -center.dy, 0))
        ..multiply(_controller.value);
      _controller.value = next;
    } catch (_) {}
  }

  void _resetZoom() {
    try {
      final m = _controller.calculatePageFitMatrix(pageNumber: _controller.page);
      if (m != null) {
        _controller.value = m;
      }
    } catch (_) {}
  }

  Future<void> _share() async {
    final bytes = await OfficialFormsService.buildFormPdf(
        widget.form, widget.claimData);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          OfficialFormsService.pdfFileName(widget.form, widget.claimData.master.month),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: PdfViewPinch(
            controller: _controller,
            minScale: _minScale,
            maxScale: _maxScale,
          ),
        ),
        Material(
          color: scheme.surface,
          elevation: 4,
          child: SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _BarButton(
                    tooltip: 'Print form',
                    icon: Icons.print,
                    onPressed: () => OfficialFormsService.printForm(
                        widget.form, widget.claimData),
                  ),
                  _BarButton(
                    tooltip: 'Share form',
                    icon: Icons.share,
                    onPressed: _share,
                  ),
                  _BarButton(
                    tooltip: 'Zoom out',
                    icon: Icons.remove,
                    onPressed: () => _zoomBy(1 / _zoomStep),
                  ),
                  _BarButton(
                    tooltip: 'Zoom in',
                    icon: Icons.add,
                    onPressed: () => _zoomBy(_zoomStep),
                  ),
                  _BarButton(
                    tooltip: 'Reset zoom',
                    icon: Icons.fit_screen,
                    onPressed: _resetZoom,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _BarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
