import 'cash_ledger_event_type.dart';

/// Read-only derived ledger row — no persistence.
class CashLedgerEvent {
  const CashLedgerEvent({
    required this.id,
    required this.timestamp,
    required this.eventType,
    required this.amount,
    required this.direction,
    required this.referenceType,
    required this.referenceId,
    this.userId,
    this.customerId,
    this.supplierId,
    this.invoiceId,
    required this.description,
    this.runningBalance,
  });

  final String id;
  final DateTime timestamp;
  final CashLedgerEventType eventType;
  final double amount;
  final CashLedgerDirection direction;
  final String referenceType;
  final int referenceId;
  final int? userId;
  final int? customerId;
  final int? supplierId;
  final int? invoiceId;
  final String description;
  final double? runningBalance;

  bool get isInflow => direction == CashLedgerDirection.inflow;

  CashLedgerEvent copyWith({double? runningBalance}) => CashLedgerEvent(
        id: id,
        timestamp: timestamp,
        eventType: eventType,
        amount: amount,
        direction: direction,
        referenceType: referenceType,
        referenceId: referenceId,
        userId: userId,
        customerId: customerId,
        supplierId: supplierId,
        invoiceId: invoiceId,
        description: description,
        runningBalance: runningBalance,
      );
}

enum CashLedgerDirection {
  inflow('inflow'),
  outflow('outflow');

  const CashLedgerDirection(this.code);
  final String code;

  static CashLedgerDirection fromCode(String code) =>
      code == inflow.code ? inflow : outflow;
}