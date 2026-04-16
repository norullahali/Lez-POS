// lib/core/database/app_database.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'tables/categories_table.dart';
import 'tables/suppliers_table.dart';
import 'tables/customers_table.dart';
import 'tables/customer_accounts_table.dart';
import 'tables/customer_transactions_table.dart';
import 'tables/products_table.dart';
import 'tables/product_batches_table.dart';
import 'tables/stock_ledger_table.dart';
import 'tables/stock_adjustments_table.dart';
import 'tables/purchase_invoices_table.dart';
import 'tables/purchase_items_table.dart';
import 'tables/pos_sessions_table.dart';
import 'tables/sales_invoices_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/customer_returns_table.dart';
import 'tables/supplier_returns_table.dart';
import 'tables/supplier_accounts_table.dart';
import 'tables/supplier_transactions_table.dart';
import 'tables/users_table.dart';
import 'tables/roles_table.dart';
import 'tables/role_permissions_table.dart';
import 'tables/permissions_table.dart';
import 'tables/logs_table.dart';
import 'tables/pricing_rules_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/notifications_table.dart';
import 'daos/users_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/suppliers_dao.dart';
import 'daos/customers_dao.dart';
import 'daos/customer_accounts_dao.dart';
import 'daos/supplier_accounts_dao.dart';
import 'daos/products_dao.dart';
import 'daos/stock_dao.dart';
import 'daos/purchases_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/returns_dao.dart';
import 'daos/logs_dao.dart';
import 'daos/pricing_dao.dart';
import 'daos/app_settings_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    Suppliers,
    Customers,
    CustomerAccounts,
    CustomerTransactions,
    SupplierAccounts,
    SupplierTransactions,
    Products,
    ProductBatches,
    StockLedger,
    StockAdjustments,
    PurchaseInvoices,
    PurchaseItems,
    PosSessions,
    SalesInvoices,
    SaleItems,
    CustomerReturns,
    CustomerReturnItems,
    SupplierReturns,
    SupplierReturnItems,
    UsersTable,
    Roles,
    Permissions,
    RolePermissions,
    LogsTable,
    PricingRules,
    PricingRuleConditions,
    PricingRuleActions,
    AppSettings,
    NotificationsTable,
  ],
  daos: [
    UsersDao,
    CategoriesDao,
    SuppliersDao,
    CustomersDao,
    CustomerAccountsDao,
    SupplierAccountsDao,
    ProductsDao,
    StockDao,
    PurchasesDao,
    SalesDao,
    ReturnsDao,
    LogsDao,
    AppSettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static AppDatabase? _instance;

  static AppDatabase get instance {
    _instance ??= AppDatabase._internal(_openConnection());
    return _instance!;
  }

  /// Plain (non-Drift-managed) DAO for pricing rules.
  late final pricingDao = PricingDao(this);

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Enable foreign keys
        await customStatement('PRAGMA foreign_keys = ON');
        // Set WAL mode for better concurrent performance
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA synchronous = NORMAL');
        // Seed default roles and permissions
        await _seedDefaultRoles(m);
        // Seed default app settings (loyalty config, etc.)
        await _seedDefaultSettings();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          try { await m.createTable(posSessions); } catch (e) { debugPrint('[Migration] create pos_sessions error: $e'); }
          try { await m.createTable(salesInvoices); } catch (e) { debugPrint('[Migration] create sales_invoices error: $e'); }
          try { await m.createTable(saleItems); } catch (e) { debugPrint('[Migration] create sale_items error: $e'); }
          try { await m.createTable(customerReturns); } catch (e) { debugPrint('[Migration] create customer_returns error: $e'); }
          try { await m.createTable(customerReturnItems); } catch (e) { debugPrint('[Migration] create customer_return_items error: $e'); }
          try { await m.createTable(supplierReturns); } catch (e) { debugPrint('[Migration] create supplier_returns error: $e'); }
          try { await m.createTable(supplierReturnItems); } catch (e) { debugPrint('[Migration] create supplier_return_items error: $e'); }
        }
        if (from < 3) {
          // Add auth and permissions tables (ORDER MATTERS due to foreign keys)
          debugPrint('[Migration] Starting v3 migration (auth tables)...');
          try { 
            await m.createTable(roles); 
            debugPrint('[Migration] roles table created');
          } catch (e) { 
            debugPrint('[Migration] roles table skip/error: $e'); 
          }
          
          try { 
            await m.createTable(permissions); 
            debugPrint('[Migration] permissions table created');
          } catch (e) { 
            debugPrint('[Migration] permissions table skip/error: $e'); 
          }
          
          try { 
            await m.createTable(rolePermissions); 
            debugPrint('[Migration] role_permissions table created');
          } catch (e) { 
            debugPrint('[Migration] role_permissions table skip/error: $e'); 
          }
          
          try { 
            await m.createTable(usersTable); 
            debugPrint('[Migration] users table created');
          } catch (e) { 
            debugPrint('[Migration] users table skip/error: $e'); 
          }

          // Add created_by_user_id columns - silently ignore if already exist
          try { await customStatement('ALTER TABLE "sales_invoices" ADD COLUMN "created_by_user_id" INTEGER NULL REFERENCES users(id)'); } catch (e) { debugPrint('[Migration] alter sales_invoices skipped: $e'); }
          try { await customStatement('ALTER TABLE "purchase_invoices" ADD COLUMN "created_by_user_id" INTEGER NULL REFERENCES users(id)'); } catch (e) { debugPrint('[Migration] alter purchase_invoices skipped: $e'); }
          try { await customStatement('ALTER TABLE "stock_adjustments" ADD COLUMN "created_by_user_id" INTEGER NULL REFERENCES users(id)'); } catch (e) { debugPrint('[Migration] alter stock_adjustments skipped: $e'); }
          try { await customStatement('ALTER TABLE "pos_sessions" ADD COLUMN "created_by_user_id" INTEGER NULL REFERENCES users(id)'); } catch (e) { debugPrint('[Migration] alter pos_sessions skipped: $e'); }

          // Seed default auth data on upgrade
          await _seedDefaultRoles(m);
        }
        if (from < 4) {
          debugPrint('[Migration] Starting v4 migration (customers)...');
          try { await m.createTable(customers); } catch (e) { debugPrint('[Migration] create customers skip/error: $e'); }
          try { await customStatement("INSERT OR IGNORE INTO customers (id, name, is_active) VALUES (1, 'زبون عام', 1)"); } catch (_) {}
        }
        if (from < 5) {
          debugPrint('[Migration] Starting v5 migration (logs)...');
          try { await m.createTable(logsTable); } catch (e) { debugPrint('[Migration] create logs skip/error: $e'); }
        }
        if (from < 6) {
          // Force-correct the admin password hash to SHA-256('1234')
          try {
            await customStatement("""
              UPDATE users SET password_hash = '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4'
              WHERE username = 'admin'
            """);
            await customStatement("""
              INSERT OR IGNORE INTO users (id, full_name, username, password_hash, role_id, is_active)
              VALUES (1, 'المدير العام', 'admin', '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4', 1, 1)
            """);
          } catch (e) {
            debugPrint('[Migration v6] admin password reset skipped: $e');
          }
        }
        if (from < 7) {
          debugPrint('[Migration] Starting v7 migration (pricing rules)...');
          try { await m.createTable(pricingRules); } catch (e) { debugPrint('[Migration] create pricing_rules skip/error: $e'); }
          try { await m.createTable(pricingRuleConditions); } catch (e) { debugPrint('[Migration] create pricing_rule_conditions skip/error: $e'); }
          try { await m.createTable(pricingRuleActions); } catch (e) { debugPrint('[Migration] create pricing_rule_actions skip/error: $e'); }
          debugPrint('[Migration] v7 pricing tables created.');
        }
        if (from < 8) {
          debugPrint('[Migration] Starting v8 migration (customer accounts)...');
          try { await m.createTable(customerAccounts); } catch (e) { debugPrint('[Migration] create customer_accounts skip/error: $e'); }
          try { await m.createTable(customerTransactions); } catch (e) { debugPrint('[Migration] create customer_transactions skip/error: $e'); }
          // Add new columns to existing tables (ignore if already exist)
          try { await customStatement('ALTER TABLE "customers" ADD COLUMN "credit_limit" REAL NOT NULL DEFAULT 0'); } catch (e) { debugPrint('[Migration v8] alter customers skip: $e'); }
          try { await customStatement('ALTER TABLE "sales_invoices" ADD COLUMN "debt_amount" REAL NOT NULL DEFAULT 0'); } catch (e) { debugPrint('[Migration v8] alter sales_invoices skip: $e'); }
          debugPrint('[Migration] v8 customer accounts tables created.');
        }
        if (from < 9) {
          debugPrint('[Migration] Starting v9 migration (sales_invoices.customer_id)...');
          try { await customStatement('ALTER TABLE "sales_invoices" ADD COLUMN "customer_id" INTEGER NULL REFERENCES customers(id)'); } catch (e) { debugPrint('[Migration v9] alter sales_invoices add customer_id skip: $e'); }
        }
        if (from < 10) {
          debugPrint('[Migration] Starting v10 migration (supplier accounts)...');
          try { await m.createTable(supplierAccounts); } catch (e) { debugPrint('[Migration] create supplier_accounts skip: $e'); }
          try { await m.createTable(supplierTransactions); } catch (e) { debugPrint('[Migration] create supplier_transactions skip: $e'); }
          try { await customStatement('ALTER TABLE "purchase_invoices" ADD COLUMN "paid_amount" REAL NOT NULL DEFAULT 0'); } catch (e) { debugPrint('[Migration v10] alter purchase_invoices skip: $e'); }
          try { await customStatement('ALTER TABLE "purchase_invoices" ADD COLUMN "debt_amount" REAL NOT NULL DEFAULT 0'); } catch (e) { debugPrint('[Migration v10] alter purchase_invoices skip: $e'); }
          try { await customStatement('ALTER TABLE "purchase_invoices" ADD COLUMN "due_date" INTEGER'); } catch (e) { debugPrint('[Migration v10] alter purchase_invoices skip: $e'); }
        }
        if (from < 11) {
          // v11: reserved for future promotions table (promotions table was planned but uses existing pricing_rules)
          debugPrint('[Migration] v11 reserved — no structural changes.');
        }
        if (from < 12) {
          debugPrint('[Migration] Starting v12 migration (customer loyalty points)...');
          try {
            await customStatement('ALTER TABLE "customers" ADD COLUMN "loyalty_points" REAL NOT NULL DEFAULT 0');
            debugPrint('[Migration v12] loyalty_points column added to customers.');
          } catch (e) {
            debugPrint('[Migration v12] alter customers loyalty_points skip: $e');
          }
        }
        if (from < 13) {
          debugPrint('[Migration] Starting v13 migration (app_settings table)...');
          try {
            await m.createTable(appSettings);
            debugPrint('[Migration v13] app_settings table created.');
          } catch (e) {
            debugPrint('[Migration v13] create app_settings skip: $e');
          }
          // Seed default loyalty settings
          await _seedDefaultSettings();
        }
        if (from < 14) {
          debugPrint('[Migration] Starting v14 migration (Advanced RBAC)...');
          try { await m.createTable(notificationsTable); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(roles, roles.isSystem); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(usersTable, usersTable.refundLimit); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(usersTable, usersTable.pinCode); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(logsTable, logsTable.amount); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(logsTable, logsTable.approvedByUserId); } catch(e){ debugPrint('skip: $e'); }
          try { await m.addColumn(logsTable, logsTable.note); } catch(e){ debugPrint('skip: $e'); }
          
          // Clear old permissions to apply the new advanced RBAC structure safely
          try { await customStatement("DELETE FROM role_permissions"); } catch(e){ debugPrint('skip: $e'); }
          try { await customStatement("DELETE FROM permissions"); } catch(e){ debugPrint('skip: $e'); }
          
          await _seedDefaultRoles(m);
        }
        if (from < 15) {
          debugPrint('[Migration] Starting v15 migration (Data Integrity)...');
          try { await customStatement('UPDATE users SET refund_limit = 0.0 WHERE refund_limit IS NULL'); } catch(e){ debugPrint('skip: $e'); }
          try { await customStatement('UPDATE roles SET is_system = 0 WHERE is_system IS NULL'); } catch(e){ debugPrint('skip: $e'); }
        }
        if (from < 16) {
          debugPrint('[Migration] Starting v16 migration (processed_by auditing)...');
          try { await m.addColumn(salesInvoices, salesInvoices.processedByUserId); } catch(e){ debugPrint('skip: $e'); }
        }
      },
      beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
      },
    );
  }

  Future<void> _seedDefaultRoles(Migrator m) async {
    // We execute SQL directly for seeding because DAOs might not be fully functional during migrations yet.
    debugPrint('[Seed] Starting default data seeding...');
    
    try {
      // 0. Ensure tables exist before inserting (extra safety for "no such table" errors)
      // Drift's createTable is usually safer than raw SQL for this.
      try { await m.createTable(roles); } catch (_) {}
      try { await m.createTable(permissions); } catch (_) {}
      try { await m.createTable(rolePermissions); } catch (_) {}
      try { await m.createTable(usersTable); } catch (_) {}

      // 1. Insert Default Roles
      try { await customStatement("INSERT OR IGNORE INTO roles (id, role_name, description, is_system) VALUES (1, 'المالك', 'صلاحيات كاملة على النظام', 1)"); } catch (e) { debugPrint('[Seed] roles error: $e'); }
      try { await customStatement("INSERT OR IGNORE INTO roles (id, role_name, description, is_system) VALUES (2, 'مدير', 'إدارة المنتجات والمخزون والموظفين', 1)"); } catch (e) { debugPrint('[Seed] roles error: $e'); }
      try { await customStatement("INSERT OR IGNORE INTO roles (id, role_name, description, is_system) VALUES (3, 'كاشير', 'نقاط البيع والفواتير فقط', 1)"); } catch (e) { debugPrint('[Seed] roles error: $e'); }
      try { await customStatement("INSERT OR IGNORE INTO roles (id, role_name, description, is_system) VALUES (4, 'موظف مخزن', 'إدارة المخزون والموردين', 1)"); } catch (e) { debugPrint('[Seed] roles error: $e'); }
      
      // Update existing default roles to be system roles (in case of migration)
      try { await customStatement("UPDATE roles SET is_system = 1 WHERE id IN (1, 2, 3, 4)"); } catch (_) {}

      // 2. Insert Default Permissions
      final defaultPerms = [
        (1, 'pos.sell', 'تشغيل نقطة البيع وتمشية الفواتير'),
        (2, 'pos.discount', 'إضافة خصومات على الفواتير'),
        (3, 'pos.refund', 'إجراء مرتجعات (ضمن الحدود)'),
        (4, 'pos.full_refund', 'إرجاع فاتورة كاملة'),
        (5, 'products.view', 'عرض قائمة المنتجات'),
        (6, 'products.edit', 'إضافة وتعديل المنتجات والأقسام'),
        (7, 'purchases.view', 'عرض وإدارة المشتريات والموردين'),
        (8, 'reports.view', 'الاطلاع على التقارير المالية'),
        (9, 'settings.edit', 'تغيير إعدادات النظام'),
        (10, 'users.manage', 'إدارة المستخدمين والصلاحيات'),
      ];
      for (var p in defaultPerms) {
        try {
          await customStatement("INSERT OR IGNORE INTO permissions (id, permission_key, description) VALUES (${p.$1}, '${p.$2}', '${p.$3}')");
          
          // Admin (Role 1) gets everything
          await customStatement("INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (1, ${p.$1})");
        } catch (e) {
          debugPrint('[Seed] permission ${p.$2} error: $e');
        }
      }

      // 3. System Role specific assignments
      // Manager (Role 2)
      final managerPerms = [1, 2, 3, 4, 5, 7, 8];
      for (var pid in managerPerms) {
        try { await customStatement("INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (2, $pid)"); } catch (_) {}
      }

      // Cashier (Role 3)
      final cashierPerms = [1, 2, 3, 5];
      for (var pid in cashierPerms) {
        try { await customStatement("INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (3, $pid)"); } catch (_) {}
      }

      // Store Keeper (Role 4)
      final storeKeeperPerms = [5, 6, 7];
      for (var pid in storeKeeperPerms) {
        try { await customStatement("INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (4, $pid)"); } catch (_) {}
      }

      // 4. Create Default Admin User
      try {
        await customStatement("""
          INSERT OR IGNORE INTO users (id, full_name, username, password_hash, role_id, is_active)
          VALUES (1, 'المدير العام', 'admin', '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4', 1, 1)
        """);
        debugPrint('[Seed] Admin user seeded successfully');
      } catch (e) {
        debugPrint('[Seed] admin user error: $e');
      }

      // 4. Default Walk-in Customer
      try { await customStatement("INSERT OR IGNORE INTO customers (id, name, is_active) VALUES (1, 'زبون عام', 1)"); } catch (_) {}
      
      debugPrint('[Seed] Seeding completed successfully');
    } catch (e) {
      debugPrint('[Seed] Critical failure during seeding: $e');
      // We don't rethrow here to allow the migration to complete version increment even if seeding has issues
    }
  }

  /// Seed default application settings into app_settings.
  /// Uses INSERT OR IGNORE so existing values are never overwritten.
  Future<void> _seedDefaultSettings() async {
    debugPrint('[Seed] Seeding default app settings...');
    final defaults = [
      ('loyalty_enabled',   '1',    'تفعيل نظام نقاط الولاء'),
      ('points_per_currency', '0.1', 'عدد النقاط لكل وحدة نقد'),
      ('redemption_value',  '0.05', 'قيمة النقطة الواحدة عند الاسترداد (بالعملة)'),
    ];
    for (final d in defaults) {
      try {
        await customStatement(
          "INSERT OR IGNORE INTO app_settings (key, value, description) VALUES (?, ?, ?)",
          [d.$1, d.$2, d.$3],
        );
      } catch (e) {
        debugPrint('[Seed] app_settings ${d.$1} skip: $e');
      }
    }
    debugPrint('[Seed] Default app settings seeded.');
  }

  /// Configure a custom database path (for LAN shared DB)
  static Future<void> setCustomPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('db_custom_path', path);
    _instance = null; // Force re-open on next access
  }

  static Future<String?> getCustomPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('db_custom_path');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString('db_custom_path');

    File dbFile;
    if (customPath != null && customPath.isNotEmpty) {
      dbFile = File(customPath);
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(p.join(appDir.path, 'LezPOS'));
      if (!dbDir.existsSync()) dbDir.createSync(recursive: true);
      dbFile = File(p.join(dbDir.path, 'lez_pos.db'));
    }

    return NativeDatabase.createInBackground(dbFile, logStatements: false);
  });
}
