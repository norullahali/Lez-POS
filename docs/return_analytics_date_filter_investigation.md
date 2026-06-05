# Return Analytics - Date Filtering Root-Cause Investigation

**Date:** 2026-05-25  
**Scope:** Forensic diagnosis only - no code changes applied  
**Symptoms:** Filters appear applied but results show all historical returns; some rows displayed ~1970 dates; KPI cards and recent activity otherwise load correctly.

---

## Executive Summary

Return Analytics **can** filter by date in SQL, but two defects explain the reported behavior:

| Issue | Category | Effect |
|-------|----------|--------|
| UI local state vs provider state desync | UI filter sync | Date chips turn active on pick, but `returnAnalyticsFilterProvider` keeps `fromDate`/`toDate` **null** until the user clicks **Apply**. With null dates, `_whereFilter()` emits an **empty WHERE clause** and queries return **all rows**. |
| `readTimestampMs()` treats all integers as milliseconds | Timestamp conversion | Unlike other repositories, analytics does not detect seconds vs milliseconds. Raw second values, `0`, or unparseable values produce **1970-era display dates** in Recent Activity. |

**Perceived gaps (by design):** `getSuspiciousFlags()` and overview today/week/month cards use fixed rolling windows and ignore the user-selected date range.

**Primary root cause:** UI filter sync - visual filter state is not query filter state.  
**Secondary root cause:** Timestamp conversion in `readTimestampMs()` / `getRecentActivity()`.  
**Confidence:** 82% (primary), 78% (1970 dates) - static analysis; live DB unavailable.

---

## A) Data Storage Layer

### Schema: `return_audit_logs`

**File:** `lib/core/database/tables/return_audit_logs_table.dart`

| Column | Drift type | Notes |
|--------|------------|-------|
| `id` | `IntColumn` | PK AUTOINCREMENT |
| **`created_at`** | **`DateTimeColumn` (`dateTime()`)** | **Only date/time column**; required on insert |
| `return_type` | `TextColumn` | full, partial, smart_lookup, etc. |

Generated mapping (`app_database.g.dart`):

```dart
late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at', aliasedName, false,
    type: DriftSqlType.dateTime, requiredDuringInsert: true);
```

### Expected storage format

- Drift `DriftSqlType.dateTime` on native SQLite: **INTEGER Unix epoch milliseconds (UTC)** when written via ORM (`insertAuditLog` uses `Value(DateTime.now())`).
- Not ISO strings at rest; not microseconds (no `microsecondsSinceEpoch` in `lib/`).
- **v28 backfill** copies `cr.return_date` and `sir.created_at` (both `DateTimeColumn`) into `return_audit_logs.created_at` as raw SQLite values.

### Sample stored values (predicted - no live DB)

| Source | Example raw value | Meaning |
|--------|-------------------|---------|
| Live DAO insert | `1748169600000` (13 digits) | ms epoch |
| Seconds mis-store | `1748169600` (10 digits) | same instant if read as seconds |
| NULL / bad parse | NULL or garbage | becomes **0 ms** -> **1970-01-01** in UI |

**Evidence:** Trend SQL uses `DATE(ral.created_at / 1000, 'unixepoch', 'localtime')` (`return_analytics_repository.dart` ~198). Same `/1000` pattern in `advanced_analytics_repository.dart`.

---

## B) Repository Layer - Query Audit

**File:** `lib/features/returns/repositories/return_analytics_repository.dart`

### `_whereFilter()` behavior

```dart
if (f.fromDate != null) {
  parts.add('${p}created_at >= ?');
  vars.add(Variable.withInt(ReturnAnalyticsDateUtils.startMs(f.fromDate!)));
}
if (f.toDate != null) {
  parts.add('${p}created_at <= ?');
  vars.add(Variable.withInt(ReturnAnalyticsDateUtils.endMs(f.toDate!)));
}
if (parts.isEmpty) return const _SqlFilter('', []);
```

**If both dates null:** empty clause -> **all rows**.

### Per-query summary

| Query | Date filter? | Column | Start/end | SQL/Dart | All rows when dates null? |
|-------|--------------|--------|-----------|----------|---------------------------|
| **getOverview** (totals) | If dates set | `created_at` | `startMs` / `endMs` | SQL | **Yes** |
| **getOverview** (today/week/month) | User filter + rolling windows | `created_at` | `todayStartMs`, etc. | SQL | Partial |
| **getDailyTrend** | **Always** | `ral.created_at` | user dates or last 30 days | SQL | No (max ~30d) |
| **getTopProducts** | If dates set | `ral.created_at` | `startMs` / `endMs` | SQL | **Yes** |
| **getCashierStats** | If dates set | `created_at` | `startMs` / `endMs` | SQL | **Yes** |
| **getSuspiciousFlags** | **No user filter** | fixed today / 7-day | `todayMs`, `sevenDaysAgo` | SQL | Ignores UI range |
| **getRecentActivity** | If dates set | `ral.created_at` | `startMs` / `endMs` | SQL filter; Dart display | **Yes** |
| Filter dropdowns | None | - | - | SQL | Always all-time options |

Filtering is **always in SQL**, never post-filtered in Dart (except timestamp display for Recent Activity).

---

