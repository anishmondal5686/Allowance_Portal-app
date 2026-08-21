import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:allowance_shared/models/claim_data.dart';
import 'package:allowance_shared/models/master_data.dart';
import 'package:allowance_shared/services/allowance_calculator.dart';
import 'package:allowance_shared/services/claim_print_service.dart';
import 'package:allowance_shared/services/official_forms_service.dart';
import 'official_forms_screen.dart';

class ClaimSummaryScreen extends StatefulWidget {
  final ClaimData claimData;
  final VoidCallback onChanged;

  const ClaimSummaryScreen({
    super.key,
    required this.claimData,
    required this.onChanged,
  });

  @override
  State<ClaimSummaryScreen> createState() => _ClaimSummaryScreenState();
}

class _ClaimSummaryScreenState extends State<ClaimSummaryScreen> {
  final _fmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  bool _printing = false;
  OfficialForm? _formPrinting;

  Future<void> _print() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _printing = true);
    try {
      await ClaimPrintService.printClaim(widget.claimData);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Print failed: $e')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _printForm(OfficialForm form) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _formPrinting = form);
    try {
      await OfficialFormsService.printForm(form, widget.claimData);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Print failed: $e')));
    } finally {
      if (mounted) setState(() => _formPrinting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = AllowanceCalculator.computeSummary(widget.claimData);
    final master = widget.claimData.master;
    final scheme = Theme.of(context).colorScheme;
    final monthLabel = master.month.isEmpty ? '—' : MasterData.displayMonth(master.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claim Summary'),
        actions: [
          IconButton(
            tooltip: 'Print / PDF',
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row(
                        Icons.person_outline, 'Name',
                        master.name.isEmpty ? '—' : master.name),
                    _row(
                        Icons.badge_outlined, 'Designation',
                        master.designation.isEmpty ? '—' : master.designation),
                    _row(
                        Icons.calendar_month_outlined, 'Month',
                        monthLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claim summary · $monthLabel',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (summary.lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No payable claim rows yet.',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    for (final line in summary.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(line.label)),
                            Text(
                                line.key == 'weightage' &&
                                        summary.nightWeightageHours > 0
                                    ? '${_fmt.format(line.amount)} · '
                                        '${summary.nightWeightageHours.toStringAsFixed(2)} hrs'
                                    : _fmt.format(line.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (summary.nightWeightageHours > 0 &&
                        !summary.hasWeightageAmount)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Expanded(child: Text('Night Weightage')),
                            Text(
                                '${summary.nightWeightageHours.toStringAsFixed(2)} '
                                'hrs',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.currency_rupee_rounded,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text('Grand total',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(_fmt.format(summary.grandTotal),
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary)),
                        ],
                      ),
                    ),
                    if (summary.payWarning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: scheme.tertiary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Enter the Pay amount to calculate Night Weightage.',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.tertiary),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print),
                label: const Text('Print / PDF'),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.description_outlined,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        const Text('Official Allowance Forms',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pre-filled official one-off allowance forms for this '
                      'month.',
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OfficialFormsScreen(
                              claimData: widget.claimData,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Official Forms'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in [
                      if (!widget.claimData.master.isAdm)
                        (OfficialForm.lengthAndCold,
                            'Length & Cold Movement Allowance')
                      else
                        (OfficialForm.lengthAllowance,
                            'Length Allowance'),
                      if (!widget.claimData.master.isAdm &&
                          widget.claimData.actingAdmDates.isNotEmpty)
                        (OfficialForm.lengthAllowance,
                            'Length Allowance (ADM Duty)'),
                      (OfficialForm.nightActWeightage,
                          'Night Act & Night Weightage Allowance'),
                      (OfficialForm.lockToApproachJetty,
                          'Lock to Approach Jetty Allowance'),
                      if (!widget.claimData.master.isAdm &&
                          widget.claimData.actingAdmDates.isNotEmpty)
                        (OfficialForm.lockToApproachJettyAdmDuty,
                            'Lock to Approach Jetty Allowance (ADM Duty)'),
                      (OfficialForm.nightNavigation,
                          'Night Navigation Allowance'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _formPrinting == null
                                ? () => _printForm(entry.$1)
                                : null,
                            icon: _formPrinting == entry.$1
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.picture_as_pdf, size: 18),
                            label: Text(entry.$2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
