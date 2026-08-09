// lib/features/returns/screens/widgets/create_supplier_return_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../models/supplier_return_draft_models.dart';
import '../../providers/supplier_return_draft_provider.dart';

Future<void> showCreateSupplierReturnDialog(
  BuildContext context,
  WidgetRef ref,
) {
  ref.read(supplierReturnDraftProvider.notifier).reset();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const CreateSupplierReturnDialog(),
  ).whenComplete(() {
    ref.read(supplierReturnDraftProvider.notifier).reset();
  });
}

class CreateSupplierReturnDialog extends ConsumerStatefulWidget {
  const CreateSupplierReturnDialog({super.key});

  @override
  ConsumerState<CreateSupplierReturnDialog> createState() =>
      _CreateSupplierReturnDialogState();
}

class _CreateSupplierReturnDialogState
    extends ConsumerState<CreateSupplierReturnDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(supplierReturnDraftProvider.notifier).loadPurchases();
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(supplierReturnDraftProvider);
    final dateFmt = DateFormat('yyyy/MM/dd');

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: draft.step == SupplierReturnDraftStep.selectPurchase
                  ? 'اختيار فاتورة الشراء'
                  : 'إعداد مرتجع المورد',
              onClose: () => Navigator.of(context).pop(),
            ),
            if (draft.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  draft.errorMessage!,
                  style: const TextStyle(color: AppColors.error),
                  textDirection: TextDirection.rtl,
                ),
              ),
            Expanded(
              child: draft.step == SupplierReturnDraftStep.selectPurchase
                  ? _PurchaseSelector(dateFmt: dateFmt)
                  : _DraftLinesEditor(dateFmt: dateFmt),
            ),
            _Footer(onClose: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _PurchaseSelector extends ConsumerWidget {
  const _PurchaseSelector({required this.dateFmt});

  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(supplierReturnDraftProvider);
    final notifier = ref.read(supplierReturnDraftProvider.notifier);

    if (draft.loadingPurchases) {
      return const Center(child: CircularProgressIndicator());
    }

    if (draft.purchases.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد فواتير مشتريات متاحة للإرجاع',
          style: TextStyle(color: AppColors.textHint),
          textDirection: TextDirection.rtl,
        ),
      );
    }

    final filtered = draft.filteredPurchases;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'بحث برقم الفاتورة أو اسم المورد',
              border: OutlineInputBorder(),
            ),
            textDirection: TextDirection.rtl,
            onChanged: notifier.setSearchQuery,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد نتائج مطابقة',
                      style: TextStyle(color: AppColors.textHint),
                      textDirection: TextDirection.rtl,
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        onTap: () => notifier.selectPurchase(p),
                        title: Text(
                          'فاتورة ${p.displayInvoiceNumber}',
                          textDirection: TextDirection.rtl,
                        ),
                        subtitle: Text(
                          'المورد: ${p.supplierName} • ${dateFmt.format(p.purchaseDate)} • ${p.totalAmount.toStringAsFixed(2)}',
                          textDirection: TextDirection.rtl,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraftLinesEditor extends ConsumerWidget {
  const _DraftLinesEditor({required this.dateFmt});

  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(supplierReturnDraftProvider);
    final notifier = ref.read(supplierReturnDraftProvider.notifier);
    final purchase = draft.selectedPurchase;

    if (draft.loadingLines) {
      return const Center(child: CircularProgressIndicator());
    }

    if (purchase == null) {
      return const Center(child: Text('لم يتم اختيار فاتورة'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: notifier.backToPurchaseSelection,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('تغيير الفاتورة'),
              ),
              const Spacer(),
              Text(
                '${purchase.supplierName} • ${purchase.displayInvoiceNumber} • ${dateFmt.format(purchase.purchaseDate)}',
                style: const TextStyle(color: AppColors.textSecondary),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
          if (!draft.hasReturnableLines)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'لا توجد كميات متبقية قابلة للإرجاع في هذه الفاتورة',
                textDirection: TextDirection.rtl,
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: _LinesTable(draft: draft),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'سبب الإرجاع (اختياري)',
              border: OutlineInputBorder(),
            ),
            textDirection: TextDirection.rtl,
            onChanged: notifier.setReason,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختياري)',
              border: OutlineInputBorder(),
            ),
            textDirection: TextDirection.rtl,
            onChanged: notifier.setNotes,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'إجمالي المسودة: ${draft.draftTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
                textDirection: TextDirection.rtl,
              ),
              const Spacer(),
              Tooltip(
                message: 'سيتم تفعيل الحفظ في المرحلة القادمة (SR.3.2)',
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ المرتجع'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinesTable extends ConsumerStatefulWidget {
  const _LinesTable({required this.draft});

  final SupplierReturnDraftState draft;

  @override
  ConsumerState<_LinesTable> createState() => _LinesTableState();
}

class _LinesTableState extends ConsumerState<_LinesTable> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(SupplierReturnDraftLine line) {
    return _controllers.putIfAbsent(
      line.purchaseItemId,
      () => TextEditingController(
        text: line.selectedReturnQty > 0
            ? _formatQty(line.selectedReturnQty)
            : '',
      ),
    );
  }

  String _formatQty(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(supplierReturnDraftProvider.notifier);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(flex: 3, child: Text('المنتج', style: labelStyle)),
                _col('الكمية المشتراة', labelStyle),
                _col('المرتجع سابقاً', labelStyle),
                _col('المتاح للإرجاع', labelStyle),
                _col('تكلفة الوحدة', labelStyle),
                SizedBox(
                  width: 96,
                  child: Text('كمية الإرجاع',
                      style: labelStyle, textAlign: TextAlign.center),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final line in widget.draft.lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(line.productName,
                        textDirection: TextDirection.rtl),
                  ),
                  _cell(_formatQty(line.purchasedQty)),
                  _cell(_formatQty(line.alreadyReturnedQty)),
                  _cell(_formatQty(line.returnableQty)),
                  _cell(line.unitCost.toStringAsFixed(2)),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _controllerFor(line),
                      enabled: line.returnableQty > 0,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        errorText: widget.draft.lineErrors[line.purchaseItemId],
                        errorMaxLines: 2,
                      ),
                      onChanged: (v) {
                        final qty = double.tryParse(v.trim()) ?? 0;
                        notifier.setLineQuantity(line.purchaseItemId, qty);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _col(String text, TextStyle? style) {
    return Expanded(
        child: Text(text, style: style, textAlign: TextAlign.center));
  }

  Widget _cell(String text) {
    return Expanded(child: Text(text, textAlign: TextAlign.center));
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(onPressed: onClose, child: const Text('إغلاق')),
      ),
    );
  }
}