## C) Filter Pipeline

```
UI _TopBar: _pickDate() -> setState(_from/_to), chips active immediately
  -> NO provider update until Apply clicked

User clicks Apply:
  _apply() -> _applyFilter() -> normalizeFilter() -> returnAnalyticsFilterProvider
  -> FutureProviders ref.watch(filter) -> repository.getX(filter)
  -> _whereFilter() -> SQL WHERE created_at >= ? AND created_at <= ?
```

### Values after Apply (example: 2026-05-20 to 2026-05-20)

| Step | Value |
|------|-------|
| Provider `fromDate` / `toDate` | `2026-05-20 00:00:00.000` local (both normalized to startOfDay) |
| `startMs(fromDate)` | start of day in epoch ms (timezone-dependent) |
| `endMs(toDate)` | end of same day 23:59:59.999 in epoch ms |
| SQL | `WHERE ral.created_at >= ? AND ral.created_at <= ?` |

### Values when dates picked but Apply NOT clicked

| Step | Value |
|------|-------|
| UI chips | Active (dates visible) |
| Provider dates | **null** |
| `_whereFilter()` | **empty** |
| Result | **All historical rows** |

Matches symptoms #4 and #6.

**Note:** Date picker `lastDate: DateTime.now()` prevents selecting 2026-06-01 as of 2026-05-25; Section E uses that range hypothetically.

---

## D) Timestamp Conversion Audit

### Return Analytics usages

| File | API |
|------|-----|
| `return_analytics_date_utils.dart` | `startMs`, `endMs`, `readTimestampMs` |
| `return_analytics_repository.dart` | `Variable.withInt(...)`, `DateTime.fromMillisecondsSinceEpoch(readTimestampMs(...))` |

### `readTimestampMs()` (lines 49-58)

- `int` -> returned as-is (**no seconds/ms threshold**)
- `null` / unparseable -> **0**
- `DateTime` -> `millisecondsSinceEpoch`

### Contrast: `smart_return_lookup_repository.dart`

Uses threshold `100000000000`: values below are treated as **seconds** and multiplied by 1000.

### Why ~1970 dates appeared

1. `readTimestampMs` returns **0** for null/unparseable -> epoch 1970-01-01.
2. Integer **seconds** passed to `fromMillisecondsSinceEpoch` without `* 1000` -> dates in January 1970 (e.g. `1748169600` ms = ~1970-01-21).

**Not found:** `fromMicrosecondsSinceEpoch`, `fromSecondsSinceEpoch`, `microsecondsSinceEpoch`.

---

## E) Runtime Verification

**NOT EXECUTED** - per DO NOT modify code; no debug logging added; `lez_pos.db` not found on investigation machine.

### Predicted log: Apply 2026-06-01 to 2026-06-01 (hypothetical, UTC+3 example)

```
selectedStart: 2026-06-01 00:00:00.000
selectedEnd:   2026-06-01 00:00:00.000
normalizedStartMs: 1780270800000
normalizedEndMs:   1780357199999
sqlClause: WHERE ral.created_at >= ? AND ral.created_at <= ?
rowsReturned: 0
```

### Predicted log: dates picked, Apply NOT clicked

```
normalizedStartMs: (none)
normalizedEndMs: (none)
sqlClause: (empty)
rowsReturned: N (ALL audit rows)
```

**Suggested DB check:**

```sql
SELECT id, created_at, typeof(created_at), return_type
FROM return_audit_logs ORDER BY id DESC LIMIT 10;
```

---

## F) Final Conclusion

### 1. Exact root cause

- **Primary:** `_TopBar` shows active date chips from local `_from`/`_to` immediately, but `returnAnalyticsFilterProvider` updates only on **Apply**. Until then SQL has no date predicate -> all rows.
- **Secondary:** `readTimestampMs()` lacks seconds/ms detection -> 1970-era Recent Activity dates.
- **Contributing (by design):** Suspicious flags and today/week/month KPI cards ignore user date range.

### 2. Confidence

| Finding | Level |
|---------|-------|
| Empty WHERE / UI sync | 82% |
| 1970 timestamp conversion | 78% |
| Combined explanation | 80% |

### 3. Files involved

- `lib/features/returns/screens/return_analytics_dashboard_screen.dart`
- `lib/features/returns/providers/return_analytics_provider.dart`
- `lib/features/returns/utils/return_analytics_date_utils.dart`
- `lib/features/returns/repositories/return_analytics_repository.dart`
- `lib/core/database/tables/return_audit_logs_table.dart`
- `lib/core/database/daos/return_audit_logs_dao.dart`
- `lib/core/database/app_database.dart` (v28 backfill)
- `lib/features/returns/repositories/smart_return_lookup_repository.dart` (reference parser)

### 4. Minimal fix (not implemented)

1. Auto-sync date picks to `returnAnalyticsFilterProvider` (or auto-apply on pick).
2. Add seconds/ms threshold to `readTimestampMs()` like other repos.
3. Optionally scope suspicious flags / rolling KPI cards to user filter.

### 5. Classification

**Multiple issues combined:** UI filter sync (primary), provider state (consequence), SQL filtering (correct when dates present), timestamp conversion (secondary).

---

*End of investigation report.*
