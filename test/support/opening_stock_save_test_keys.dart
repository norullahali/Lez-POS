// test/support/opening_stock_save_test_keys.dart

import 'package:uuid/uuid.dart';

const _b20TestUuid = Uuid();

String b20OpeningStockSaveIdempotencyKey() => _b20TestUuid.v4();