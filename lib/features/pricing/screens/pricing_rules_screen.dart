// lib/features/pricing/screens/pricing_rules_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../models/pricing_rule_model.dart';
import '../providers/pricing_provider.dart';
import 'pricing_rule_form.dart';

class PricingRulesScreen extends ConsumerWidget {
  const PricingRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allRules = ref.watch(allPricingRulesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              const Expanded(
                child: Text(
                  'قواعد التسعير والعروض',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('قاعدة جديدة'),
                onPressed: () => _openForm(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── List ──
          Expanded(
            child: allRules.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (rules) => rules.isEmpty
                  ? _emptyState()
                  : _rulesTable(context, ref, rules),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesTable(
    BuildContext context,
    WidgetRef ref,
    List<PricingRuleModel> rules,
  ) {
    final df = DateFormat('yyyy/MM/dd');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 18,
            headingRowColor: WidgetStateProperty.all(
              AppColors.primary.withValues(alpha: 0.06),
            ),
            columns: const [
              DataColumn(label: Text('الاسم',     style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('النوع',     style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('الأولوية',  style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('من',        style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('إلى',       style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('الحالة',    style: TextStyle(fontWeight: FontWeight.w700))),
              DataColumn(label: Text('إجراءات',   style: TextStyle(fontWeight: FontWeight.w700))),
            ],
            rows: rules.map((r) {
              return DataRow(cells: [
                DataCell(Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(_TypeChip(r.ruleType)),
                DataCell(Text('${r.priority}')),
                DataCell(Text(r.startDate != null ? df.format(r.startDate!) : '—')),
                DataCell(Text(r.endDate   != null ? df.format(r.endDate!)   : '—')),
                DataCell(_ActiveToggle(rule: r, onReload: () => _reload(ref))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                    tooltip: 'تعديل',
                    onPressed: () => _openForm(context, ref, rule: r),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                    tooltip: 'حذف',
                    onPressed: () => _confirmDelete(context, ref, r),
                  ),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.local_offer_outlined, size: 72, color: AppColors.textHint.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        const Text('لا توجد قواعد تسعير بعد',
            style: TextStyle(fontSize: 18, color: AppColors.textHint, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('أنشئ أول قاعدة تسعير بالضغط على "قاعدة جديدة"',
            style: TextStyle(color: AppColors.textHint)),
      ]),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref, {PricingRuleModel? rule}) async {
    debugPrint('[PricingRulesScreen] _openForm called for rule: ${rule?.name ?? "NEW"}');
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PricingRuleForm(editRule: rule),
      );
      debugPrint('[PricingRulesScreen] Dialog closed with result: $result');
      if (result == true) {
        _reload(ref);
      }
    } catch (e, stack) {
      debugPrint('[PricingRulesScreen] Error opening form: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, PricingRuleModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف القاعدة: "${r.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDatabase.instance.pricingDao.deleteRule(r.id);
      if (context.mounted) _reload(ref);
    }
  }

  void _reload(WidgetRef ref) {
    ref.read(pricingProvider.notifier).reload();
    ref.invalidate(allPricingRulesProvider);
  }
}

// ── Active Toggle ──────────────────────────────────────────────────────────────

class _ActiveToggle extends StatelessWidget {
  final PricingRuleModel rule;
  final VoidCallback onReload;
  const _ActiveToggle({required this.rule, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: rule.isActive,
      activeThumbColor: AppColors.success,
      onChanged: (v) async {
        await AppDatabase.instance.pricingDao.toggleActive(rule.id, active: v);
        onReload();
      },
    );
  }
}

// ── Type Chip ─────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final RuleType type;
  const _TypeChip(this.type);

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      RuleType.discountPercentage => (AppColors.primary,         Icons.percent_rounded),
      RuleType.discountFixed      => (const Color(0xFF7E57C2),   Icons.money_rounded),
      RuleType.buyXGetY          => (AppColors.success,          Icons.card_giftcard_rounded),
      RuleType.wholesalePrice    => (AppColors.warning,          Icons.store_rounded),
      RuleType.specialPrice      => (AppColors.accent,           Icons.local_offer_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(type.displayName,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
