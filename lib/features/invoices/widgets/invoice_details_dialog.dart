import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/constants/invoice_lifecycle.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/partial_return_service.dart';
import '../../../core/services/receipt_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/permissions/permission_keys.dart';
import '../../auth/providers/permission_provider.dart';
import '../../auth/utils/permission_actions.dart';
import '../../pos/models/invoice_models.dart';
import '../../pos/providers/pos_products_provider.dart';
import '../../products/providers/products_provider.dart';
import '../../returns/providers/partial_return_provider.dart';
import '../../returns/screens/customer_returns_screen.dart';
import '../models/invoice_detail.dart';
import '../models/invoice_history_row.dart' show invoicePaymentLabelAr;
import '../providers/invoice_history_provider.dart';

// ---------------------------------------------------------------------------
// Provider: already-returned quantities per invoice (keyed by sale_item_id).
// ---------------------------------------------------------------------------
final _partialReturnQtysProvider = FutureProvider.autoDispose
    .family<Map<int, double>, int>((ref, invoiceId) {
  return ref.read(partialReturnServiceProvider).getReturnedQuantitiesForInvoice(invoiceId);
});

/// Read-only desktop dialog: header, line items, totals, full/partial return, reprint + close.
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
    final meta = data.returnMetadata;
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
        change: data.header.changeAmount > 0 ? data.header.changeAmount : null,
        customerName: data.header.customerName == 'زبون عام'
            ? null
            : data.header.customerName,
        cashierName:
            data.header.cashierName == '—' ? null : data.header.cashierName,
        isReturned: data.isReturned,
        returnDate: meta?.returnDate,
        returnNote: meta?.returnNote,
        returnedByName: meta?.returnedByName,
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

  /// Shows the full-return confirmation dialog with a required note field.
  Future<String?> _showReturnConfirmDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReturnConfirmDialog(),
    );
  }

  Future<void> _confirmFullReturn(BuildContext context) async {
    if (!PermissionActions.guard(
      ref,
      context,
      PermissionKeys.posFullRefund,
    )) {
      return;
    }

    final note = await _showReturnConfirmDialog(context);
    if (note == null) return;
    if (!mounted) return;

    final authState = ref.read(authProvider).valueOrNull;
    final userId = authState?.user?.id;
    if (userId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('تعذر التحقق من هوية المستخدم. الرجاء تسجيل الدخول مجدداً.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _returning = true);
    try {
      await AppDatabase.instance.returnsDao.returnFullSaleInvoice(
        widget.invoiceId,
        note: note,
        returnedByUserId: userId,
      );

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

  /// Called by [_PartialReturnSection] after a successful partial return.
  void _onPartialReturnDone() {
    ref.invalidate(invoiceDetailProvider(widget.invoiceId));
    ref.invalidate(_partialReturnQtysProvider(widget.invoiceId));
    ref.invalidate(invoiceHistoryPageProvider);
    ref.invalidate(productsNotifierProvider);
    ref.invalidate(posProductsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final canFullRefund =
        ref.watch(permissionProvider(PermissionKeys.posFullRefund));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 820),
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
                  onPartialReturnDone: _onPartialReturnDone,
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

// ---------------------------------------------------------------------------
// Main body
// ---------------------------------------------------------------------------

class _InvoiceDetailBody extends StatelessWidget {
  const _InvoiceDetailBody({
    required this.data,
    required this.canFullRefund,
    required this.returning,
    required this.onClose,
    required this.onReprint,
    required this.onFullReturn,
    required this.onPartialReturnDone,
  });

  final InvoiceDetailData data;
  final bool canFullRefund;
  final bool returning;
  final VoidCallback onClose;
  final VoidCallback onReprint;
  final VoidCallback onFullReturn;
  final VoidCallback onPartialReturnDone;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        );
    final h = data.header;
    final statusAr = invoiceLifecycleLabelAr(h.invoiceStatus);
    final hasAnyReturn = invoiceHasAnyReturn(h.invoiceStatus);
    // Full return is blocked once any partial return exists.
    final canReturn = canFullRefund && !hasAnyReturn && !returning;
    final canPartialReturn =
        canFullRefund && invoiceCanBeReturned(h.invoiceStatus) && !returning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header bar ───────────────────────────────────────────────────
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
                        label: Text('مرتجعة بالكامل'),
                        backgroundColor: AppColors.warningLight,
                        side: BorderSide(color: AppColors.warning),
                        labelStyle: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    else if (hasAnyReturn)
                      const Chip(
                        label: Text('مرتجع جزئياً'),
                        backgroundColor: AppColors.infoLight,
                        side: BorderSide(color: AppColors.info),
                        labelStyle: TextStyle(
                          color: AppColors.info,
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

        // ── Scrollable content ────────────────────────────────────────────
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
                        DataColumn(label: Text('الصنف', style: titleStyle)),
                        DataColumn(label: Text('الكمية', style: titleStyle)),
                        DataColumn(label: Text('سعر الوحدة', style: titleStyle)),
                        DataColumn(label: Text('الخصم', style: titleStyle)),
                        DataColumn(label: Text('الإجمالي', style: titleStyle)),
                      ],
                      rows: [
                        for (final l in data.lines)
                          DataRow(
                            cells: [
                              DataCell(Text(l.productName)),
                              DataCell(Text(
                                InvoiceDetailsDialog._money.format(l.quantity),
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.unitPrice)} د.ع',
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.discount)} د.ع',
                              )),
                              DataCell(Text(
                                '${InvoiceDetailsDialog._money.format(l.lineTotal)} د.ع',
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

                  // ── Full-return metadata ─────────────────────────────
                  if (data.isReturned) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(text: 'بيانات الإرجاع', style: titleStyle),
                    const SizedBox(height: 8),
                    _ReturnMetadataCard(data: data),
                  ],

                  // ── Partial return section ───────────────────────────
                  if (invoiceCanBeReturned(h.invoiceStatus)) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(text: 'الإرجاع الجزئي', style: titleStyle),
                    const SizedBox(height: 8),
                    _PartialReturnSection(
                      invoiceId: h.id,
                      lines: data.lines,
                      canPartialReturn: canPartialReturn,
                      onDone: onPartialReturnDone,
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),

        // ── Footer buttons ────────────────────────────────────────────────
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
                      ? 'هذه الفاتورة مرتجعة بالكامل'
                      : hasAnyReturn
                          ? 'لا يمكن الإرجاع الكامل بعد تسجيل إرجاع جزئي'
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

// ---------------------------------------------------------------------------
// Partial return section
// ---------------------------------------------------------------------------

class _PartialReturnSection extends ConsumerStatefulWidget {
  const _PartialReturnSection({
    required this.invoiceId,
    required this.lines,
    required this.canPartialReturn,
    required this.onDone,
  });

  final int invoiceId;
  final List<InvoiceDetailLine> lines;
  final bool canPartialReturn;
  final VoidCallback onDone;

  @override
  ConsumerState<_PartialReturnSection> createState() =>
      _PartialReturnSectionState();
}

class _PartialReturnSectionState extends ConsumerState<_PartialReturnSection> {
  final Map<int, TextEditingController> _controllers = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final line in widget.lines) {
      _controllers[line.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qtysAsync = ref.watch(_partialReturnQtysProvider(widget.invoiceId));

    return qtysAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'تعذر تحميل بيانات الإرجاع: $e',
          style: const TextStyle(color: AppColors.error),
        ),
      ),
      data: (alreadyReturned) =>
          _buildBody(context, alreadyReturned),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Map<int, double> alreadyReturned,
  ) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Column header row
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('الصنف', style: labelStyle),
                ),
                _colHeader('المباع', labelStyle),
                _colHeader('المرتجع', labelStyle),
                _colHeader('المتاح', labelStyle),
                const SizedBox(width: 8),
                SizedBox(
                  width: 108,
                  child: Text(
                    'كمية الإرجاع',
                    style: labelStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const Divider(height: 14),

            // Item rows
            for (final line in widget.lines)
              _LineRow(
                line: line,
                alreadyReturned: alreadyReturned[line.id] ?? 0.0,
                controller: _controllers[line.id]!,
                canInput: widget.canPartialReturn && !_submitting,
              ),

            const SizedBox(height: 16),

            if (widget.canPartialReturn)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _submit(context, alreadyReturned),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.assignment_return_rounded, size: 18),
                  label: const Text('تنفيذ الإرجاع الجزئي'),
                ),
              )
            else
              Text(
                'ليس لديك صلاحية تنفيذ الإرجاع الجزئي.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _colHeader(String text, TextStyle? style) {
    return SizedBox(
      width: 72,
      child: Text(text, style: style, textAlign: TextAlign.end),
    );
  }

  Future<void> _submit(
    BuildContext context,
    Map<int, double> alreadyReturned,
  ) async {
    final m = NumberFormat('#,##0.##');
    final lines = <PartialReturnLine>[];

    for (final line in widget.lines) {
      final text = _controllers[line.id]?.text.trim() ?? '';
      if (text.isEmpty || text == '0') continue;

      final qty = double.tryParse(text);
      if (qty == null || qty <= 0) {
        _showError(context, 'كمية غير صحيحة للصنف: ${line.productName}');
        return;
      }

      final available =
          (line.quantity - (alreadyReturned[line.id] ?? 0.0))
              .clamp(0.0, double.infinity);

      if (qty > available + 0.0001) {
        _showError(
          context,
          'كمية الإرجاع (${m.format(qty)}) تتجاوز المتاح (${m.format(available)}) للصنف: ${line.productName}',
        );
        return;
      }

      lines.add(PartialReturnLine(
        saleItemId: line.id,
        productId: line.productId,
        quantity: qty,
        unitPrice: line.unitPrice,
        unitCost: line.unitCost,
      ));
    }

    if (lines.isEmpty) {
      _showError(context, 'أدخل كمية إرجاع لصنف واحد على الأقل.');
      return;
    }

    // Show note dialog
    final note = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PartialReturnNoteDialog(),
    );
    if (note == null) return;
    if (!context.mounted) return;

    final userId = ref.read(authProvider).valueOrNull?.user?.id;
    if (userId == null) {
      if (!context.mounted) return;
      _showError(context, 'تعذر التحقق من هوية المستخدم. الرجاء تسجيل الدخول مجدداً.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(partialReturnServiceProvider).processPartialReturn(
            saleInvoiceId: widget.invoiceId,
            lines: lines,
            returnedByUserId: userId,
            note: note,
          );

      // Clear all inputs
      for (final c in _controllers.values) {
        c.clear();
      }

      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('تم تنفيذ الإرجاع الجزئي بنجاح واستعادة المخزون.'),
          backgroundColor: AppColors.success,
        ),
      );

      // Tell parent dialog to invalidate & reload
      widget.onDone();
    } on StateError catch (e) {
      if (!context.mounted) return;
      _showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'تعذر تنفيذ الإرجاع الجزئي: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

// ---------------------------------------------------------------------------
// Single item row inside the partial-return section
// ---------------------------------------------------------------------------

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.alreadyReturned,
    required this.controller,
    required this.canInput,
  });

  final InvoiceDetailLine line;
  final double alreadyReturned;
  final TextEditingController controller;
  final bool canInput;

  @override
  Widget build(BuildContext context) {
    final m = NumberFormat('#,##0.##');
    final available =
        (line.quantity - alreadyReturned).clamp(0.0, double.infinity);
    final isFullyReturned = available <= 0.0001;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Product name + badge
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    line.productName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isFullyReturned
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      decoration: isFullyReturned
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (isFullyReturned) ...[
                  const SizedBox(width: 6),
                  _badge('مرتجع', AppColors.warning, AppColors.warningLight),
                ],
              ],
            ),
          ),

          // Sold qty
          SizedBox(
            width: 72,
            child: Text(
              m.format(line.quantity),
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),

          // Already returned
          SizedBox(
            width: 72,
            child: Text(
              alreadyReturned > 0 ? m.format(alreadyReturned) : '—',
              textAlign: TextAlign.end,
              style: alreadyReturned > 0
                  ? const TextStyle(
                      color: AppColors.warning, fontWeight: FontWeight.w600)
                  : const TextStyle(color: AppColors.textSecondary),
            ),
          ),

          // Available qty
          SizedBox(
            width: 72,
            child: Text(
              isFullyReturned ? '—' : m.format(available),
              textAlign: TextAlign.end,
              style: TextStyle(
                color: isFullyReturned
                    ? AppColors.textSecondary
                    : AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Return qty input
          SizedBox(
            width: 108,
            child: isFullyReturned
                ? const SizedBox.shrink()
                : canInput
                    ? TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: InputDecoration(
                          hintText: '0',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, style: style);
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
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _HeaderCol1(data: data)),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _HeaderCol2(data: data, statusAr: statusAr),
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
    final Color? statusColor = data.isReturned
        ? AppColors.warning
        : invoiceHasAnyReturn(h.invoiceStatus)
            ? AppColors.info
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('طريقة الدفع', invoicePaymentLabelAr(h.paymentMethod)),
        _kv(
          'الحالة',
          statusAr,
          valueStyle: statusColor != null
              ? TextStyle(color: statusColor, fontWeight: FontWeight.w800)
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
                const TextStyle(color: AppColors.textPrimary),
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

// ---------------------------------------------------------------------------
// Full-return metadata card
// ---------------------------------------------------------------------------

class _ReturnMetadataCard extends StatelessWidget {
  const _ReturnMetadataCard({required this.data});

  final InvoiceDetailData data;

  static final _df = DateFormat('yyyy/MM/dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final meta = data.returnMetadata;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warningLight.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_return_rounded,
                    size: 18, color: AppColors.warning),
                SizedBox(width: 8),
                Text(
                  'هذه الفاتورة مرتجعة بالكامل',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (meta?.returnDate != null)
              _metaRow('تاريخ الإرجاع', _df.format(meta!.returnDate!)),
            if (meta?.returnedByName != null &&
                meta!.returnedByName!.trim().isNotEmpty)
              _metaRow('تم بواسطة', meta.returnedByName!),
            if (meta?.returnNote != null && meta!.returnNote!.trim().isNotEmpty)
              _metaRow('سبب الإرجاع', meta.returnNote!),
            if (meta == null || !meta.hasData)
              const Text(
                'لا تتوفر بيانات إضافية لهذا الإرجاع.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-return confirmation dialog (unchanged)
// ---------------------------------------------------------------------------

class _ReturnConfirmDialog extends StatefulWidget {
  @override
  State<_ReturnConfirmDialog> createState() => _ReturnConfirmDialogState();
}

class _ReturnConfirmDialogState extends State<_ReturnConfirmDialog> {
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تأكيد إرجاع الفاتورة'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('سيتم تنفيذ الإرجاع الكامل لهذه الفاتورة وفق التالي:'),
                const SizedBox(height: 12),
                const Text('• إعادة جميع الكميات المباعة إلى المخزون.'),
                const SizedBox(height: 6),
                const Text('• تسجيل حركات إرجاع وترحيل صحيح للمخزون.'),
                const SizedBox(height: 6),
                const Text('• وسم الفاتورة كمرتجعة — لا يمكن تكرار الإرجاع.'),
                const SizedBox(height: 6),
                const Text(
                  'لن يتم حذف الفاتورة الأصلية؛ تبقى محفوظة للمراجعة المحاسبية.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'سبب / ملاحظة الإرجاع *',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  textDirection: TextDirection.rtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'أدخل سبب الإرجاع...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'هذا الحقل مطلوب';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.of(context).pop(_noteController.text.trim());
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.textPrimary,
            ),
            child: const Text('تأكيد الإرجاع'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Partial-return note dialog
// ---------------------------------------------------------------------------

class _PartialReturnNoteDialog extends StatefulWidget {
  @override
  State<_PartialReturnNoteDialog> createState() =>
      _PartialReturnNoteDialogState();
}

class _PartialReturnNoteDialogState extends State<_PartialReturnNoteDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assignment_return_rounded,
                size: 20, color: AppColors.info),
            SizedBox(width: 8),
            Text('سبب الإرجاع الجزئي'),
          ],
        ),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'أدخل سبب الإرجاع...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: AppColors.inputFill,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.of(context).pop(_controller.text.trim());
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }
}
