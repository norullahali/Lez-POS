import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../governance/smart_action_grouping_service.dart';
import '../models/smart_action_item.dart';
import '../providers/automation_providers.dart';
import '../widgets/business_guidance_tile.dart';
import '../widgets/smart_action_card.dart';
import '../widgets/smart_action_group_header.dart';

class SmartActionCenterScreen extends ConsumerStatefulWidget {
  const SmartActionCenterScreen({super.key});

  @override
  ConsumerState<SmartActionCenterScreen> createState() => _SmartActionCenterScreenState();
}

class _SmartActionCenterScreenState extends ConsumerState<SmartActionCenterScreen>
    with SingleTickerProviderStateMixin {
  SmartActionCategory? _categoryFilter;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(smartActionsProvider);
    ref.invalidate(smartActionsGroupedProvider);
    ref.invalidate(businessGuidanceProvider);
    ref.invalidate(reorderSuggestionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final groupedAsync = ref.watch(smartActionsGroupedProvider);
    final guidanceAsync = ref.watch(businessGuidanceProvider);
    final reorderAsync = ref.watch(reorderSuggestionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'الإجراءات'),
                    Tab(text: 'المساعد'),
                    Tab(text: 'إعادة الطلب'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _actionsTab(groupedAsync),
              guidanceAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => BusinessGuidanceTile(item: items[i]),
                ),
              ),
              reorderAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return ListTile(
                      title: Text(r.productName),
                      subtitle: Text('${r.explanation}\nكمية: ${r.suggestedQty.toStringAsFixed(0)}'),
                      trailing: Text('P${r.priorityScore}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionsTab(AsyncValue groupedAsync) {
    return groupedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (sections) {
        final typedSections = sections;
        final flat = typedSections.expand((s) => s.items).toList();
        final filtered = _categoryFilter == null
            ? flat
            : flat.where((a) => a.category == _categoryFilter).toList();
        final filteredSections = _categoryFilter == null
            ? typedSections
            : typedSections
                .map((s) => s.copyWith(items: s.items.where((a) => a.category == _categoryFilter).toList()))
                .where((s) => s.items.isNotEmpty)
                .toList();

        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('الكل'),
                    selected: _categoryFilter == null,
                    onSelected: (_) => setState(() => _categoryFilter = null),
                  ),
                  ...SmartActionCategory.values.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        label: Text(_catLabel(c)),
                        selected: _categoryFilter == c,
                        onSelected: (_) => setState(() => _categoryFilter = c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('لا توجد إجراءات', style: TextStyle(color: AppColors.textHint)),
                    )
                  : ListView.builder(
                      itemCount: _categoryFilter == null ? _groupedItemCount(filteredSections) : filtered.length,
                      itemBuilder: (context, index) {
                        if (_categoryFilter != null) {
                          return SmartActionCard(action: filtered[index]);
                        }
                        return _buildGroupedItem(filteredSections, index);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  int _groupedItemCount(List<SmartActionGroupedSection> sections) {
    var count = 0;
    for (final section in sections) {
      count += 1 + section.items.length;
    }
    return count;
  }

  Widget _buildGroupedItem(List<SmartActionGroupedSection> sections, int index) {
    var cursor = 0;
    for (final section in sections) {
      if (index == cursor) return SmartActionGroupHeader(section: section);
      cursor++;
      for (final item in section.items) {
        if (index == cursor) return SmartActionCard(action: item);
        cursor++;
      }
    }
    return const SizedBox.shrink();
  }

  String _catLabel(SmartActionCategory c) => switch (c) {
        SmartActionCategory.reorder => 'إعادة طلب',
        SmartActionCategory.purchase => 'شراء',
        SmartActionCategory.restock => 'تخزين',
        SmartActionCategory.debt => 'ذمم',
        SmartActionCategory.loyalty => 'ولاء',
        SmartActionCategory.cashier => 'كاشير',
        SmartActionCategory.sales => 'مبيعات',
        SmartActionCategory.workflow => 'سير عمل',
      };
}
