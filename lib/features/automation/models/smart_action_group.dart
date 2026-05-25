import 'smart_action_item.dart';

enum SmartActionGroup {
  inventory,
  finance,
  operations,
  cashier,
  loyalty,
  alerts,
}

extension SmartActionGroupX on SmartActionGroup {
  String get labelAr => switch (this) {
        SmartActionGroup.inventory => 'المخزون',
        SmartActionGroup.finance => 'المالية',
        SmartActionGroup.operations => 'التشغيل',
        SmartActionGroup.cashier => 'الكاشير',
        SmartActionGroup.loyalty => 'الولاء',
        SmartActionGroup.alerts => 'التنبيهات',
      };

  static SmartActionGroup fromCategory(SmartActionCategory category) => switch (category) {
        SmartActionCategory.reorder => SmartActionGroup.inventory,
        SmartActionCategory.purchase => SmartActionGroup.inventory,
        SmartActionCategory.restock => SmartActionGroup.inventory,
        SmartActionCategory.debt => SmartActionGroup.finance,
        SmartActionCategory.sales => SmartActionGroup.operations,
        SmartActionCategory.workflow => SmartActionGroup.operations,
        SmartActionCategory.cashier => SmartActionGroup.cashier,
        SmartActionCategory.loyalty => SmartActionGroup.loyalty,
      };
}