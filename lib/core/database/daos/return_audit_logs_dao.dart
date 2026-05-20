// lib/core/database/daos/return_audit_logs_dao.dart
//
// IMMUTABILITY CONTRACT:
//   - This DAO has NO update methods.
//   - This DAO has NO delete methods.
//   - Every row is append-only and permanent.
//   - All writes MUST occur inside the enclosing return DB transaction so
//     that a failed return leaves no orphan audit row.
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/return_audit_logs_table.dart';

part 'return_audit_logs_dao.g.dart';

@DriftAccessor(tables: [ReturnAuditLogs])
class ReturnAuditLogsDao extends DatabaseAccessor<AppDatabase>
    with _$ReturnAuditLogsDaoMixin {
  ReturnAuditLogsDao(super.db);

  // -------------------------------------------------------------------------
  // WRITE — append-only
  // -------------------------------------------------------------------------

  /// Inserts one immutable audit row.
  ///
  /// Call this from inside an existing DB transaction — it participates in
  /// the enclosing transaction automatically (no nested savepoint needed).
  Future<int> insertAuditLog({
    required String returnType,
    int? invoiceId,
    int? saleItemId,
    int? productId,
    double returnedQuantity = 0.0,
    double returnedAmount = 0.0,
    int? cashierUserId,
    String? cashierNameSnapshot,
    int? sessionId,
    int? customerId,
    String? customerNameSnapshot,
    String? returnReason,
    String? returnNote,
    double? stockBefore,
    double? stockAfter,
    String? referenceType,
    int? referenceId,
    String? deviceInfo,
    String? metadataJson,
  }) =>
      into(returnAuditLogs).insert(
        ReturnAuditLogsCompanion(
          createdAt: Value(DateTime.now()),
          returnType: Value(returnType),
          invoiceId: Value(invoiceId),
          saleItemId: Value(saleItemId),
          productId: Value(productId),
          returnedQuantity: Value(returnedQuantity),
          returnedAmount: Value(returnedAmount),
          cashierUserId: Value(cashierUserId),
          cashierNameSnapshot: Value(cashierNameSnapshot),
          sessionId: Value(sessionId),
          customerId: Value(customerId),
          customerNameSnapshot: Value(customerNameSnapshot),
          returnReason: Value(returnReason),
          returnNote: Value(returnNote),
          stockBefore: Value(stockBefore),
          stockAfter: Value(stockAfter),
          referenceType: Value(referenceType),
          referenceId: Value(referenceId),
          deviceInfo: Value(deviceInfo),
          metadataJson: Value(metadataJson),
        ),
      );

  // -------------------------------------------------------------------------
  // READ — query support for future analytics
  // -------------------------------------------------------------------------

  /// All rows, newest first (paginated).
  Future<List<ReturnAuditLog>> getPage({
    int limit = 50,
    int offset = 0,
  }) =>
      (select(returnAuditLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit, offset: offset))
          .get();

  /// Filter by calendar date range.
  Future<List<ReturnAuditLog>> getByDateRange(
    DateTime from,
    DateTime to,
  ) =>
      (select(returnAuditLogs)
            ..where((t) => t.createdAt.isBetweenValues(from, to))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// All audit rows for a specific cashier.
  Future<List<ReturnAuditLog>> getByCashier(int userId) =>
      (select(returnAuditLogs)
            ..where((t) => t.cashierUserId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// All audit rows for a specific product.
  Future<List<ReturnAuditLog>> getByProduct(int productId) =>
      (select(returnAuditLogs)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// All audit rows linked to a specific invoice.
  Future<List<ReturnAuditLog>> getByInvoice(int invoiceId) =>
      (select(returnAuditLogs)
            ..where((t) => t.invoiceId.equals(invoiceId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// Filter by return type: 'full' | 'partial' | 'smart_lookup' | 'manual_future'
  Future<List<ReturnAuditLog>> getByReturnType(String type) =>
      (select(returnAuditLogs)
            ..where((t) => t.returnType.equals(type))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// Total count — lightweight metric for future dashboard.
  Future<int> countAll() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM return_audit_logs',
      readsFrom: {returnAuditLogs},
    ).getSingleOrNull();
    return (result?.data['cnt'] as int?) ?? 0;
  }
}
