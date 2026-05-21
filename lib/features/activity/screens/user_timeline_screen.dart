// lib/features/activity/screens/user_timeline_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/activity/activity_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../users/providers/users_provider.dart';
import '../providers/activity_logs_provider.dart';
import '../widgets/activity_log_detail_dialog.dart';
import '../widgets/activity_severity_chip.dart';

class UserTimelineScreen extends ConsumerWidget {
  const UserTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersListProvider);
    final filter = ref.watch(activityLogsFilterProvider);
    final pageAsync = ref.watch(activityLogsPageProvider);
    final df = DateFormat('yyyy/MM/dd HH:mm');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '\u0631\u062c\u0648\u0639',
                onPressed: () => context.go('/activity'),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              const SizedBox(width: 8),
              Text(
                '\u0627\u0644\u062c\u062f\u0648\u0644 \u0627\u0644\u0632\u0645\u0646\u064a \u0644\u0644\u0645\u0633\u062a\u062e\u062f\u0645',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          usersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645\u064a\u0646: $e', style: const TextStyle(color: AppColors.error)),
            data: (users) {
              final activeUsers = users.where((u) => u.isActive).toList();
              return DropdownButtonFormField<int?>(
                value: filter.userId,
                decoration: const InputDecoration(
                  labelText: '\u0627\u062e\u062a\u0631 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('\u2014 \u0627\u062e\u062a\u0631 \u0645\u0633\u062a\u062e\u062f\u0645\u0627\u064b \u2014')),
                  ...activeUsers.map(
                    (u) => DropdownMenuItem<int?>(
                      value: u.id,
                      child: Text('${u.fullName} (${u.username})'),
                    ),
                  ),
                ],
                onChanged: (userId) {
                  ref.read(activityLogsFilterProvider.notifier).update(
                        (f) => f.copyWith(
                          userId: userId,
                          clearUserId: userId == null,
                          page: 0,
                        ),
                      );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filter.userId == null
                ? const Center(
                    child: Text(
                      '\u0627\u062e\u062a\u0631 \u0645\u0633\u062a\u062e\u062f\u0645\u0627\u064b \u0644\u0639\u0631\u0636 \u0633\u062c\u0644 \u0646\u0634\u0627\u0637\u0647',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : pageAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('\u062e\u0637\u0623: $e')),
                    data: (page) {
                      if (page.items.isEmpty) {
                        return const Center(child: Text('\u0644\u0627 \u064a\u0648\u062c\u062f \u0646\u0634\u0627\u0637 \u0645\u0633\u062c\u0644 \u0644\u0647\u0630\u0627 \u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645'));
                      }
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          itemCount: page.items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = page.items[index];
                            return ListTile(
                              onTap: () => showActivityLogDetailDialog(context, log),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primarySurface,
                                child: Icon(
                                  Icons.history_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                              title: Text(log.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${ActivityCategories.labelAr(log.category)} \u2022 ${log.action}\n${df.format(log.createdAt)}',
                              ),
                              isThreeLine: true,
                              trailing: ActivitySeverityChip(severity: log.severity),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
