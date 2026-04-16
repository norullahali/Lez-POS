// lib/features/pos/screens/pos_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/services/printing_service.dart';
import '../../../core/services/settings_service.dart';
import '../../categories/providers/categories_provider.dart';
import '../../customers/providers/customer_accounts_provider.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../products/models/product_model.dart';
import '../../products/providers/products_provider.dart';
import '../providers/pos_products_provider.dart';
import '../models/cart_item.dart';
import '../models/cart_session.dart';
import '../providers/pos_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/database/app_database.dart';
import '../../../core/widgets/manager_approval_dialog.dart';
import 'widgets/payment_dialog.dart';
import 'widgets/session_dialog.dart';
import 'widgets/customer_selection_modal.dart';
import 'widgets/smart_search_bar.dart';

final posNfProvider = Provider<NumberFormat>((ref) => NumberFormat('#,##0.##'));

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
      // Initialize POS products load in background (warm-up)
      ref.read(posProductsProvider);
    });
  }

  Future<void> _checkSession() async {
    final session = await ref.read(posSessionProvider.future);
    if (session == null && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SessionOpenDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen must be called here (build phase), not in initState/callbacks
    ref.listen<CartState>(cartProvider, (prev, next) {
      if ((prev?.restoredFromStorage ?? false) == false &&
          next.restoredFromStorage &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم استرجاع السلات السابقة'),
            backgroundColor: Colors.teal,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    // Scaffold builds ONCE. Micro-widgets handle their own state.
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.posBackground,
        body: Column(
          children: [
            const _PosTopBar(),
            Expanded(
              child: Row(
                children: [
                  // LEFT: Product picker (60%)
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        SmartSearchBar(
                          onProductSelected: (product) {
                            final cart = ref.read(cartProvider);
                            final currentQty = cart.items
                                .where((i) => i.product.id == product.id)
                                .fold(0.0, (s, i) => s + i.quantity);
                            if (product.currentStock <= currentQty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('المخزون غير كافٍ: ${product.name}'),
                                  backgroundColor: AppColors.warning,
                                ),
                              );
                              return;
                            }
                            ref.read(cartProvider.notifier).addProduct(product);
                          },
                          onBarcodeSubmit: (barcode) async {
                            final product = await ref
                                .read(posProductsProvider.notifier)
                                .findByBarcode(barcode);
                            if (product != null) {
                              final cart = ref.read(cartProvider);
                              final currentQty = cart.items
                                  .where((i) => i.product.id == product.id)
                                  .fold(0.0, (s, i) => s + i.quantity);
                              if (product.currentStock <= currentQty) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('المخزون غير كافٍ: ${product.name}'),
                                    backgroundColor: AppColors.warning,
                                  ),
                                );
                                return;
                              }
                              ref.read(cartProvider.notifier).addProduct(product);
                            } else {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('المنتج غير موجود: $barcode'),
                                  backgroundColor: AppColors.error,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                        const _CategoryTabsPanel(),
                        const SizedBox(height: 8),
                        const Expanded(child: _ProductGridPanel()),
                      ],
                    ),
                  ),
                  // RIGHT: Cart (40%)
                  Container(
                    width: 380,
                    color: AppColors.posCartBg,
                    child: const _CartPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f12) {
        final cart = ref.read(cartProvider);
        if (cart.items.isNotEmpty) {
          // Trigger checkout (need a way to call it, maybe via a global event or just keeping checkout logic inside CartPanel)
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        ref.read(cartProvider.notifier).clearCart();
      } else if (event.logicalKey == LogicalKeyboardKey.delete) {
        final cart = ref.read(cartProvider);
        final selected = cart.selectedIndex;
        if (selected != null) {
          ref.read(cartProvider.notifier).removeItem(selected);
        }
      }
    }
  }
}




class _CategoryTabsPanel extends ConsumerWidget {
  const _CategoryTabsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final categoryFilter = ref.watch(posCategoryFilterProvider);

    return categoriesAsync.when(
      data: (cats) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _CategoryChip(
                label: 'الكل',
                isSelected: categoryFilter == null,
                onTap: () =>
                    ref.read(posCategoryFilterProvider.notifier).state = null),
            ...cats.map((c) => _CategoryChip(
                  label: c.name,
                  isSelected: categoryFilter == c.id,
                  color: c.color,
                  onTap: () =>
                      ref.read(posCategoryFilterProvider.notifier).state = c.id,
                )),
          ],
        ),
      ),
      loading: () => const SizedBox(height: 40),
      error: (_, __) => const SizedBox(height: 40),
    );
  }
}

