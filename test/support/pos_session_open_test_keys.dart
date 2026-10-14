// test/support/pos_session_open_test_keys.dart

import 'package:uuid/uuid.dart';

const _b25OpenUuid = Uuid();

String b25SessionOpenKey([String suffix = '']) =>
    'b25-open-${suffix.isEmpty ? _b25OpenUuid.v4() : suffix}';
