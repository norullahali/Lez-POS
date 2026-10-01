import 'package:uuid/uuid.dart';

const _b7TestUuid = Uuid();

String b7PurchaseIdempotencyKey() => _b7TestUuid.v4();
