// lib/features/returns/screens/widgets/smart_return_lookup_dialog.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/constants/invoice_lifecycle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../invoices/widgets/invoice_details_dialog.dart';
import '../../models/smart_return_result.dart';
import '../../providers/smart_return_lookup_provider.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void showSmartReturnLookupDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const SmartReturnLookupDialog(),
  );
}

// ---------------------------------------------------------------------------
// Main Dialog
// ---------------------------------------------------------------------------

class SmartReturnLookupDialog extends ConsumerStatefulWidget {
  const SmartReturnLookupDialog({super.key});

  @override
  ConsumerState<SmartReturnLookupDialog> createState() =>
      _SmartReturnLookupDialogState();
}

class _SmartReturnLookupDialogState
    extends ConsumerState<SmartReturnLookupDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // The live query sent to the provider (debounced)
  String _liveQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      if (mounted) {
        setState(() => _liveQuery = _controller.text.trim());
      }
    });
  }

  void _clearSearch() {
    _controller.clear();
    setState(() => _liveQuery = '');
    _focusNode.requestFocus();
  }

  void _openInvoice(BuildContext context, int invoiceId) {
    // Open the existing partial-return-capable dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoiceDetailsDialog(invoiceId: invoiceId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 680),
        child: Column(
          children: [
            _Header(onClose: () => Navigator.of(context).pop()),
            _SearchBar(
              controller: _controller,
              focusNode: _focusNode,
              onClear: _clearSearch,
            ),
            const Divider(height: 1),
            Expanded(child: _ResultsArea(query: _liveQuery, onSelect: _openInvoice)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Colors.white70, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'البحث الذكي للإرجاع',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'ابحث بالباركود أو اسم المنتج أو رقم الفاتورة أو هاتف العميل',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: onClose,
            tooltip: 'اغلاق',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'باركود / اسم المنتج / رقم الفاتورة / هاتف العميل...',
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                    onPressed: onClear,
                    tooltip: 'مسح',
                  ),
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results Area
// ---------------------------------------------------------------------------

class _ResultsArea extends ConsumerWidget {
  const _ResultsArea({required this.query, required this.onSelect});

  final String query;
  final void Function(BuildContext context, int invoiceId) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.length < 2) {
      return const _Placeholder();
    }

    final asyncResult = ref.watch(smartReturnLookupProvider(query));

    return asyncResult.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 8),
            Text('خطأ: $e',
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center),
          ],
        ),
      ),
      data: (results) => results.isEmpty
          ? _NoResults(query: query)
          : _ResultsTable(results: results, onSelect: onSelect),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder (before typing)
// ---------------------------------------------------------------------------

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded,
                size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'ابدأ الكتابة للبحث',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'يمكنك البحث بالباركود، اسم المنتج،\nرقم الفاتورة، أو رقم هاتف العميل',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.6),
          ),
          const SizedBox(height: 24),
          const _HintChips(),
        ],
      ),
    );
  }
}

class _HintChips extends StatelessWidget {
  const _HintChips();
  @override
  Widget build(BuildContext context) {
    const hints = [
      (Icons.qr_code_rounded,      'باركود المنتج'),
      (Icons.inventory_2_outlined,  'اسم المنتج'),
      (Icons.receipt_long_outlined, 'رقم الفاتورة'),
      (Icons.phone_outlined,        'هاتف العميل'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: hints
          .map((h) => Chip(
                avatar: Icon(h.$1, size: 14, color: AppColors.primary),
                label: Text(h.$2,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.primary)),
                backgroundColor: AppColors.primarySurface,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// No Results
// ---------------------------------------------------------------------------

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.find_in_page_outlined,
              size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'لا توجد نتائج لـ "$query"',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'تأكد من الباركود أو جرب نوعاً آخر من البحث',
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results Table
// ---------------------------------------------------------------------------

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.results, required this.onSelect});

  final List<SmartReturnResult> results;
  final void Function(BuildContext context, int invoiceId) onSelect;

  static final _df = DateFormat('dd/MM/yyyy HH:mm');
  static final _qty = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Count bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.surfaceVariant,
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'تم العثور على ${results.length} نتيجة',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Table
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              itemCount: results.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (ctx, i) =>
                  _ResultRow(r: results[i], df: _df, qty: _qty,
                      onTap: () => onSelect(ctx, results[i].invoiceId)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single Result Row
// ---------------------------------------------------------------------------

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.r,
    required this.df,
    required this.qty,
    required this.onTap,
  });

  final SmartReturnResult r;
  final DateFormat df;
  final NumberFormat qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = r.remainingReturnable;
    final hasReturn = r.alreadyReturned > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Product icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 12),

            // Left section: product + invoice info
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(
                    r.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Barcode if present
                  if (r.barcode.isNotEmpty)
                    Text(
                      r.barcode,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textHint),
                    ),
                  const SizedBox(height: 4),
                  // Invoice row
                  Row(
                    children: [
                      const Icon(Icons.receipt_outlined,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        r.invoiceNumber,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.info,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.calendar_today_outlined,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        df.format(r.saleDate),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Middle section: customer + cashier
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetaLine(Icons.person_outline_rounded, r.customerName),
                  const SizedBox(height: 4),
                  _MetaLine(Icons.badge_outlined, r.cashierName),
                ],
              ),
            ),

            // Right section: quantities
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _QtyChip(
                    label: 'مباع',
                    value: qty.format(r.soldQuantity),
                    color: AppColors.textSecondary,
                    bg: AppColors.surfaceVariant,
                  ),
                  if (hasReturn) ...[
                    const SizedBox(height: 4),
                    _QtyChip(
                      label: 'مرتجع',
                      value: qty.format(r.alreadyReturned),
                      color: AppColors.warning,
                      bg: AppColors.warningLight,
                    ),
                  ],
                  const SizedBox(height: 4),
                  _QtyChip(
                    label: 'متاح للإرجاع',
                    value: qty.format(remaining),
                    color: AppColors.success,
                    bg: AppColors.successLight,
                    bold: true,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Action button
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.assignment_return_rounded, size: 16),
              label: const Text('فتح الفاتورة'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),

            // Status badge (partially returned)
            if (hasReturn) ...[
              const SizedBox(width: 8),
              _statusBadge(r.invoiceStatus),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final label = invoiceLifecycleLabelAr(status);
    final isPartial = status == InvoiceLifecycleStatus.partiallyReturned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPartial ? AppColors.infoLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPartial ? AppColors.info : AppColors.warning,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _QtyChip extends StatelessWidget {
  const _QtyChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color color;
  final Color bg;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