class _ProductGridPanel extends ConsumerWidget {
  const _ProductGridPanel();

  void _addProduct(BuildContext context, WidgetRef ref, ProductModel product) {
    final cart = ref.read(cartProvider);
    final currentQty = cart.items
        .where((i) => i.product.id == product.id)
        .fold(0.0, (s, i) => s + i.quantity);
    if (product.currentStock <= currentQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('المخزون غير كافٍ: ${product.name}'),
            backgroundColor: AppColors.warning),
      );
      return;
    }
    ref.read(cartProvider.notifier).addProduct(product);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posStateAsync = ref.watch(posProductsProvider);
    final posState = posStateAsync.valueOrNull;

    if (posState == null && posStateAsync.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final filtered = ref.watch(filteredPosProductsProvider);
    final nf = ref.read(posNfProvider);

    if (filtered.isEmpty) {
      return Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('لا توجد منتجات', style: TextStyle(color: Colors.white54)),
          if (posState != null && !posState.isFullyLoaded) ...[
            const SizedBox(height: 12),
            const SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                    color: AppColors.accent, backgroundColor: Colors.white12)),
            const SizedBox(height: 8),
            const Text('جاري تحميل سجلات المتجر في الخلفية...',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]
        ],
      ));
    }

    return Column(
      children: [
        if (posState != null && !posState.isFullyLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent)),
                SizedBox(width: 8),
                Text('جاري التحميل في الخلفية...',
                    style: TextStyle(color: AppColors.accent, fontSize: 10)),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _ProductCard(
              product: filtered[i],
              onTap: () => _addProduct(context, ref, filtered[i]),
              nf: nf,
            ),
          ),
        ),
      ],
    );
  }
}

class _PosTopBar extends ConsumerWidget {
  const _PosTopBar();

