import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/constants/invoice_lifecycle.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/receipt_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pos/models/invoice_models.dart';
import '../../pos/providers/pos_products_provider.dart';
import '../../products/providers/products_provider.dart';
import '../../returns/screens/customer_returns_screen.dart';
import '../models/invoice_detail.dart';
import '../models/invoice_history_row.dart' show invoicePaymentLabelAr;
import '../providers/invoice_history_provider.dart';

/// Read-only desktop dialog: header, line items, totals, full return, reprint + close.
class InvoiceDetailsDialog extends ConsumerStatefulWidget {
  const InvoiceDetailsDialog({super.key, required this.invoiceId});

  final int invoiceId;

  static final _df = DateFormat('yyyy/MM/dd HH:mm');
  static final _money = NumberFormat('#,##0.##');

  @override
  ConsumerState<InvoiceDetailsDialog> createState() =>
      _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends ConsumerState<InvoiceDetailsDialog> {
  bool _returning = false;

  Future<void> _reprint(BuildContext context, InvoiceDetailData data) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final paid = data.header.cashPaid + data.header.cardPaid;
    try {
      await printSale(
        invoiceNumber: data.header.invoiceNumber,
        items: data.lines
            .map(
              (l) => InvoiceItem(
                name: l.productName,
                qty: l.quantity,
                unitPrice: l.unitPrice,
                lineTotal: l.lineTotal,
              ),
            )
            .toList(),
        paid: paid > 0 ? paid : null,
        change:
            data.header.changeAmount > 0 ? data.header.changeAmount : null,
        customerName: data.header.customerName == 'زبون عام'
            ? null
            : data.header.customerName,
        cashierName:
            data.header.cashierName == '—' ? null : data.header.cashierName,
      );
      if (!context.mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('تم إرسال الفاتورة للطباعة')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('خطأ في الطباعة: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmFullReturn(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد إرجاع الفاتورة'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('سيتم تنفيذ الإرجاع الكامل لهذه الفاتورة وفق التالي:'),
                SizedBox(height: 14),
                Text('• إعادة جميع الكميات المباعة إلى المخزون.'),
                SizedBox(height: 8),
                Text('• تسجيل حركات إرجاع وترحيل صحيح للمخزون.'),
                SizedBox(height: 8),
                Text('• وسم الفاتورة كمرتجعة — لا يمكن تكرار الإرجاع.'),
                SizedBox(height: 8),
                Text(
                  'لن يتم حذف الفاتورة الأصلية؛ تبقى محفوظة للمراجعة المحاسبية.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.textPrimary,
              ),
              child: const Text('تأكيد الإرجاع'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() => _returning = true);
    try {
      await AppDatabase.instance.returnsDao
          .returnFullSaleInvoice(widget.invoiceId);

      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      ref.invalidate(invoiceHistoryPageProvider);
      ref.invalidate(customerReturnsProvider);
      ref.invalidate(productsNotifierProvider);
      ref.invalidate(posProductsProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('تم إرجاع الفاتورة بنجاح واستعادة المخزون.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on StateError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('تعذر إرجاع الفاتورة: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _returning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final authState = ref.watch(authProvider).valueOrNull;
    final canFullRefund = authState?.hasPermission('pos.full_refund') ?? false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText('تعذر تحميل الفاتورة:\n$e'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            ),
            data: (data) => Stack(
              children: [
                _InvoiceDetailBody(
                  data: data,
                  canFullRefund: canFullRefund,
                  returning: _returning,
                  onClose: () => Navigator.of(context).pop(),
                  onReprint: () => _reprint(context, data),
                  onFullReturn: () => _confirmFullReturn(context),
                ),
                if (_returning)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.12),
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('جارٍ معالجة الإرجاع...'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceDetailBody extends StatelessWidget {
  const _InvoiceDetailBody({
    required this.data,
    required this.canFullRefund,
    required this.returning,
    required this.onClose,
    required this.onReprint,
    required this.onFullReturn,
  });

  final InvoiceDetailData data;
  final bool canFullRefund;
  final bool returning;
  final VoidCallback onClose;
  final VoidCallback onReprint;
  final VoidCallback onFullReturn;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final h = data.header;
    final statusAr = invoiceLifecycleLabelAr(h.invoiceStatus);
    final canReturn = canFullRefund && !data.isReturned && !returning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      'تفاصيل الفاتورة ${h.invoiceNumber}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                    ),
                    if (data.isReturned)
                      const Chip(
                        label: Text('مرتجعة'),
                        backgroundColor: AppColors.warningLight,
                        side: BorderSide(color: AppColors.warning),
                        labelStyle: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(text: 'بيانات الفاتورة', style: titleStyle),
                  const SizedBox(height: 8),
                  _HeaderGrid(data: data, statusAr: statusAr),
                  const SizedBox(height: 24),
                  _SectionTitle(text: 'الأصناف', style: titleStyle),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor:
                          WidgetStateProperty.all(AppColors.primarySurface),
                      dataRowMinHeight: 40,
                      columnSpacing: 20,
                      horizontalMargin: 16,
                      columns: [
                        DataColumn(
                          label: Text('الصنف', style: titleStyle),
                        ),
                        DataColumn(
                          label: Text('الكمية', style: titleStyle),
                        ),
                        DataColumn(
                          label: Text('سعر الوحدة', style: titleStyle),
                        ),
                        DataColumn(
                          label: Text('الخصم', style: titleStyle),
                        ),
                        DataColumn(
                          label: Text('الإجمالي', style: titleStyle),
                        ),
                      ],
                      rows: [
                        for (final l in data.lines)
                          DataRow(
                            cells: [
                              DataCell(Text(l.productName, style: bodyStyle)),
                              DataCell(Text(
                                InvoiceDetailsDialog._money
                                    .format(l.quantity),
                                style: bodyStyle,
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.unitPrice)} د.ع',
                                style: bodyStyle,
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.discount)} د.ع',
                                style: bodyStyle,
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.lineTotal)} د.ع',
                                style: bodyStyle,
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(text: 'الإجماليات', style: titleStyle),
                  const SizedBox(height: 8),
                  _TotalsCard(data: data),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onReprint,
                icon: const Icon(Icons.print_rounded, size: 20),
                label: const Text('إعادة طباعة الفاتورة'),
              ),
              if (canFullRefund)
                Tooltip(
                  message: data.isReturned
                      ? 'هذه الفاتورة مرتجعة مسبقاً'
                      : 'إرجاع كامل مع استعادة المخزون',
                  child: FilledButton.icon(
                    onPressed: canReturn ? onFullReturn : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: AppColors.textPrimary,
                      disabledForegroundColor: AppColors.textSecondary,
                      disabledBackgroundColor: AppColors.surfaceVariant,
                    ),
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    label: const Text('إرجاع كامل الفاتورة'),
                  ),
                ),
              OutlinedButton(
                onPressed: onClose,
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style);
  }
}

class _HeaderGrid extends StatelessWidget {
  const _HeaderGrid({required this.data, required this.statusAr});

  final InvoiceDetailData data;
  final String statusAr;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 640;
            final child = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _HeaderCol1(data: data)),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _HeaderCol2(
                          data: data,
                          statusAr: statusAr,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeaderCol1(data: data),
                      const SizedBox(height: 16),
                      _HeaderCol2(data: data, statusAr: statusAr),
                    ],
                  );
            return child;
          },
        ),
      ),
    );
  }
}

