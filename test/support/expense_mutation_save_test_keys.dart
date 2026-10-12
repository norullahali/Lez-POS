import 'package:uuid/uuid.dart';

const _b22TestUuid = Uuid();

String b22ExpenseMutationIdempotencyKey() => _b22TestUuid.v4();
