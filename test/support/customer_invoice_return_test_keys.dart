import 'package:uuid/uuid.dart';

const _b16TestUuid = Uuid();

String b16CustomerInvoiceReturnIdempotencyKey() => _b16TestUuid.v4();