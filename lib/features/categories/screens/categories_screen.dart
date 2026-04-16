// lib/features/categories/screens/categories_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../models/category_model.dart';
import '../providers/categories_provider.dart';
import 'widgets/category_form_dialog.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة فئة'),
                onPressed: () => _showForm(context, ref, null),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Grid
          Expanded(
            child: categoriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (categories) {
                if (categories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.category_outlined, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد فئات بعد', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة أول فئة'),
                          onPressed: () => _showForm(context, ref, null),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (_, i) => _CategoryCard(
                    category: categories[i],
                    onEdit: () => _showForm(context, ref, categories[i]),
                    onDelete: () => _confirmDelete(context, ref, categories[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, CategoryModel? existing) async {
    final result = await showDialog<CategoryModel>(
      context: context,
      builder: (_) => CategoryFormDialog(existing: existing),
    );
    if (result != null) {
      final notifier = ref.read(categoriesNotifierProvider.notifier);
      if (existing == null) {
        await notifier.add(result);
      } else {
        await notifier.updateCategory(result);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CategoryModel cat) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'حذف الفئة',
      message: 'هل تريد حذف فئة "${cat.name}"؟ لن يمكن التراجع عن هذا الإجراء.',
    );
    if (confirmed) {
      await ref.read(categoriesNotifierProvider.notifier).delete(cat.id!);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({required this.category, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.category_rounded, color: color, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    color: AppColors.primary,
                    tooltip: 'تعديل',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.error,
                    tooltip: 'حذف',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
