import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final Future<Uint8List> pdfFuture;
  final String pdfName;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.pdfFuture,
    required this.pdfName,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  static const _minScale = 1.0;
  static const _maxScale = 8.0;
  static const _zoomStep = 1.5;

  late final Future<PdfDocument> _document;
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _document = PdfDocument.openData(widget.pdfFuture);
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
      final m =
          _controller.calculatePageFitMatrix(pageNumber: _controller.page);
      if (m != null) {
        _controller.value = m;
      }
    } catch (_) {}
  }

  Future<void> _print() async {
    final bytes = await widget.pdfFuture;
    await Printing.layoutPdf(name: widget.pdfName, onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    final bytes = await widget.pdfFuture;
    await Printing.sharePdf(bytes: bytes, filename: widget.pdfName);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BarButton(
                      tooltip: 'Print',
                      icon: Icons.print,
                      onPressed: _print,
                    ),
                    _BarButton(
                      tooltip: 'Share',
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
      ),
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