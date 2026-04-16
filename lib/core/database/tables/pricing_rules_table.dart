// lib/core/database/tables/pricing_rules_table.dart
import 'package:drift/drift.dart';
import 'products_table.dart';
import 'categories_table.dart';

// ─── Rule Type Enum stored as TEXT ───────────────────────────────────────────
// DISCOUNT_PERCENTAGE | DISCOUNT_FIXED | BUY_X_GET_Y | WHOLESALE_PRICE | SPECIAL_PRICE

/// Main pricing rule record.
class PricingRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get ruleType => text()(); // RuleType enum as string
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Future-ready fields (nullable – ignored for now)
  IntColumn get customerGroupId => integer().nullable()();
  TextColumn get couponCode => text().nullable()();
}

/// Condition: when does this rule apply?
class PricingRuleConditions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ruleId => integer().references(PricingRules, #id, onDelete: KeyAction.cascade)();
  // Scope: if both null → applies to all products
  IntColumn get productId => integer().nullable().references(Products, #id, onDelete: KeyAction.setNull)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  RealColumn get minimumQuantity => real().withDefault(const Constant(0.0))();
  RealColumn get minimumTotalPrice => real().withDefault(const Constant(0.0))();
}

/// Action: what happens when the rule is applied?
class PricingRuleActions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ruleId => integer().references(PricingRules, #id, onDelete: KeyAction.cascade)();
  RealColumn get discountPercentage => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get specialPrice => real().nullable()();
  IntColumn get buyQuantity => integer().withDefault(const Constant(1))();
  IntColumn get getQuantity => integer().withDefault(const Constant(0))();
}
