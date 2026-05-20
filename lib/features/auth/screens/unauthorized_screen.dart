// lib/features/auth/screens/unauthorized_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

class UnauthorizedScreen extends StatelessWidget {
  const UnauthorizedScreen({super.key, this.attemptedRoute});
  final String? attemptedRoute;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 56, color: AppColors.warning),
                const SizedBox(height: 16),
                const Text('غير مصرح', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  attemptedRoute == null
                      ? 'ليس لديك صلاحية للوصول إلى هذه الصفحة.'
                      : 'ليس لديك صلاحية للوصول إلى:\n$attemptedRoute',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}