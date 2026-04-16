// lib/features/pricing/screens/pricing_rule_form.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../categories/models/category_model.dart';
import '../../categories/providers/categories_provider.dart';
import '../../products/models/product_model.dart';
import '../../products/providers/products_provider.dart';
import '../../../../core/utils/number_parser.dart';
import '../models/pricing_rule_model.dart';

class PricingRuleForm extends ConsumerStatefulWidget {
  final PricingRuleModel? editRule;
  const PricingRuleForm({super.key, this.editRule});

  @override
  ConsumerState<PricingRuleForm> createState() => _PricingRuleFormState();
}

class _PricingRuleFormState extends ConsumerState<PricingRuleForm> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _isLoadingData = true;

  // ── Form state ─────────────────────────────────────────────────────────────
  late final _nameCtrl            = TextEditingController();
  late final _priorityCtrl        = TextEditingController(text: '0');
  late final _discPctCtrl         = TextEditingController(text: '0');
  late final _discAmtCtrl         = TextEditingController(text: '0');
  late final _specialPriceCtrl    = TextEditingController();
  late final _buyQtyCtrl          = TextEditingController(text: '2');
  late final _getQtyCtrl          = TextEditingController(text: '1');
  late final _minQtyCtrl          = TextEditingController(text: '0');
  late final _minTotalCtrl        = TextEditingController(text: '0');

  RuleType _ruleType     = RuleType.discountPercentage;
  bool     _isActive     = true;
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedProductId;
  String? _selectedProductName;
  int? _selectedCategoryId;
  String? _selectedCategoryName;

  List<CategoryModel> _categories = [];

  final _df = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    debugPrint('[PricingRuleForm] initState started');
    final r = widget.editRule;
    if (r != null) {
      _nameCtrl.text         = r.name;
      _priorityCtrl.text     = '${r.priority}';
      _ruleType              = r.ruleType;
      _isActive              = r.isActive;
      _startDate             = r.startDate;
      _endDate               = r.endDate;
      _selectedProductId     = r.productId;
      _selectedCategoryId    = r.categoryId;
      _discPctCtrl.text      = '${r.discountPercentage}';
      _discAmtCtrl.text      = '${r.discountAmount}';
      _specialPriceCtrl.text = r.specialPrice != null ? '${r.specialPrice}' : '';
      _buyQtyCtrl.text       = '${r.buyQuantity}';
      _getQtyCtrl.text       = '${r.getQuantity}';
      _minQtyCtrl.text       = '${r.minimumQuantity}';
      _minTotalCtrl.text     = '${r.minimumTotalPrice}';
    }
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      debugPrint('[PricingRuleForm] Fetching categories from DB');
      // Using repository directly instead of StreamProvider.future which can hang if unlistened
      _categories = await ref.read(categoriesRepositoryProvider).getAll();
      
      if (_selectedProductId != null) {
        debugPrint('[PricingRuleForm] Fetching product name for ID $_selectedProductId');
        final prod = await AppDatabase.instance.productsDao.getProductById(_selectedProductId!);
        _selectedProductName = prod?.name;
      }

      if (_selectedCategoryId != null) {
        debugPrint('[PricingRuleForm] Fetching category name for ID $_selectedCategoryId');
        final cat = await AppDatabase.instance.categoriesDao.getCategoryById(_selectedCategoryId!);
        _selectedCategoryName = cat?.name;
      }
    } catch (e, stack) {
      debugPrint('[PricingRuleForm] Error loading initial data: $e\n$stack');
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _priorityCtrl, _discPctCtrl, _discAmtCtrl,
      _specialPriceCtrl, _buyQtyCtrl, _getQtyCtrl, _minQtyCtrl, _minTotalCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    debugPrint('[PricingRuleForm] Saving rule...');
    try {
      final dao = AppDatabase.instance.pricingDao;
      final name       = _nameCtrl.text.trim();
      final priority   = _priorityCtrl.text.tryParseArabicInt() ?? 0;
      final discPct    = _discPctCtrl.text.tryParseArabicDouble() ?? 0;
      final discAmt    = _discAmtCtrl.text.tryParseArabicDouble() ?? 0;
      final specPrice  = _specialPriceCtrl.text.tryParseArabicDouble();
      final buyQty     = _buyQtyCtrl.text.tryParseArabicInt() ?? 2;
      final getQty     = _getQtyCtrl.text.tryParseArabicInt() ?? 1;
      final minQty     = _minQtyCtrl.text.tryParseArabicDouble() ?? 0;
      final minTotal   = _minTotalCtrl.text.tryParseArabicDouble() ?? 0;

      if (widget.editRule == null) {
        await dao.saveRule(
          name: name, ruleType: _ruleType.dbValue, priority: priority,
          startDate: _startDate, endDate: _endDate, isActive: _isActive,
          productId: _selectedProductId, categoryId: _selectedCategoryId,
          minimumQuantity: minQty, minimumTotalPrice: minTotal,
          discountPercentage: discPct, discountAmount: discAmt,
          specialPrice: specPrice, buyQuantity: buyQty, getQuantity: getQty,
        );
      } else {
        await dao.updateRule(
          ruleId: widget.editRule!.id,
          name: name, ruleType: _ruleType.dbValue, priority: priority,
          startDate: _startDate, endDate: _endDate, isActive: _isActive,
          productId: _selectedProductId, categoryId: _selectedCategoryId,
          minimumQuantity: minQty, minimumTotalPrice: minTotal,
          discountPercentage: discPct, discountAmount: discAmt,
          specialPrice: specPrice, buyQuantity: buyQty, getQuantity: getQty,
        );
      }
      debugPrint('[PricingRuleForm] Save successful');
      if (mounted) Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrint('[PricingRuleForm] Save Error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editRule != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Title bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              Icon(isEdit ? Icons.edit_rounded : Icons.add_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Text(isEdit ? 'تعديل قاعدة تسعير' : 'قاعدة تسعير جديدة',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context, false),
              ),
            ]),
          ),

          // ── Scrollable body or loading spinner ──
          if (_isLoadingData)
            const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
          else
            Flexible(
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Name + Priority
                        _row([
                          _field(_nameCtrl, 'اسم القاعدة *', flex: 3,
                              validator: (v) => (v?.trim().isEmpty ?? true) ? 'مطلوب' : null),
                          _field(_priorityCtrl, 'الأولوية', flex: 1,
                              keyboardType: TextInputType.number,
                              hint: '0 = الأدنى'),
                        ]),
                        const SizedBox(height: 16),

                        // Rule type
                        _sectionTitle('نوع القاعدة'),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: RuleType.values.map((t) => ChoiceChip(
                            label: Text(t.displayName),
                            selected: _ruleType == t,
                            onSelected: (_) => setState(() => _ruleType = t),
                            selectedColor: AppColors.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: _ruleType == t ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: _ruleType == t ? FontWeight.w700 : FontWeight.w400,
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Action fields (driven by rule type)
                        _sectionTitle('الإجراء'),
                        _actionFields(),
                        const SizedBox(height: 16),

                        // Conditions
                        _sectionTitle('الشروط (اختياري)'),
                        _row([
                          _categoryPicker(),
                          _productPicker(),
                        ]),
                        const SizedBox(height: 8),
                        _row([
                          _field(_minQtyCtrl, 'الحد الأدنى للكمية',
                              keyboardType: TextInputType.number),
                          _field(_minTotalCtrl, 'الحد الأدنى للمبلغ',
                              keyboardType: TextInputType.number),
                        ]),
                        const SizedBox(height: 16),

                        // Dates + Active
                        _sectionTitle('التفعيل والمدة'),
                        _row([
                          _datePicker('تاريخ البدء', _startDate,
                              (d) => setState(() => _startDate = d)),
                          _datePicker('تاريخ الانتهاء', _endDate,
                              (d) => setState(() => _endDate = d)),
                        ]),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          title: const Text('تفعيل القاعدة فوراً'),
                          activeThumbColor: AppColors.success,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ]),
                    ),
                  ),

                  // ── Actions ──
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(isEdit ? 'حفظ التعديلات' : 'إضافة القاعدة'),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  // ── Action fields by rule type ────────────────────────────────────────────
  Widget _actionFields() {
    switch (_ruleType) {
      case RuleType.discountPercentage:
        return _row([
          _field(_discPctCtrl, 'نسبة الخصم (%)',
            hint: 'مثال: 10', keyboardType: TextInputType.number,
            validator: _pctValidator)
        ]);
      case RuleType.discountFixed:
        return _row([
          _field(_discAmtCtrl, 'مبلغ الخصم',
            hint: 'مثال: 500', keyboardType: TextInputType.number)
        ]);
      case RuleType.buyXGetY:
        return _row([
          _field(_buyQtyCtrl, 'اشترِ (كمية)',
              keyboardType: TextInputType.number),
          _field(_getQtyCtrl, 'مجاناً (كمية)',
              keyboardType: TextInputType.number),
        ]);
      case RuleType.wholesalePrice:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'سيتم تطبيق سعر الجملة من بيانات المنتج تلقائياً.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
      case RuleType.specialPrice:
        return _row([
          _field(_specialPriceCtrl, 'السعر الخاص',
            hint: 'مثال: 1500', keyboardType: TextInputType.number)
        ]);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _row(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .expand((w) => [w, const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    int flex = 1,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Expanded(
      flex: flex,
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: validator,
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 13)),
    );
  }

  Widget _datePicker(String label, DateTime? value, void Function(DateTime?) onPick) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          onPick(d);
        },
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: value != null
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () => onPick(null),
                  )
                : const Icon(Icons.calendar_today_rounded, size: 16),
          ),
          child: Text(
            value != null ? _df.format(value) : 'اختياري',
            style: TextStyle(
              color: value != null ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _productPicker() {
    return Expanded(
      child: InkWell(
        onTap: _pickProduct,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'المنتج (اختياري)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: _selectedProductId != null
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () => setState(() {
                      _selectedProductId = null;
                      _selectedProductName = null;
                    }),
                  )
                : const Icon(Icons.search_rounded, size: 16),
          ),
          child: Text(
            _selectedProductName ?? 'كل المنتجات',
            style: TextStyle(
              color: _selectedProductName != null ? AppColors.textPrimary : AppColors.textHint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _pickProduct() async {
    debugPrint('[PricingRuleForm] Opening ProductSearchDialog');
    final product = await showDialog<ProductModel>(
      context: context,
      builder: (_) => const _ProductSearchDialog(),
    );
    if (product != null && mounted) {
      debugPrint('[PricingRuleForm] Selected product: ${product.name}');
      setState(() {
        _selectedProductId = product.id;
        _selectedProductName = product.name;
      });
    }
  }

  Widget _categoryPicker() {
    return Expanded(
      child: InkWell(
        onTap: _pickCategory,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'الفئة (اختياري)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: _selectedCategoryId != null
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () => setState(() {
                      _selectedCategoryId = null;
                      _selectedCategoryName = null;
                    }),
                  )
                : const Icon(Icons.search_rounded, size: 16),
          ),
          child: Text(
            _selectedCategoryName ?? 'كل الفئات',
            style: TextStyle(
              color: _selectedCategoryName != null ? AppColors.textPrimary : AppColors.textHint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    debugPrint('[PricingRuleForm] Opening CategorySearchDialog');
    final cat = await showDialog<CategoryModel>(
      context: context,
      builder: (_) => _CategorySearchDialog(categories: _categories),
    );
    if (cat != null && mounted) {
      debugPrint('[PricingRuleForm] Selected category: ${cat.name}');
      setState(() {
        _selectedCategoryId = cat.id;
        _selectedCategoryName = cat.name;
      });
    }
  }

  String? _pctValidator(String? v) {
    final d = (v ?? '').tryParseArabicDouble();
    if (d == null || d < 0 || d > 100) return '0–100';
    return null;
  }
}

class _CategorySearchDialog extends StatefulWidget {
  final List<CategoryModel> categories;
  const _CategorySearchDialog({required this.categories});

  @override
  State<_CategorySearchDialog> createState() => _CategorySearchDialogState();
}

class _CategorySearchDialogState extends State<_CategorySearchDialog> {
  final _searchCtrl = TextEditingController();
  late List<CategoryModel> _results;

  @override
  void initState() {
    super.initState();
    _results = widget.categories.take(30).toList();
  }

  void _search(String query) {
    if (query.trim().isEmpty) {
      setState(() => _results = widget.categories.take(30).toList());
      return;
    }
    final q = query.toLowerCase();
    setState(() {
       _results = widget.categories.where((c) => 
         c.name.toLowerCase().contains(q)
       ).take(30).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ابحث عن فئة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'اكتب اسم الفئة...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final c = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_left_rounded, size: 16),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _ProductSearchDialog extends ConsumerStatefulWidget {
  const _ProductSearchDialog();

  @override
  ConsumerState<_ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends ConsumerState<_ProductSearchDialog> {
  final _searchCtrl = TextEditingController();
  List<ProductModel> _results = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _search(''));
  }

  void _search(String query) {
    final allProducts = ref.read(productsNotifierProvider).valueOrNull ?? [];
    if (query.trim().isEmpty) {
      setState(() => _results = allProducts.take(30).toList());
      return;
    }
    final q = query.toLowerCase();
    setState(() {
       _results = allProducts.where((p) => 
         p.name.toLowerCase().contains(q) || p.barcode.contains(q)
       ).take(30).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ابحث عن منتج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'اكتب اسم المنتج أو الباركود...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = _results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('الباركود: ${p.barcode}', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_left_rounded, size: 16),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              ],
            )
          ],
        ),
      ),
    );
  }
}