class _HeaderCol1 extends StatelessWidget {
  const _HeaderCol1({required this.data});

  final InvoiceDetailData data;

  @override
  Widget build(BuildContext context) {
    final h = data.header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('رقم الفاتورة', h.invoiceNumber),
        _kv('التاريخ والوقت', InvoiceDetailsDialog._df.format(h.saleDate)),
        _kv('العميل', h.customerName),
        _kv('الكاشير', h.cashierName),
      ],
    );
  }
}

class _HeaderCol2 extends StatelessWidget {
  const _HeaderCol2({required this.data, required this.statusAr});

  final InvoiceDetailData data;
  final String statusAr;

  @override
  Widget build(BuildContext context) {
    final h = data.header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('طريقة الدفع', invoicePaymentLabelAr(h.paymentMethod)),
        _kv(
          'الحالة',
          statusAr,
          valueStyle: data.isReturned
              ? const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                )
              : null,
        ),
      ],
    );
  }
}

Widget _kv(String k, String val, {TextStyle? valueStyle}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            val,
            style: valueStyle ??
                const TextStyle(
                  color: AppColors.textPrimary,
                ),
          ),
        ),
      ],
    ),
  );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.data});

  final InvoiceDetailData data;

  @override
  Widget build(BuildContext context) {
    final h = data.header;
    final m = InvoiceDetailsDialog._money;

    Widget line(String label, String value, {bool emphasize = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                  fontSize: emphasize ? 17 : 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                fontSize: emphasize ? 17 : 15,
                color: emphasize ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            line('المجموع الفرعي', '${m.format(h.subtotal)} د.ع'),
            line('إجمالي الخصم', '${m.format(h.discountTotal)} د.ع'),
            line(
              data.showTax ? 'الضريبة (15٪)' : 'الضريبة',
              '${m.format(data.taxAmount)} د.ع',
            ),
            const Divider(height: 20),
            line('الإجمالي النهائي', '${m.format(data.grandTotal)} د.ع',
                emphasize: true),
          ],
        ),
      ),
    );
  }
}
