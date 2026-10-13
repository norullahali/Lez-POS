import 'package:uuid/uuid.dart';

const _b23TestUuid = Uuid();

String b23OtherIncomeMutationIdempotencyKey() => _b23TestUuid.v4();
