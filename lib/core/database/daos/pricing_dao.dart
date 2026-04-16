// lib/core/database/daos/pricing_dao.dart
//
// Pure raw-SQL DAO for pricing rules. No Drift typed API used – avoids
// needing the table accessors in the Companion objects and works cleanly
// with the generated AppDatabase code.

import '../app_database.dart';

class PricingDao {
  final AppDatabase db;
  PricingDao(this.db);

  static const _joinedSelect = '''
    SELECT
      r.id, r.name, r.rule_type, r.priority, r.is_active,
      r.start_date, r.end_date, r.created_at,
      r.customer_group_id, r.coupon_code,
      c.product_id, c.category_id,
      c.minimum_quantity, c.minimum_total_price,
      a.discount_percentage, a.discount_amount, a.special_price,
      a.buy_quantity, a.get_quantity
    FROM pricing_rules r
    LEFT JOIN pricing_rule_conditions c ON c.rule_id = r.id
    LEFT JOIN pricing_rule_actions    a ON a.rule_id = r.id
  ''';

  // ── Reads ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllRulesRaw() async {
    final rows = await db.customSelect(
      '$_joinedSelect ORDER BY r.priority DESC, r.id',
      readsFrom: {db.pricingRules, db.pricingRuleConditions, db.pricingRuleActions},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getActiveRulesRaw() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.customSelect(
      '''
      $_joinedSelect
      WHERE r.is_active = 1
        AND (r.start_date IS NULL OR r.start_date <= $now)
        AND (r.end_date   IS NULL OR r.end_date   >= $now)
      ORDER BY r.priority DESC, r.id
      ''',
      readsFrom: {db.pricingRules, db.pricingRuleConditions, db.pricingRuleActions},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<int> saveRule({
    required String name,
    required String ruleType,
    required int priority,
    DateTime? startDate,
    DateTime? endDate,
    bool isActive = true,
    // Condition
    int? productId,
    int? categoryId,
    double minimumQuantity = 0,
    double minimumTotalPrice = 0,
    // Action
    double discountPercentage = 0,
    double discountAmount = 0,
    double? specialPrice,
    int buyQuantity = 1,
    int getQuantity = 0,
  }) async {
    return db.transaction<int>(() async {
      final startTs = startDate != null ? startDate.millisecondsSinceEpoch ~/ 1000 : 'NULL';
      final endTs   = endDate   != null ? endDate.millisecondsSinceEpoch   ~/ 1000 : 'NULL';
      final activeInt = isActive ? 1 : 0;

      await db.customStatement(
        "INSERT INTO pricing_rules (name, rule_type, priority, start_date, end_date, is_active) "
        "VALUES ('${_esc(name)}', '${_esc(ruleType)}', $priority, $startTs, $endTs, $activeInt)",
      );
      final ruleId = await _lastInsertRowId();

      final pId   = productId  != null ? '$productId'  : 'NULL';
      final catId = categoryId != null ? '$categoryId' : 'NULL';
      await db.customStatement(
        "INSERT INTO pricing_rule_conditions "
        "(rule_id, product_id, category_id, minimum_quantity, minimum_total_price) "
        "VALUES ($ruleId, $pId, $catId, $minimumQuantity, $minimumTotalPrice)",
      );

      final sp = specialPrice != null ? '$specialPrice' : 'NULL';
      await db.customStatement(
        "INSERT INTO pricing_rule_actions "
        "(rule_id, discount_percentage, discount_amount, special_price, buy_quantity, get_quantity) "
        "VALUES ($ruleId, $discountPercentage, $discountAmount, $sp, $buyQuantity, $getQuantity)",
      );

      return ruleId;
    });
  }

  Future<void> updateRule({
    required int ruleId,
    required String name,
    required String ruleType,
    required int priority,
    DateTime? startDate,
    DateTime? endDate,
    bool isActive = true,
    int? productId,
    int? categoryId,
    double minimumQuantity = 0,
    double minimumTotalPrice = 0,
    double discountPercentage = 0,
    double discountAmount = 0,
    double? specialPrice,
    int buyQuantity = 1,
    int getQuantity = 0,
  }) async {
    await db.transaction(() async {
      final startTs   = startDate != null ? startDate.millisecondsSinceEpoch ~/ 1000 : 'NULL';
      final endTs     = endDate   != null ? endDate.millisecondsSinceEpoch   ~/ 1000 : 'NULL';
      final activeInt = isActive ? 1 : 0;

      await db.customStatement(
        "UPDATE pricing_rules SET name='${_esc(name)}', rule_type='${_esc(ruleType)}', "
        "priority=$priority, start_date=$startTs, end_date=$endTs, is_active=$activeInt "
        "WHERE id=$ruleId",
      );

      final pId   = productId  != null ? '$productId'  : 'NULL';
      final catId = categoryId != null ? '$categoryId' : 'NULL';
      await db.customStatement(
        "UPDATE pricing_rule_conditions SET "
        "product_id=$pId, category_id=$catId, "
        "minimum_quantity=$minimumQuantity, minimum_total_price=$minimumTotalPrice "
        "WHERE rule_id=$ruleId",
      );

      final sp = specialPrice != null ? '$specialPrice' : 'NULL';
      await db.customStatement(
        "UPDATE pricing_rule_actions SET "
        "discount_percentage=$discountPercentage, discount_amount=$discountAmount, "
        "special_price=$sp, buy_quantity=$buyQuantity, get_quantity=$getQuantity "
        "WHERE rule_id=$ruleId",
      );
    });
  }

  Future<void> deleteRule(int ruleId) async {
    await db.customStatement("DELETE FROM pricing_rules WHERE id=$ruleId");
    // Rows in _conditions and _actions deleted automatically via ON DELETE CASCADE
  }

  Future<void> toggleActive(int ruleId, {required bool active}) async {
    await db.customStatement(
      "UPDATE pricing_rules SET is_active=${active ? 1 : 0} WHERE id=$ruleId",
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _esc(String s) => s.replaceAll("'", "''");

  Future<int> _lastInsertRowId() async {
    final rows = await db.customSelect('SELECT last_insert_rowid() AS id').get();
    return rows.first.data['id'] as int;
  }
}
