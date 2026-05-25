import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../governance/smart_action_grouping_service.dart';
import '../models/smart_action_group.dart';
import '../models/business_guidance_item.dart';
import '../models/reorder_suggestion.dart';
import '../models/smart_action_item.dart';
import '../providers/automation_providers.dart';
import '../widgets/automation_state_views.dart';
import '../widgets/automation_ui_helpers.dart';
import '../widgets/business_guidance_tile.dart';
import '../widgets/reorder_suggestion_card.dart';
import '../widgets/smart_action_card.dart';
import '../widgets/smart_action_group_header.dart';

class SmartActionCenterScreen extends ConsumerStatefulWidget {
  const SmartActionCenterScreen({super.key});

  @override
  ConsumerState<SmartActionCenterScreen> createState() =>
      _SmartActionCenterScreenState();
}

class _SmartActionCenterScreenState
    extends ConsumerState<SmartActionCenterScreen>
    with SingleTickerProviderStateMixin {
  SmartActionCategory? _categoryFilter;
  final Set<SmartActionGroup> _collapsedGroups = {};
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

  void _toggleGroup(SmartActionGroup group) {
    setState(() {
      if (_collapsedGroups.contains(group)) {
        _collapsedGroups.remove(group);
      } else {
        _collapsedGroups.add(group);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupedAsync = ref.watch(smartActionsGroupedProvider);
    final guidanceAsync = ref.watch(businessGuidanceProvider);
    final reorderAsync = ref.watch(reorderSuggestionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: 'الإجراءات'),
                    Tab(text: 'المساعد'),
                    Tab(text: 'إعادة الطلب'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                visualDensity: VisualDensity.compact,
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _actionsTab(groupedAsync),
              _guidanceTab(guidanceAsync),
              _reorderTab(reorderAsync),
            ],
          ),
        ),
      ],
    );
  }

  Widget _centeredContent(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: child,
      ),
    );
  }

  Widget _actionsTab(AsyncValue<List<SmartActionGroupedSection>> groupedAsync) {
    return groupedAsync.when(
      loading: () =>
          _centeredContent(const AutomationLoadingSkeleton(lines: 5)),
      error: (e, _) => _centeredContent(
        AutomationErrorState(message: 'خطأ: $e', onRetry: _refresh),
      ),
      data: (List<SmartActionGroupedSection> sections) {
        final List<SmartActionItem> flat =
            sections.expand((SmartActionGroupedSection s) => s.items).toList();
        final List<SmartActionItem> filtered = _categoryFilter == null
            ? flat
            : flat
                .where((SmartActionItem a) => a.category == _categoryFilter)
                .toList();
        final List<SmartActionGroupedSection> filteredSections =
            _categoryFilter == null
                ? sections
                : sections
                    .map(
                      (SmartActionGroupedSection s) => s.copyWith(
                        items: s.items
                            .where((SmartActionItem a) =>
                                a.category == _categoryFilter)
                            .toList(),
                      ),
                    )
                    .where((SmartActionGroupedSection s) => s.items.isNotEmpty)
                    .toList();

        return _centeredContent(
          Column(
            children: [
              _categoryFilters(),
              Expanded(
                child: filtered.isEmpty
                    ? const AutomationEmptyState(
                        title: 'لا توجد إجراءات تشغيلية',
                        subtitle: 'ستظهر التوصيات هنا عند توفر بيانات كافية',
                        icon: Icons.dashboard_customize_outlined,
                      )
                    : _categoryFilter == null
                        ? ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: filteredSections.length,
                            itemBuilder: (context, index) {
                              final section = filteredSections[index];
                              return SmartActionSectionBlock(
                                section: section,
                                collapsed:
                                    _collapsedGroups.contains(section.group),
                                onToggle: () => _toggleGroup(section.group),
                              );
                            },
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12, top: 4),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) =>
                                SmartActionCard(action: filtered[index]),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _guidanceTab(AsyncValue<List<BusinessGuidanceItem>> guidanceAsync) {
    return guidanceAsync.when(
      loading: () =>
          _centeredContent(const AutomationLoadingSkeleton(lines: 4)),
      error: (e, _) => _centeredContent(
        AutomationErrorState(message: 'خطأ: $e', onRetry: _refresh),
      ),
      data: (List<BusinessGuidanceItem> items) {
        if (items.isEmpty) {
          return _centeredContent(
            const AutomationEmptyState(
              title: 'لا توجد رؤى حالياً',
              subtitle: 'المساعد التشغيلي يظهر ملخصات عند توفر إشارات',
              icon: Icons.lightbulb_outline_rounded,
            ),
          );
        }
        return _centeredContent(
          ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (_, i) => BusinessGuidanceTile(item: items[i]),
          ),
        );
      },
    );
  }

  Widget _reorderTab(AsyncValue<List<ReorderSuggestion>> reorderAsync) {
    return reorderAsync.when(
      loading: () =>
          _centeredContent(const AutomationLoadingSkeleton(lines: 5)),
      error: (e, _) => _centeredContent(
        AutomationErrorState(message: 'خطأ: $e', onRetry: _refresh),
      ),
      data: (List<ReorderSuggestion> items) {
        if (items.isEmpty) {
          return _centeredContent(
            const AutomationEmptyState(
              title: 'لا توجد اقتراحات إعادة طلب',
              subtitle: 'المنتجات ضمن المخزون الآمن حالياً',
              icon: Icons.inventory_outlined,
            ),
          );
        }
        return _centeredContent(
          ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (_, i) => ReorderSuggestionCard(suggestion: items[i]),
          ),
        );
      },
    );
  }

  Widget _categoryFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          _filterChip(null, 'الكل'),
          ...SmartActionCategory.values.map(
            (c) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _filterChip(c, AutomationUiHelpers.categoryLabel(c)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(SmartActionCategory? category, String label) {
    final selected = _categoryFilter == category;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      onSelected: (_) => setState(() => _categoryFilter = category),
      selectedColor: AppColors.primarySurface,
      checkmarkColor: AppColors.primary,
    );
  }
}
