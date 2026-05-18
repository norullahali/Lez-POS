// lib/features/products/screens/widgets/product_profile_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/movement_types.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_row.dart';
import '../../providers/stock_movement_history_provider.dart';

// ---------------------------------------------------------------------------
// Entry-point
// ---------------------------------------------------------------------------

void showProductProfileDialog(BuildContext context, ProductModel product) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ProductProfileDialog(product: product),
  );
}

// ---------------------------------------------------------------------------
// Main Dialog
// ---------------------------------------------------------------------------

class ProductProfileDialog extends StatelessWidget {
  const ProductProfileDialog({super.key, required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              _DialogHeader(product: product),
              const _DialogTabBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _ProductOverviewTab(product: product),
                    _StockMovementHistoryTab(productId: product.id!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_rounded, color: Colors.white70, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'اغلاق',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TabBar
// ---------------------------------------------------------------------------

class _DialogTabBar extends StatelessWidget {
  const _DialogTabBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: const TabBar(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: AppColors.accentLight,
        indicatorWeight: 3,
        tabs: [
          Tab(icon: Icon(Icons.info_outline_rounded, size: 18), text: 'معلومات المنتج'),
          Tab(icon: Icon(Icons.swap_vert_rounded, size: 18), text: 'حركة المخزون'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Product Overview
// ---------------------------------------------------------------------------

class _ProductOverviewTab extends StatelessWidget {
  const _ProductOverviewTab({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final isLow =
        product.safeStock <= product.minStock && product.minStock > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('بيانات المنتج'),
          const SizedBox(height: 12),
          _InfoGrid(items: [
            _InfoItem('اسم المنتج', product.name),
            _InfoItem('الباركود', product.barcode.isEmpty ? '-' : product.barcode),
            _InfoItem('الفئة', product.categoryName ?? '-'),
            _InfoItem('المورد', product.supplierName ?? '-'),
            _InfoItem('وحدة القياس', product.unit),
            _InfoItem('تتبع الانتهاء', product.trackExpiry ? 'نعم' : 'لا'),
            _InfoItem('الحالة', product.isActive ? 'نشط' : 'غير نشط'),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('التسعير'),
          const SizedBox(height: 12),
          _InfoGrid(items: [
            _InfoItem('سعر الشراء', '${product.costPrice.toStringAsFixed(0)} د.ع'),
            _InfoItem('سعر البيع', '${product.sellPrice.toStringAsFixed(0)} د.ع'),
            _InfoItem('سعر الجملة', '${product.wholesalePrice.toStringAsFixed(0)} د.ع'),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('المخزون'),
          const SizedBox(height: 12),
          _InfoGrid(items: [
            _InfoItem(
              'المخزون الحالي',
              product.safeStock.toStringAsFixed(2),
              valueColor: isLow ? AppColors.error : AppColors.success,
              valueBg: isLow ? AppColors.errorLight : AppColors.successLight,
            ),
            _InfoItem('الحد الأدنى', product.minStock.toStringAsFixed(2)),
          ]),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 18, color: AppColors.primary,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});

  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: items,
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem(
    this.label,
    this.value, {
    this.valueColor,
    this.valueBg,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? valueBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Container(
            padding: valueBg != null
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                : EdgeInsets.zero,
            decoration: valueBg != null
                ? BoxDecoration(
                    color: valueBg,
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Stock Movement History
// ---------------------------------------------------------------------------

class _StockMovementHistoryTab extends ConsumerStatefulWidget {
  const _StockMovementHistoryTab({required this.productId});

  final int productId;

  @override
  ConsumerState<_StockMovementHistoryTab> createState() =>
      _StockMovementHistoryTabState();
}

class _StockMovementHistoryTabState
    extends ConsumerState<_StockMovementHistoryTab> {
  static const _pageSize = 25;

  late StockMovementQuery _query;

  // Filter state
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _query = StockMovementQuery(
      productId: widget.productId,
      pageSize: _pageSize,
    );
  }

  void _applyFilters() {
    setState(() {
      _query = StockMovementQuery(
        productId: widget.productId,
        page: 0,
        pageSize: _pageSize,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        movementType: _selectedType,
      );
    });
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _selectedType = null;
      _query = StockMovementQuery(
        productId: widget.productId,
        pageSize: _pageSize,
      );
    });
  }

  void _goToPage(int page) {
    setState(() {
      _query = _query.copyWith(page: page);
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? (_dateFrom ?? DateTime.now()) : (_dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(stockMovementHistoryProvider(_query));

    return Column(
      children: [
        _FiltersRow(
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          selectedType: _selectedType,
          onPickFrom: () => _pickDate(isFrom: true),
          onPickTo: () => _pickDate(isFrom: false),
          onTypeChanged: (v) => setState(() => _selectedType = v),
          onApply: _applyFilters,
          onClear: _clearFilters,
        ),
        const Divider(height: 1),
        Expanded(
          child: asyncData.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
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
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(
                        stockMovementHistoryProvider(_query)),
                  ),
                ],
              ),
            ),
            data: (page) => page.rows.isEmpty
                ? const _EmptyState()
                : Column(
                    children: [
                      Expanded(child: _MovementsTable(rows: page.rows)),
                      _PaginationBar(
                        page: page,
                        onPrev: page.hasPrevPage
                            ? () => _goToPage(page.page - 1)
                            : null,
                        onNext: page.hasNextPage
                            ? () => _goToPage(page.page + 1)
                            : null,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filters Row
// ---------------------------------------------------------------------------

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.dateFrom,
    required this.dateTo,
    required this.selectedType,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onTypeChanged,
    required this.onApply,
    required this.onClear,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? selectedType;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  static final _df = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        dateFrom != null || dateTo != null || selectedType != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surfaceVariant,
      child: Row(
        children: [
          // From date
          _DateChip(
            label: dateFrom != null ? 'من: ${_df.format(dateFrom!)}' : 'من تاريخ',
            icon: Icons.calendar_today_rounded,
            isSet: dateFrom != null,
            onTap: onPickFrom,
          ),
          const SizedBox(width: 8),
          // To date
          _DateChip(
            label: dateTo != null ? 'إلى: ${_df.format(dateTo!)}' : 'إلى تاريخ',
            icon: Icons.calendar_today_rounded,
            isSet: dateTo != null,
            onTap: onPickTo,
          ),
          const SizedBox(width: 12),
          // Movement type
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              initialValue: selectedType,
              decoration: InputDecoration(
                labelText: 'نوع الحركة',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: AppColors.surface,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('الكل')),
                ...StockMovementKind.all.map(
                  (k) => DropdownMenuItem<String?>(
                    value: k,
                    child: Text(StockMovementKind.labelAr(k),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              onChanged: onTypeChanged,
            ),
          ),
          const SizedBox(width: 10),
          // Apply
          FilledButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('تطبيق'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('مسح'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.icon,
    required this.isSet,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSet ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSet ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isSet ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSet ? AppColors.primary : AppColors.textSecondary,
                fontWeight:
                    isSet ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movements Table
// ---------------------------------------------------------------------------

class _MovementsTable extends StatelessWidget {
  const _MovementsTable({required this.rows});

  final List<StockMovementRow> rows;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            headingRowHeight: 42,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
            border: TableBorder.all(
              color: AppColors.divider,
              width: 1,
              borderRadius: BorderRadius.zero,
            ),
            columns: const [
              DataColumn(label: _HeadCell('التاريخ')),
              DataColumn(label: _HeadCell('نوع الحركة')),
              DataColumn(label: _HeadCell('التغيير'), numeric: true),
              DataColumn(label: _HeadCell('قبل'), numeric: true),
              DataColumn(label: _HeadCell('بعد'), numeric: true),
              DataColumn(label: _HeadCell('المرجع')),
              DataColumn(label: _HeadCell('المستخدم')),
              DataColumn(label: _HeadCell('ملاحظة')),
            ],
            rows: rows.map(_buildRow).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(StockMovementRow r) {
    final isPositive = r.quantityChange >= 0;
    final changeColor = isPositive ? AppColors.success : AppColors.error;
    final changeBg =
        isPositive ? AppColors.successLight : AppColors.errorLight;

    return DataRow(cells: [
      // التاريخ
      DataCell(_DateCell(r.createdAt)),
      // نوع الحركة
      DataCell(_TypeBadge(r.movementType)),
      // التغيير
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: changeBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${isPositive ? '+' : ''}${r.quantityChange.toStringAsFixed(2)}',
            style: TextStyle(
              color: changeColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
      // قبل
      DataCell(Text(r.stockBefore.toStringAsFixed(2),
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
      // بعد
      DataCell(Text(r.stockAfter.toStringAsFixed(2),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      // المرجع
      DataCell(_ReferenceCell(
          referenceType: r.referenceType, referenceId: r.referenceId)),
      // المستخدم
      DataCell(Text(r.userName ?? '-',
          style: const TextStyle(fontSize: 12))),
      // ملاحظة
      DataCell(
        SizedBox(
          width: 140,
          child: Text(
            r.note ?? '-',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Table Cell Helpers
// ---------------------------------------------------------------------------

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.textPrimary));
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell(this.dt);

  final DateTime dt;
  static final _df = DateFormat('dd/MM/yyyy');
  static final _tf = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_df.format(dt),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(_tf.format(dt),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.kind);

  final String kind;

  static Color _bg(String k) => switch (k) {
        StockMovementKind.sale => AppColors.errorLight,
        StockMovementKind.purchase => AppColors.successLight,
        StockMovementKind.fullReturn => AppColors.infoLight,
        StockMovementKind.partialReturn => AppColors.infoLight,
        StockMovementKind.openingStock => AppColors.primarySurface,
        StockMovementKind.manualAdjustment => AppColors.warningLight,
        _ => AppColors.surfaceVariant,
      };

  static Color _fg(String k) => switch (k) {
        StockMovementKind.sale => AppColors.error,
        StockMovementKind.purchase => AppColors.success,
        StockMovementKind.fullReturn => AppColors.info,
        StockMovementKind.partialReturn => AppColors.info,
        StockMovementKind.openingStock => AppColors.primary,
        StockMovementKind.manualAdjustment => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _bg(kind),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        StockMovementKind.labelAr(kind),
        style: TextStyle(
          color: _fg(kind),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ReferenceCell extends StatelessWidget {
  const _ReferenceCell({this.referenceType, this.referenceId});

  final String? referenceType;
  final int? referenceId;

  String get _label {
    if (referenceId == null) return '-';
    final id = referenceId!;
    return switch (referenceType) {
      'sale_items' => 'فاتورة بيع #$id',
      'purchase_items' => 'فاتورة شراء #$id',
      'customer_return_items' => 'مرتجع كامل #$id',
      'sale_item_returns' => 'مرتجع جزئي #$id',
      'supplier_return_items' => 'مرتجع مورد #$id',
      'stock_adjustments' => 'تسوية #$id',
      _ => referenceType != null ? '$referenceType #$id' : '#$id',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (referenceId == null) {
      return const Text('-',
          style: TextStyle(color: AppColors.textHint, fontSize: 12));
    }
    return Text(
      _label,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.info,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination Bar
// ---------------------------------------------------------------------------

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.onPrev,
    required this.onNext,
  });

  final StockMovementPage page;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final from = page.totalCount == 0 ? 0 : page.page * page.pageSize + 1;
    final to = ((page.page + 1) * page.pageSize).clamp(0, page.totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Text(
            'عرض $from - $to من أصل ${page.totalCount} حركة',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            'صفحة ${page.page + 1} من ${page.totalPages == 0 ? 1 : page.totalPages}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onPrev,
            tooltip: 'السابق',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onNext,
            tooltip: 'التالي',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_vert_rounded, size: 56, color: AppColors.textHint),
          SizedBox(height: 12),
          Text(
            'لا توجد حركات مخزنية',
            style: TextStyle(color: AppColors.textHint, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'حاول تغيير الفلاتر أو اختر فترة زمنية مختلفة',
            style: TextStyle(
                color: AppColors.textHint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
