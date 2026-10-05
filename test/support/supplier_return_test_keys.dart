import 'package:uuid/uuid.dart';

const _b15TestUuid = Uuid();

String b15SupplierReturnIdempotencyKey() => _b15TestUuid.v4();
