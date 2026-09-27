import 'package:uuid/uuid.dart';

const _supplierRefundTestUuid = Uuid();

/// Unique idempotency key for an independent supplier refund test operation.
String supplierRefundTestIdempotencyKey() => _supplierRefundTestUuid.v4();
