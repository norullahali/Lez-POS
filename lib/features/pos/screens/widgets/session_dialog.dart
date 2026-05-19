// lib/features/pos/screens/widgets/session_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../providers/pos_provider.dart';

// ---------------------------------------------------------------------------
// Open Session Dialog
// ---------------------------------------------------------------------------

class SessionOpenDialog extends ConsumerStatefulWidget {
  const SessionOpenDialog({super.key});

  @override
  ConsumerState<SessionOpenDialog> createState() => _SessionOpenDialogState();
}

class _SessionOpenDialogState extends ConsumerState<SessionOpenDialog> {
  final _cashCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authProvider).valueOrNull?.user;
    final cashierName = authUser?.fullName.trim().isNotEmpty == true
        ? authUser!.fullName
        : 'كاشير';

    return Dialog(
      backgroundColor: AppColors.posPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: AppColors.accent, size: 38),
              ),
              const SizedBox(height: 16),
              const Text(
                'فتح وردية جديدة',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              // Cashier identity chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined,
                        color: AppColors.accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      cashierName,
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Opening cash
              TextField(
                controller: _cashCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'رصيد الصندوق الافتتاحي',
                  labelStyle:
                      const TextStyle(color: Colors.white60, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  suffixText: 'د.ع',
                  suffixStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 12),
              // Optional note
              TextField(
                controller: _noteCtrl,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textDirection: TextDirection.rtl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  labelStyle:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : () => _open(cashierName),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('فتح الجلسة',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(String cashierName) async {
    final cash = double.tryParse(_cashCtrl.text.trim()) ?? 0.0;
    if (cash < 0) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(posSessionProvider.notifier).openSession(
            cashierName,
            cash,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Close Session Dialog
// ---------------------------------------------------------------------------

class SessionCloseDialog extends ConsumerStatefulWidget {
  const SessionCloseDialog({super.key, required this.session});

  final PosSession session;

  @override
  ConsumerState<SessionCloseDialog> createState() =>
      _SessionCloseDialogState();
}

class _SessionCloseDialogState extends ConsumerState<SessionCloseDialog> {
  static final _nf = NumberFormat('#,##0.##');

  final _actualCashCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isLoading = false;

  double? _actualCash;
  double? _expectedCash;
  double _cashReturns = 0.0;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _actualCashCtrl.addListener(() {
      setState(
          () => _actualCash = double.tryParse(_actualCashCtrl.text.trim()));
    });
  }

  @override
  void dispose() {
    _actualCashCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await ref
          .read(posRepositoryProvider)
          .getSessionSummary(widget.session.id);
      final cash = (summary['cash'] as num?)?.toDouble() ?? 0.0;
      final cashReturns = (summary['cash_returns'] as num?)?.toDouble() ?? 0.0;
      setState(() {
        _summary = summary;
        _cashReturns = cashReturns;
        _expectedCash = widget.session.openingCash + cash;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final diff = (_actualCash != null && _expectedCash != null)
        ? _actualCash! - _expectedCash!
        : null;
    final diffColor = diff == null
        ? Colors.white54
        : diff >= 0
            ? AppColors.success
            : AppColors.error;

    return Dialog(
      backgroundColor: AppColors.posPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.error, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إغلاق الوردية',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('تأكد من عد الصندوق قبل الإغلاق',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Session summary card
              if (_summary != null) ...[
                _SummaryCard(
                  salesCount: (_summary!['count'] as num?)?.toInt() ?? 0,
                  totalSales: (_summary!['total'] as num?)?.toDouble() ?? 0,
                  cashSales: (_summary!['cash'] as num?)?.toDouble() ?? 0,
                  cardSales: (_summary!['card'] as num?)?.toDouble() ?? 0,
                  cashReturns: _cashReturns,
                  openingCash: widget.session.openingCash,
                  expectedCash: _expectedCash ?? 0,
                  nf: _nf,
                ),
                const SizedBox(height: 20),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],

              // Actual cash input
              TextField(
                controller: _actualCashCtrl,
                autofocus: true,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'النقد المعدود فعلياً',
                  labelStyle:
                      const TextStyle(color: Colors.white60, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  suffixText: 'د.ع',
                  suffixStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 12),

              // Difference display
              if (diff != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: diffColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        diff >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: diffColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${diff >= 0 ? '+' : ''}${_nf.format(diff)} د.ع',
                        style: TextStyle(
                            color: diffColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        diff == 0
                            ? 'مطابق'
                            : diff > 0
                                ? 'فائض'
                                : 'عجز',
                        style: TextStyle(
                            color: diffColor.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _noteCtrl,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textDirection: TextDirection.rtl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'ملاحظة الإغلاق (اختياري)',
                  labelStyle:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed:
                          (_isLoading || _actualCashCtrl.text.trim().isEmpty)
                              ? null
                              : _close,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('تأكيد الإغلاق',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _close() async {
    final actualCash = double.tryParse(_actualCashCtrl.text.trim()) ?? 0.0;
    setState(() => _isLoading = true);
    try {
      await ref.read(posSessionProvider.notifier).closeSession(
            closingCash: actualCash,
            notes: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Summary Card inside close dialog
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.salesCount,
    required this.totalSales,
    required this.cashSales,
    required this.cardSales,
    required this.cashReturns,
    required this.openingCash,
    required this.expectedCash,
    required this.nf,
  });

  final int salesCount;
  final double totalSales;
  final double cashSales;
  final double cardSales;
  final double cashReturns;
  final double openingCash;
  final double expectedCash;
  final NumberFormat nf;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.posPanelLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _Row('عدد المبيعات', '$salesCount فاتورة'),
          _Row('إجمالي المبيعات', '${nf.format(totalSales)} د.ع'),
          _Row('مبيعات نقدية', '${nf.format(cashSales)} د.ع'),
          _Row('مبيعات بطاقة', '${nf.format(cardSales)} د.ع'),
          if (cashReturns > 0)
            _Row('مرتجعات نقدية', '- ${nf.format(cashReturns)} د.ع',
                warn: true),
          const Divider(color: Colors.white12, height: 20),
          _Row('رصيد افتتاحي', '${nf.format(openingCash)} د.ع'),
          _Row(
            'المتوقع في الصندوق',
            '${nf.format(expectedCash)} د.ع',
            highlight: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value,
      {this.highlight = false, this.warn = false});

  final String label;
  final String value;
  final bool highlight;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final Color valueColor = highlight
        ? AppColors.accentLight
        : warn
            ? AppColors.error
            : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              fontSize: highlight ? 14 : 13,
            ),
          ),
        ],
      ),
    );
  }
}