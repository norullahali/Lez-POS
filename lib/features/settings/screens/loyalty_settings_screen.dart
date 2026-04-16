// lib/features/settings/screens/loyalty_settings_screen.dart
//
// "إعدادات النقاط" — Loyalty Points configuration screen.
// Allows the shop owner to enable/disable the system, adjust earn/redeem rates.
// Changes are persisted immediately to app_settings and invalidate the global
// loyaltySettingsProvider so every downstream consumer (POS, PaymentDialog)
// picks up the new values without an app restart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/constants/loyalty_config.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() =>
      _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState
    extends ConsumerState<LoyaltySettingsScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  bool _enabled = true;
  final _ppcCtrl   = TextEditingController(); // points_per_currency
  final _rvCtrl    = TextEditingController(); // redemption_value
  bool _loading    = true;
  bool _saving     = false;
  String? _feedback;         // success / error message
  bool _feedbackSuccess = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ppcCtrl.dispose();
    _rvCtrl.dispose();
    super.dispose();
  }

  // ── Load current settings ─────────────────────────────────────────────────
  Future<void> _load() async {
    final svc = ref.read(settingsServiceProvider);
    final cfg = await svc.loadLoyaltySettings();
    if (!mounted) return;
    setState(() {
      _enabled = cfg.enabled;
      _ppcCtrl.text = cfg.pointsPerCurrency.toString();
      _rvCtrl.text   = cfg.redemptionValue.toString();
      _loading = false;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final ppc = double.tryParse(_ppcCtrl.text.trim());
    final rv  = double.tryParse(_rvCtrl.text.trim());

    if (ppc == null || ppc <= 0) {
      _showFeedback('قيمة "نقاط لكل مبلغ" يجب أن تكون رقماً موجباً', success: false);
      return;
    }
    if (rv == null || rv <= 0) {
      _showFeedback('قيمة "قيمة النقطة" يجب أن تكون رقماً موجباً', success: false);
      return;
    }

    setState(() => _saving = true);
    try {
      final svc = ref.read(settingsServiceProvider);
      await Future.wait([
        svc.setLoyaltyEnabled(_enabled),
        svc.setPointsPerCurrency(ppc),
        svc.setRedemptionValue(rv),
      ]);

      // Invalidate the global snapshot so all consumers reload instantly.
      ref.invalidate(loyaltySettingsProvider);

      _showFeedback('تم حفظ الإعدادات بنجاح ✓', success: true);
    } catch (e) {
      _showFeedback('حدث خطأ عند الحفظ: $e', success: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showFeedback(String msg, {required bool success}) {
    if (!mounted) return;
    setState(() {
      _feedback = msg;
      _feedbackSuccess = success;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'إعدادات نقاط الولاء',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('حفظ التغييرات'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Feedback banner ───────────────────────────────────────
                  if (_feedback != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _feedbackSuccess
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _feedbackSuccess
                              ? AppColors.success.withValues(alpha: 0.5)
                              : AppColors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          _feedbackSuccess
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: _feedbackSuccess
                              ? AppColors.success
                              : AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_feedback!,
                              style: TextStyle(
                                  color: _feedbackSuccess
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),

                  // ── Cards ─────────────────────────────────────────────────
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left — main settings card
                        Expanded(
                          flex: 3,
                          child: _SettingsCard(
                            enabled: _enabled,
                            ppcCtrl: _ppcCtrl,
                            rvCtrl: _rvCtrl,
                            onToggle: (v) => setState(() => _enabled = v),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Right — live preview card
                        Expanded(
                          flex: 2,
                          child: _PreviewCard(
                            enabled: _enabled,
                            pointsPerCurrency:
                                double.tryParse(_ppcCtrl.text) ??
                                    LoyaltyConfig.pointsPerCurrency,
                            redemptionValue:
                                double.tryParse(_rvCtrl.text) ??
                                    LoyaltyConfig.redemptionValue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Card
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final bool enabled;
  final TextEditingController ppcCtrl;
  final TextEditingController rvCtrl;
  final ValueChanged<bool> onToggle;

  const _SettingsCard({
    required this.enabled,
    required this.ppcCtrl,
    required this.rvCtrl,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.star_rounded,
                  color: Color(0xFFF59E0B), size: 24),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نظام نقاط الولاء',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  'تحكم بكيفية اكتساب واسترداد النقاط',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 28),

          // Toggle
          _SettingRow(
            icon: Icons.toggle_on_rounded,
            iconColor: enabled
                ? const Color(0xFF22C55E)
                : Colors.white38,
            label: 'تفعيل النظام',
            subtitle: enabled
                ? 'النظام مفعّل — العملاء يكسبون ويستردون النقاط'
                : 'النظام معطّل — لا يتم اكتساب أو استرداد نقاط',
            child: Switch(
              value: enabled,
              onChanged: onToggle,
              activeThumbColor: const Color(0xFF22C55E),
              activeTrackColor: const Color(0xFF22C55E).withValues(alpha: 0.25),
            ),
          ),

          const Divider(color: Colors.white12, height: 32),

          // Points per currency
          _SettingRow(
            icon: Icons.add_circle_outline_rounded,
            iconColor: AppColors.accent,
            label: 'نقاط لكل وحدة نقد',
            subtitle: 'عدد النقاط الممنوحة مقابل كل وحدة عملة تُنفق',
            child: SizedBox(
              width: 160,
              child: TextField(
                controller: ppcCtrl,
                enabled: enabled,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  hintText: '0.1',
                  hintStyle: const TextStyle(color: Colors.white24),
                  suffixText: 'نقطة/و.ن',
                  suffixStyle:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 32),

          // Redemption value
          _SettingRow(
            icon: Icons.redeem_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'قيمة النقطة عند الاسترداد',
            subtitle: 'الخصم النقدي الممنوح مقابل كل نقطة يستردها العميل',
            child: SizedBox(
              width: 160,
              child: TextField(
                controller: rvCtrl,
                enabled: enabled,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  hintText: '0.05',
                  hintStyle: const TextStyle(color: Colors.white24),
                  suffixText: 'د.ع/نقطة',
                  suffixStyle:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Preview Card
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  final bool enabled;
  final double pointsPerCurrency;
  final double redemptionValue;

  const _PreviewCard({
    required this.enabled,
    required this.pointsPerCurrency,
    required this.redemptionValue,
  });

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat('#,##0.##');

    // Simulate a 10,000 IQD purchase
    const sampleAmount = 10000.0;
    final earned = enabled
        ? (sampleAmount * pointsPerCurrency).floorToDouble()
        : 0.0;
    const usedPoints = 50.0;
    final discount = enabled ? usedPoints * redemptionValue : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Preview card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.visibility_rounded, color: Colors.white54, size: 18),
                SizedBox(width: 8),
                Text('معاينة مباشرة',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 20),
              _previewRow('مثال: فاتورة بقيمة',
                  '${nf.format(sampleAmount)} د.ع'),
              const SizedBox(height: 12),
              _previewRow(
                'نقاط مكتسبة',
                enabled ? '+ ${nf.format(earned)} نقطة' : '— معطّل',
                valueColor: enabled
                    ? const Color(0xFF22C55E)
                    : Colors.white38,
                icon: Icons.star_rounded,
              ),
              const Divider(color: Colors.white12, height: 24),
              _previewRow('مثال: استرداد 50 نقطة', ''),
              const SizedBox(height: 8),
              _previewRow(
                'خصم',
                enabled ? '− ${nf.format(discount)} د.ع' : '— معطّل',
                valueColor: enabled
                    ? const Color(0xFFF59E0B)
                    : Colors.white38,
                icon: Icons.redeem_rounded,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Defaults hint card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('القيم الافتراضية',
                  style: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(height: 10),
              _defaultRow('نقاط/و.ن',
                  LoyaltyConfig.pointsPerCurrency.toString()),
              _defaultRow('قيمة النقطة',
                  '${LoyaltyConfig.redemptionValue} د.ع'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewRow(String label, String value,
      {Color? valueColor, IconData? icon}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 13)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, color: valueColor ?? Colors.white, size: 15),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
                color: valueColor ?? Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ]),
      ],
    );
  }

  Widget _defaultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable setting row layout
// ─────────────────────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final Widget child;

  const _SettingRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        child,
      ],
    );
  }
}