  Future<void> _closeSession(BuildContext context, WidgetRef ref) async {
    final closingCashCtrl = TextEditingController(text: '0');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.posPanel,
        title: const Text('إغلاق جلسة الكاشير',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: closingCashCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              labelText: 'النقد الختامي',
              labelStyle: TextStyle(color: Colors.white70)),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إغلاق الجلسة')),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final closingCash = double.tryParse(closingCashCtrl.text) ?? 0;
      final summary =
          await ref.read(posSessionProvider.notifier).closeSession(closingCash);

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.posPanel,
            title: const Text('ملخص الجلسة',
                style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow('عدد الفواتير:', '${summary['count'] ?? 0}'),
                _SummaryRow('إجمالي المبيعات:',
                    '${NumberFormat('#,##0').format(summary['total'] ?? 0)} د.ع'),
                _SummaryRow('نقدي:',
                    '${NumberFormat('#,##0').format(summary['cash'] ?? 0)} د.ع'),
                _SummaryRow('بطاقة:',
                    '${NumberFormat('#,##0').format(summary['card'] ?? 0)} د.ع'),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/dashboard');
                },
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(posSessionProvider);
    final sessionName = sessionAsync.valueOrNull?.cashierName ?? '';

    return Container(
      height: 52,
      color: AppColors.posPanel,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              onPressed: () => context.go('/dashboard'),
              tooltip: 'العودة'),
          const SizedBox(width: 8),
          const Icon(Icons.point_of_sale_rounded,
              color: AppColors.accent, size: 22),
          const SizedBox(width: 8),
          const Text('ليز POS',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const Spacer(),
          if (sessionName.isNotEmpty) ...[
            const Icon(Icons.person_rounded, color: Colors.white54, size: 18),
            const SizedBox(width: 4),
            Text(sessionName,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 16),
          ],
          Text('F2:بحث  F12:دفع  Esc:مسح',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          const SizedBox(width: 16),
          TextButton.icon(
            icon: const Icon(Icons.logout_rounded,
                size: 16, color: Colors.white54),
            label: const Text('إغلاق الجلسة',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onPressed: () => _closeSession(context, ref),
          ),
        ],
      ),
    );
  }
}

class _CartPanel extends ConsumerStatefulWidget {
  const _CartPanel();
  @override
  ConsumerState<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<_CartPanel> {
  final _invoiceDiscountCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _invoiceDiscountCtrl.dispose();
    super.dispose();
  }

  /// Prints receipt from a CartSession snapshot.
  /// Used by checkout so the correct cart data is printed even if the
  /// user switches active cart between checkout start and completion.
  void _printReceiptFromSnapshot({
    required String invoiceNumber,
    required CartSession cart,
    required PaymentInfo payment,
    required String cashierName,
    double? currentDebt,
    double? pointsBefore,
    double? pointsEarned,
    double? pointsAfter,
  }) {
    final data = ReceiptData(
      invoiceNumber: invoiceNumber,
      date: DateTime.now(),
      items: cart.items
          .map((i) => ReceiptItem(
              name: i.product.name,
              qty: i.quantity,
              unitPrice: i.unitPrice,
              discount: i.discount,
              total: i.lineTotal))
          .toList(),
      subtotal: cart.subtotal,
      discount: cart.invoiceDiscount,
      total: cart.total,
      paymentMethod: payment.method,
      cashPaid: payment.cashPaid,
      change: payment.change,
      cashierName: cashierName,
      customerName: cart.selectedCustomer != null && cart.selectedCustomer!.id != 1 ? cart.selectedCustomer!.name : null,
      currentDebt: currentDebt,
      pointsBefore: pointsBefore,
      pointsEarned: pointsEarned,
      pointsAfter: pointsAfter,
    );
    PrintingService.printReceipt(data).catchError((_) {});
  }

  /// Opens a quick settle-debt dialog — allows paying previous balance from POS.
  Future<void> _settleDebt(int customerId, double currentBalance, String customerName) async {
    final amtCtrl = TextEditingController(text: currentBalance.toStringAsFixed(0));
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppColors.posPanel,
          title: Text('تسوية دين: $customerName',
              style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الرصيد الحالي: ${NumberFormat('#,##0.##').format(currentBalance)} د.ع',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amtCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'مبلغ الدفع',
                  labelStyle: TextStyle(color: Colors.white54),
                  suffixText: 'د.ع',
                  suffixStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('تأكيد الدفع'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
        if (amt <= 0) return;
        await ref.read(posRepositoryProvider).settleDebt(
          customerId: customerId,
          amount: amt,
          note: 'تسوية دين من POS',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تم تسجيل دفعة ${NumberFormat('#,##0.##').format(amt)} د.ع'),
            backgroundColor: AppColors.success,
          ));
        }
      }
    } finally {
      amtCtrl.dispose();
    }
  }

  Future<void> _checkout() async {
    final session = ref.read(posSessionProvider).valueOrNull;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('افتح جلسة الكاشير أولاً'),
          backgroundColor: AppColors.warning));
      return;
    }

    // ── Snapshot the active cart NOW, before any async gap ──────────────────
    final cartState = ref.read(cartProvider);
    final activeCartSnapshot = cartState.activeCart;
    final completedCartId = cartState.activeCartId;

    if (activeCartSnapshot.items.isEmpty) return;

    // Fetch current customer balance for display in dialog
    double customerBalance = 0;
    final selectedCustomer = activeCartSnapshot.selectedCustomer;
    if (selectedCustomer != null && selectedCustomer.id != 1) {
      customerBalance = await ref
          .read(customerAccountsDaoProvider)
          .getBalance(selectedCustomer.id);
    }

    if (!mounted) return;

    // ── Evaluate Return Limits & Permissions ────
    int? approvedByUserId;
    if (activeCartSnapshot.items.any((i) => i.isReturn)) {
      final user = ref.read(authProvider).valueOrNull?.user;
      if (user != null && user.roleId != 1) { // 1 = Admin (skip)
        final refundLimit = user.refundLimit;
        final totalRet = activeCartSnapshot.items.where((i) => i.isReturn).fold(0.0, (s, i) => s + i.lineTotal.abs());
        final nf = ref.read(posNfProvider);
        
        if (totalRet > refundLimit) {
          final approver = await showDialog<User>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ManagerApprovalDialog(
              requiredPermission: 'pos.refund',
              actionDescription: 'قيمة المرتجع (${nf.format(totalRet)} د.ع) تتجاوز الحد المسموح للكاشير (${nf.format(refundLimit)} د.ع)',
            ),
          );
          if (approver == null) return; // Cancelled
          approvedByUserId = approver.id;
        }
      }
    }

    if (!mounted) return;

    final payment = await showDialog<PaymentInfo>(
      context: context,
      builder: (_) => PaymentDialog(
        totalAmount: activeCartSnapshot.total,
        selectedCustomer: selectedCustomer,
        customerBalance: customerBalance,
      ),
    );
    if (payment == null) return;

    // Apply loyalty discount to cart state BEFORE calling checkout
    // so that pos_provider.checkout uses the updated total.
    if (payment.pointsUsed > 0) {
      ref.read(cartProvider.notifier).setLoyaltyPoints(
            payment.pointsUsed,
            payment.loyaltyDiscount,
          );
    }

    try {
      final userId = ref.read(authProvider).valueOrNull?.user?.id;
      final invoiceNumber = generateInvoiceNumber();

      await ref.read(cartProvider.notifier).checkout(
            sessionId: session.id,
            invoiceNumber: invoiceNumber,
            payment: payment,
            userId: userId,
            approvedByUserId: approvedByUserId,
          );

      final pointsBefore = selectedCustomer != null && selectedCustomer.id != 1 
          ? ref.read(customerLoyaltyPointsProvider(selectedCustomer.id)).valueOrNull ?? 0 
          : null;
      double? pointsEarned;
      double? pointsAfter;
      
      final pb = pointsBefore;
      if (pb != null) {
        final settings = SettingsService(AppDatabase.instance);
        final lsn = await settings.loadLoyaltySettings();
        if (lsn.enabled) {
          final netTotal = activeCartSnapshot.total - payment.loyaltyDiscount;
          pointsEarned = lsn.earnedPoints(netTotal);
          pointsAfter = pb - payment.pointsUsed + pointsEarned;
        }
      }

      final currentDebt = payment.method == 'DEBT' || payment.method == 'MIXED'
          ? (customerBalance - payment.cashPaid + activeCartSnapshot.total) 
          : customerBalance;

      final cashierName = ref.read(authProvider).valueOrNull?.user?.fullName ?? session.cashierName;

      _printReceiptFromSnapshot(
        invoiceNumber: invoiceNumber,
        cart: activeCartSnapshot,
        payment: payment,
        cashierName: cashierName,
        currentDebt: currentDebt > 0 ? currentDebt : null,
        pointsBefore: pointsBefore,
        pointsEarned: pointsEarned,
        pointsAfter: pointsAfter,
      );

      // clearCart() resets loyaltyPointsUsed/loyaltyDiscount too.
      ref.read(cartProvider.notifier).clearCart();
      _invoiceDiscountCtrl.text = '0';
      ref.invalidate(productsNotifierProvider);

      // Refresh loyalty points cache for this customer
      if (selectedCustomer != null && selectedCustomer.id != 1) {
        ref.invalidate(customerLoyaltyPointsProvider(selectedCustomer.id));
      }

      if (completedCartId != 1) {
        ref.read(cartProvider.notifier).switchCart(1);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تم حفظ الفاتورة رقم $invoiceNumber'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      // Roll back loyalty points application on error
      ref.read(cartProvider.notifier).clearLoyaltyPoints();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final nf = ref.read(posNfProvider);
    final authState = ref.watch(authProvider).valueOrNull;
    final canDiscount = authState?.hasPermission('pos.discount') ?? false;

    return Column(
      children: [
        // ─── Multi-cart tabs ─────────────────────────────────────────────
        const _CartTabsBar(),
        // Cart header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.posPanel,
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('العربة (${cart.items.length})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const Spacer(),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all_rounded,
                      color: Colors.white54, size: 20),
                  onPressed: () {
                    ref.read(cartProvider.notifier).clearCart();
                    _invoiceDiscountCtrl.text = '0';
                  },
                  tooltip: 'مسح العربة (Esc)',
                ),
            ],
          ),
        ),
        // Customer Selection
        GestureDetector(
          onTap: () async {
            final result = await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const CustomerSelectionModal(),
            );
            if (result != null) {
              ref.read(cartProvider.notifier).selectCustomer(result);
              // Clear any lingering loyalty discount when customer changes
              ref.read(cartProvider.notifier).clearLoyaltyPoints();
            }
          },
          child: Container(
            color: AppColors.posPanelLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                    cart.selectedCustomer != null
                        ? Icons.person_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: AppColors.accent,
                    size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cart.selectedCustomer != null
                            ? cart.selectedCustomer!.name
                            : 'اختيار عميل (افتراضي: زبون عام)',
                        style: TextStyle(
                          color: cart.selectedCustomer != null
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      // Show live balance + loyalty points if customer selected
                      if (cart.selectedCustomer != null &&
                          cart.selectedCustomer!.id != 1)
                        Consumer(builder: (ctx, r, _) {
                          final balAsync = r.watch(customerBalanceProvider(
                              cart.selectedCustomer!.id));
                          final ptsAsync = r.watch(customerLoyaltyPointsProvider(
                              cart.selectedCustomer!.id));
                          final bal = balAsync.valueOrNull ?? 0.0;
                          final pts = ptsAsync.valueOrNull ?? 0.0;
                          final nf = NumberFormat('#,##0.##');
                          return Wrap(
                            spacing: 8,
                            children: [
                              if (bal != 0)
                                Text(
                                  'دين: ${nf.format(bal)} د.ع',
                                  style: TextStyle(
                                    color: bal > 0
                                        ? Colors.red[300]
                                        : Colors.green[300],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (pts > 0)
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.star_rounded,
                                      color: Color(0xFFF59E0B), size: 12),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${nf.format(pts)} نقطة',
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ]),
                            ],
                          );
                        }),
                    ],
                  ),
                ),
                // Settle debt button
                if (cart.selectedCustomer != null &&
                    cart.selectedCustomer!.id != 1)
                  Consumer(builder: (ctx, r, _) {
                    final balAsync = r.watch(customerBalanceProvider(
                        cart.selectedCustomer!.id));
                    final bal = balAsync.valueOrNull ?? 0.0;
                    if (bal <= 0) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.payments_rounded,
                          color: Colors.orange, size: 18),
                      tooltip: 'تسوية الدين',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _settleDebt(
                          cart.selectedCustomer!.id, bal, cart.selectedCustomer!.name),
                    );
                  }),
                if (cart.selectedCustomer != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 18),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () =>
                        ref.read(cartProvider.notifier).selectCustomer(null),
                  )
                else
                  const Icon(Icons.chevron_left_rounded,
                      color: Colors.white54, size: 18),
              ],
            ),
          ),
        ),
        // Cart items
        Expanded(
          child: cart.items.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.shopping_cart_outlined,
                          color: Colors.white.withValues(alpha: 0.2), size: 64),
                      const SizedBox(height: 12),
                      Text('العربة فارغة',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 14)),
                    ]))
              : ListView.builder(
                  itemCount: cart.items.length,
                  itemBuilder: (_, i) {
                    final item = cart.items[i];
                    final isSelected = cart.selectedIndex == i;
                    return GestureDetector(
                      onTap: () =>
                          ref.read(cartProvider.notifier).selectItem(i),
                      onLongPress: () => 
                          ref.read(cartProvider.notifier).toggleReturnItem(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        color: isSelected
                            ? AppColors.posHighlight
                            : item.isReturn
                                ? Colors.red.withAlpha(40)
                                : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                      style: TextStyle(
                                          color: item.isReturn ? Colors.red.shade200 : Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (item.isReturn) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('إرجاع', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Wrap(
                                    spacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (item.originalPrice != item.unitPrice && !item.isFreeItem)
                                        Text(nf.format(item.originalPrice),
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11,
                                                decoration: TextDecoration.lineThrough)),
                                      Text(item.isFreeItem ? 'مجاناً' : '${nf.format(item.unitPrice)} د.ع',
                                          style: TextStyle(
                                              color: item.isFreeItem ? AppColors.success : Colors.white54,
                                              fontWeight: item.isFreeItem ? FontWeight.w700 : FontWeight.w400,
                                              fontSize: 12)),
                                      if (item.appliedRuleLabel != null && !item.isFreeItem)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                                          ),
                                          child: Text(item.appliedRuleLabel!,
                                              style: const TextStyle(color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.w600)),
                                        ),
                                      if (item.isFreeItem)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                                          ),
                                          child: const Text('مجاني',
                                              style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w600)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Qty controls
                            Opacity(
                              opacity: item.isFreeItem || item.isReturn ? 0.5 : 1.0,
                              child: IgnorePointer(
                                ignoring: item.isFreeItem || item.isReturn,
                                child: Row(
                                  children: [
                                    _QtyBtn(
                                        icon: Icons.remove_rounded,
                                        onTap: () => ref
                                            .read(cartProvider.notifier)
                                            .decrementQty(i)),
                                    Padding(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(nf.format(item.quantity),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15)),
                                    ),
                                    _QtyBtn(
                                        icon: Icons.add_rounded,
                                        onTap: () => ref
                                            .read(cartProvider.notifier)
                                            .incrementQty(i)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${nf.format(item.lineTotal)} د.ع',
                                style: TextStyle(
                                    color: item.isReturn ? Colors.red.shade300 : AppColors.accentLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white38, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              onPressed: () =>
                                  ref.read(cartProvider.notifier).removeItem(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Discount + Totals + Checkout
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.posPanel,
          child: Column(
            children: [
              // Invoice discount
              TextField(
                controller: _invoiceDiscountCtrl,
                enabled: canDiscount,
                style: TextStyle(color: canDiscount ? Colors.white : AppColors.textHint),
                decoration: InputDecoration(
                  labelText: 'خصم الفاتورة${canDiscount ? "" : " (غير مصرح)"}',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: AppColors.posPanelLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => ref
                    .read(cartProvider.notifier)
                    .setInvoiceDiscount(double.tryParse(v) ?? 0),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المجموع:',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${nf.format(cart.subtotal)} د.ع',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              if (cart.invoiceDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم:',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('- ${nf.format(cart.invoiceDiscount)} د.ع',
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ),
              ],
              // Loyalty points discount row
              if (cart.loyaltyDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B), size: 13),
                      SizedBox(width: 4),
                      Text('خصم نقاط:',
                          style: TextStyle(
                              color: Color(0xFFF59E0B), fontSize: 12)),
                    ]),
                    Text('- ${nf.format(cart.loyaltyDiscount)} د.ع',
                        style: const TextStyle(
                            color: Color(0xFFF59E0B), fontSize: 12)),
                  ],
                ),
              ],
              const Divider(color: Colors.white24, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي:',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Text('${nf.format(cart.total)} د.ع',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cart.items.isEmpty
                        ? Colors.grey.shade700
                        : AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 22),
                  label: const Text('الدفع (F12)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  onPressed: cart.items.isEmpty ? null : _checkout,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label,
      required this.isSelected,
      this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (color ?? AppColors.accent)
                : AppColors.posPanelLight,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: Colors.white12),
          ),
          child: Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final NumberFormat nf;

  const _ProductCard(
      {required this.product, required this.onTap, required this.nf});

  @override
  Widget build(BuildContext context) {
    final isLow = product.currentStock <= 0;
    return GestureDetector(
      onTap: isLow ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: isLow ? Colors.grey.shade800 : AppColors.posProductCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isLow
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isLow
                      ? Colors.grey.withValues(alpha: 0.3)
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2_rounded,
                    color: isLow ? Colors.grey : AppColors.accent, size: 22),
              ),
              const SizedBox(height: 8),
              Text(product.name,
                  style: TextStyle(
                      color: isLow ? Colors.grey : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('${nf.format(product.sellPrice)} د.ع',
                  style: TextStyle(
                      color: isLow ? Colors.grey : AppColors.accentLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              if (isLow)
                const Text('نفد المخزون',
                    style: TextStyle(color: Colors.red, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Multi-Cart Tabs Bar
// ══════════════════════════════════════════════════════════════════════════
class _CartTabsBar extends ConsumerWidget {
  const _CartTabsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);
    final carts = cartState.carts;
    final activeId = cartState.activeCartId;
    final canAdd = carts.length < 3;

    return Container(
      height: 44,
      color: const Color(0xFF0D1330), // slightly darker than posCartBg
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Tab list
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final cartId in [1, 2, 3])
                    if (carts.containsKey(cartId))
                      _CartTab(
                        cartId: cartId,
                        isActive: activeId == cartId,
                        onTap: () =>
                            ref.read(cartProvider.notifier).switchCart(cartId),
                        onRemove: cartId == 1
                            ? null
                            : () => ref
                                .read(cartProvider.notifier)
                                .removeCart(cartId),
                      ),
                ],
              ),
            ),
          ),
          // Add cart button
          if (canAdd)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'إضافة سلة جديدة',
                child: InkWell(
                  onTap: () => ref.read(cartProvider.notifier).createCart(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.posPanelLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white60, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartTab extends StatelessWidget {
  final int cartId;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onRemove; // null = Cart 1 (cannot remove)

  const _CartTab({
    required this.cartId,
    required this.isActive,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : AppColors.posPanelLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.only(
              right: 10,
              left: onRemove != null ? 6 : 10,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'سلة $cartId',
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onRemove,
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: isActive
                          ? Colors.white70
                          : Colors.white30,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: AppColors.posPanelLight,
            borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}
