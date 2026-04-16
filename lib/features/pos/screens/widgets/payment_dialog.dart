// lib/features/pos/screens/widgets/payment_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/constants/loyalty_config.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/loyalty/providers/loyalty_provider.dart';
import '../../models/cart_item.dart';

class PaymentDialog extends ConsumerStatefulWidget {
  final double totalAmount;
  final Customer? selectedCustomer;
  final double customerBalance; // current debt before this sale
  const PaymentDialog({
    super.key,
    required this.totalAmount,
    this.selectedCustomer,
    this.customerBalance = 0,
  });

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String _method = 'CASH';
  final _cashCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController(text: '0');
  final _nf = NumberFormat('#,##0.##');

  // Loyalty state
  double _availablePoints = 0;
  double _pointsToUse = 0;
  bool _loyaltyLoaded = false;

  @override
  void initState() {
    super.initState();
    _cashCtrl.text = widget.totalAmount.toStringAsFixed(0);
    _loadLoyaltyPoints();
  }

  Future<void> _loadLoyaltyPoints() async {
    final customer = widget.selectedCustomer;
    if (customer == null || customer.id == 1) {
      setState(() => _loyaltyLoaded = true);
      return;
    }
    final svc = ref.read(loyaltyServiceProvider);
    final pts = await svc.getPoints(customer.id);
    if (mounted) {
      setState(() {
        _availablePoints = pts;
        _loyaltyLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _cardCtrl.dispose();
    _pointsCtrl.dispose();
    super.dispose();
  }

  // ─── helpers ────────────────────────────────────────
  static String _normalizeNumber(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const arabic = '۰۱۲۳۴۵۶۷۸۹';
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(eastern[i], '$i').replaceAll(arabic[i], '$i');
    }
    return result;
  }

  double get _cashPaid =>
      double.tryParse(_normalizeNumber(_cashCtrl.text.trim())) ?? 0;
  double get _cardPaid =>
      double.tryParse(_normalizeNumber(_cardCtrl.text.trim())) ?? 0;

  /// The final amount due after loyalty discount.
  double get _effectiveTotal =>
      (widget.totalAmount - _loyaltyDiscount).clamp(0, double.infinity);

  double get _loyaltyDiscount => LoyaltyConfig.redemptionDiscount(_pointsToUse);

  double get _debtAmount {
    if (_method == 'DEBT') return _effectiveTotal - _cashPaid;
    return 0;
  }

  double get _change {
    if (_method == 'CASH') return _cashPaid - _effectiveTotal;
    if (_method == 'MIXED') return (_cashPaid + _cardPaid) - _effectiveTotal;
    if (_method == 'DEBT') {
      final cash = _cashPaid.clamp(0, _effectiveTotal);
      return cash - _effectiveTotal < 0 ? 0 : cash - _effectiveTotal;
    }
    return 0;
  }

  bool get _isValid {
    if (_method == 'CASH') return _cashPaid >= _effectiveTotal;
    if (_method == 'CARD') return true;
    if (_method == 'MIXED') {
      return (_cashPaid + _cardPaid) >= _effectiveTotal;
    }
    if (_method == 'DEBT') {
      if (widget.selectedCustomer == null || widget.selectedCustomer!.id == 1) {
        return false;
      }
      return _cashPaid >= 0 && _cashPaid <= _effectiveTotal;
    }
    return false;
  }

  bool get _noCustomerForDebt =>
      _method == 'DEBT' &&
      (widget.selectedCustomer == null || widget.selectedCustomer!.id == 1);

  double get _projectedBalance =>
      widget.customerBalance + (_method == 'DEBT' ? _debtAmount : 0);


  bool get _hasLoyaltyCustomer =>
      widget.selectedCustomer != null &&
      widget.selectedCustomer!.id != 1 &&
      _availablePoints > 0;

  void _onPointsChanged(String v) {
    final pts = double.tryParse(_normalizeNumber(v.trim())) ?? 0;
    final maxPts = LoyaltyConfig.maxRedeemable(_availablePoints, widget.totalAmount);
    setState(() {
      _pointsToUse = pts.clamp(0, maxPts);
      // Update cash field to reflect new effective total
      if (_method == 'CASH') {
        _cashCtrl.text = _effectiveTotal.toStringAsFixed(0);
      }
    });
  }

  // ─── build ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.posPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              const Text('الدفع',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'المبلغ المطلوب: ${_nf.format(widget.totalAmount)} د.ع',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),

              // ── Loyalty points section ──────────────────────────────
              if (_loyaltyLoaded && _hasLoyaltyCustomer) ...[
                const SizedBox(height: 12),
                _LoyaltySection(
                  availablePoints: _availablePoints,
                  pointsToUse: _pointsToUse,
                  loyaltyDiscount: _loyaltyDiscount,
                  effectiveTotal: _effectiveTotal,
                  controller: _pointsCtrl,
                  maxRedeemable: LoyaltyConfig.maxRedeemable(
                      _availablePoints, widget.totalAmount),
                  onChanged: _onPointsChanged,
                  nf: _nf,
                ),
              ],
              if (_loyaltyLoaded &&
                  widget.selectedCustomer != null &&
                  widget.selectedCustomer!.id != 1 &&
                  _availablePoints == 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.star_border_rounded,
                        color: Colors.white38, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'رصيد النقاط: 0 — ستكسب ${_nf.format(LoyaltyConfig.earnedPoints(widget.totalAmount))} نقطة من هذه الفاتورة',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ]),
                ),
              ],

              // Current balance warning
              if (widget.customerBalance > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'رصيد الدين الحالي: ${_nf.format(widget.customerBalance)} د.ع',
                          style:
                              const TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Method buttons
              Row(
                children: [
                  _MethodButton(
                      label: 'نقدي',
                      icon: Icons.money_rounded,
                      method: 'CASH',
                      selected: _method,
                      onTap: () => setState(() {
                            _method = 'CASH';
                            _cashCtrl.text =
                                _effectiveTotal.toStringAsFixed(0);
                          })),
                  const SizedBox(width: 6),
                  _MethodButton(
                      label: 'بطاقة',
                      icon: Icons.credit_card_rounded,
                      method: 'CARD',
                      selected: _method,
                      onTap: () => setState(() => _method = 'CARD')),
                  const SizedBox(width: 6),
                  _MethodButton(
                      label: 'مختلط',
                      icon: Icons.credit_score_rounded,
                      method: 'MIXED',
                      selected: _method,
                      onTap: () => setState(() => _method = 'MIXED')),
                  const SizedBox(width: 6),
                  _MethodButton(
                      label: 'آجل',
                      icon: Icons.account_balance_wallet_rounded,
                      method: 'DEBT',
                      selected: _method,
                      accentColor: Colors.orange,
                      onTap: () => setState(() {
                            _method = 'DEBT';
                            _cashCtrl.text = '0';
                          })),
                ],
              ),

              const SizedBox(height: 20),

              // No customer warning for DEBT
              if (_noCustomerForDebt) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_off_rounded, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'يجب اختيار عميل محدد (غير الزبون العام) للبيع الآجل',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Cash field (CASH, MIXED, DEBT partial)
              if (_method == 'CASH' || _method == 'MIXED' || _method == 'DEBT') ...[
                TextField(
                  controller: _cashCtrl,
                  autofocus: _method != 'DEBT',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _method == 'DEBT'
                        ? 'دفع نقدي الآن (اختياري)'
                        : 'المبلغ النقدي',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: AppColors.posPanelLight,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    suffixText: 'د.ع',
                    suffixStyle: const TextStyle(color: Colors.white54),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],

              // Card field (MIXED)
              if (_method == 'MIXED') ...[
                TextField(
                  controller: _cardCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'مبلغ البطاقة',
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: AppColors.posPanelLight,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    suffixText: 'د.ع',
                    suffixStyle: const TextStyle(color: Colors.white54),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],

              // DEBT summary
              if (_method == 'DEBT') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('المبلغ الآجل:',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            Text(
                              '${_nf.format(_debtAmount.clamp(0, _effectiveTotal))} د.ع',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16),
                            ),
                          ]),
                      if (widget.selectedCustomer != null &&
                          widget.selectedCustomer!.id != 1) ...[
                        const Divider(color: Colors.white12, height: 16),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('الرصيد المتوقع:',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                              Text(
                                '${_nf.format(_projectedBalance)} د.ع',
                                style: TextStyle(
                                    color: _projectedBalance > 0
                                        ? Colors.red[300]
                                        : Colors.green[300],
                                    fontSize: 13),
                              ),
                            ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Change display
              if (_method != 'CARD' && _method != 'DEBT' && _change >= 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.successLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الباقي:',
                            style: TextStyle(color: Colors.white70)),
                        Text(
                          '${_nf.format(_change)} د.ع',
                          style: const TextStyle(
                              color: Color(0xFF66BB6A),
                              fontWeight: FontWeight.w700,
                              fontSize: 18),
                        ),
                      ]),
                ),

              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                      child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء',
                              style: TextStyle(color: Colors.white54)))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isValid ? AppColors.success : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isValid ? _confirm : null,
                      child: const Text('تأكيد الدفع',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    final debtAmt = _method == 'DEBT'
        ? (_debtAmount).clamp(0.0, _effectiveTotal)
        : 0.0;
    Navigator.pop(
      context,
      PaymentInfo(
        method: _method,
        cashPaid: _cashPaid,
        cardPaid: _cardPaid,
        change: _change > 0 ? _change : 0,
        debtAmount: debtAmt,
        pointsUsed: _pointsToUse,
        loyaltyDiscount: _loyaltyDiscount,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loyalty points section widget (extracted for clarity)
// ─────────────────────────────────────────────────────────────────────────────

class _LoyaltySection extends StatelessWidget {
  final double availablePoints;
  final double pointsToUse;
  final double loyaltyDiscount;
  final double effectiveTotal;
  final double maxRedeemable;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final NumberFormat nf;

  const _LoyaltySection({
    required this.availablePoints,
    required this.pointsToUse,
    required this.loyaltyDiscount,
    required this.effectiveTotal,
    required this.maxRedeemable,
    required this.controller,
    required this.onChanged,
    required this.nf,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = loyaltyDiscount > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDiscount
              ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
              : const Color(0xFFF59E0B).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'نقاط الولاء — الرصيد المتاح: ${nf.format(availablePoints)} نقطة',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasDiscount)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'خصم ${nf.format(loyaltyDiscount)} د.ع',
                    style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Points input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'نقاط للاستخدام (max ${nf.format(maxRedeemable)})',
                    labelStyle: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.posPanelLight,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixText: 'نقطة',
                    suffixStyle: const TextStyle(
                        color: Color(0xFFF59E0B), fontSize: 11),
                  ),
                  onChanged: onChanged,
                ),
              ),
              if (pointsToUse > 0) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '= ${nf.format(loyaltyDiscount)} د.ع',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'الإجمالي بعد الخصم: ${nf.format(effectiveTotal)} د.ع',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // Earn hint
          const SizedBox(height: 6),
          const Text(
            'معدل الاسترداد: نقطة واحدة = ${LoyaltyConfig.redemptionValue} د.ع',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _MethodButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String method;
  final String selected;
  final VoidCallback onTap;
  final Color? accentColor;

  const _MethodButton(
      {required this.label,
      required this.icon,
      required this.method,
      required this.selected,
      required this.onTap,
      this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selected;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (accentColor ?? AppColors.accent)
                : AppColors.posPanelLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
