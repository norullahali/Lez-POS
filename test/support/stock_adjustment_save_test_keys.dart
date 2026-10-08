// test/support/stock_adjustment_save_test_keys.dart

import 'package:uuid/uuid.dart';

const _b21TestUuid = Uuid();

String b21StockAdjustmentSaveIdempotencyKey() => _b21TestUuid.v4();
