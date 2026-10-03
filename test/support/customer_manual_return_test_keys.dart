import 'package:uuid/uuid.dart';

const _b10TestUuid = Uuid();

String b10ManualReturnIdempotencyKey() => _b10TestUuid.v4();
