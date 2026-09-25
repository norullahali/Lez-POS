import 'package:uuid/uuid.dart';

const _refundTestUuid = Uuid();

/// Unique idempotency key for an independent customer refund test operation.
String refundTestIdempotencyKey() => _refundTestUuid.v4();
