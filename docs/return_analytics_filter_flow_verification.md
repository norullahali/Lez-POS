# Return Analytics - Filter Flow Runtime Verification

**Date:** 2026-05-25  
**Scope:** Runtime verification only - no app fixes applied  
**Database:** `C:\Users\zakho\Documents\LezPOS\lez_pos.db` (8 rows)  
**Method:** Transient harness via `flutter run -d windows` against live DB and production repository/provider code. Harness removed after run.

---

## Executive Finding

When Apply is simulated correctly, **providers refetch** and **do not cache stale filters**.

The dominant runtime defect is a **timestamp unit mismatch**:

| Layer | Unit | Example |
|-------|------|---------|
| SQLite `created_at` (actual) | **Seconds** | `1779736300` |
| SQL filter bind params (code) | **Milliseconds** | `1780261200000` |
| Display via `readTimestampMs` | Treats int as ms | **1970-01-21** |

Because `1779736300 < 1780261200000`, **filtered queries return 0 rows** when the filter reaches SQL. Unfiltered queries return **all 8 rows**.

If the UI shows **8 rows after Apply**, the filter is likely **not reaching SQL** (provider dates still null). If Apply works, the user should see **empty/zero** results for any date range - not full history.

---

## 1. Apply Simulation Logs

### CASE A: 2026-06-01 to 2026-06-01

```
[Apply] ReturnAnalyticsFilter SENT: fromDate=2026-06-01 00:00:00.000 toDate=2026-06-01 00:00:00.000
[Apply] NORMALIZED: fromDate=2026-06-01 00:00:00.000 toDate=2026-06-01 00:00:00.000
[Apply] startMs=1780261200000 endMs=1780347599999
[Apply] cacheKey=1780261200000_1780261200000_all_all_all
```

### CASE B: 2026-04-01 to 2026-04-01

```
[Apply] ReturnAnalyticsFilter SENT: fromDate=2026-04-01 00:00:00.000 toDate=2026-04-01 00:00:00.000
[Apply] NORMALIZED: fromDate=2026-04-01 00:00:00.000 toDate=2026-04-01 00:00:00.000
[Apply] startMs=1774990800000 endMs=1775077199999
[Apply] cacheKey=1774990800000_1774990800000_all_all_all
```

---

## 2. Live Database Evidence

```
=== DB totals: {c: 8, mn: 1779042343, mx: 1779736300} ===
sample: {id: 8, created_at: 1779736300, t: integer, return_type: partial}
```

### Timestamp interpretation (verify2)

| id | raw (DB) | As **seconds** | As **ms** (current display) |
|----|----------|----------------|----------------------------|
| 1 | 1779729179 | 2026-05-25 20:12:59 | 1970-01-21 17:22:09 |
| 8 | 1779736300 | 2026-05-25 22:11:40 | 1970-01-21 17:22:16 |

### May 25 2026 filter (day with 4 actual returns)

```
startMs=1779656400000  endMs=1779742799999
startSec=1779656400    endSec=1779742799

COUNT ms-params (current repository bind): 0
COUNT sec-params (correct for DB storage): 4
COUNT no filter: 8
repository getRecentActivityCount May25 ms-bind: 0
```

---

## 3. Per-Provider Runtime Results

### CASE A and CASE B (all filtered providers)

| Provider | Filter received | SQL WHERE | SQL params (CASE A) | Rows CASE A | Rows CASE B |
|----------|-----------------|-----------|---------------------|-------------|-------------|
| `returnOverviewProvider` | normalized dates | `WHERE created_at >= ? AND created_at <= ?` | `[1780261200000, 1780347599999]` | totalCount=**0** | totalCount=**0** |
| `returnTrendProvider` | normalized dates | `WHERE ral.created_at >= ? AND ral.created_at <= ?` | same | trendPoints=**0** | trendPoints=**0** |
| `topReturnedProductsProvider` | normalized dates | `WHERE ral.created_at >= ? AND ral.created_at <= ?` | same | **0** | **0** |
| `cashierReturnStatsProvider` | normalized dates | `WHERE created_at >= ? AND created_at <= ?` | same | **0** | **0** |
| `suspiciousFlagsProvider` | **NONE** | fixed today/7-day only | rolling ms (also mismatched) | **0 flags** | **0 flags** |
| `recentActivityProvider` | normalized dates | `WHERE ral.created_at >= ? AND ral.created_at <= ?` | same | totalCount=**0** | totalCount=**0** |

### NO FILTER baseline

```
recentActivityCount NO_FILTER: 8
overview totalCount NO_FILTER: 8
```

---

## 4. Stale Filter / Cache / Generation Check

### Repository (verify1)

```
filterA == filterB: false
recentActivityCount CASE_A: 0
recentActivityCount CASE_B: 0
recentActivityCount NO_FILTER: 8
```

### Riverpod ProviderContainer (verify3)

```
INITIAL no filter: returnOverviewProvider totalCount=8
After Apply CASE_A: returnOverviewProvider totalCount=0
After Apply CASE_B: returnOverviewProvider totalCount=0
Reset empty filter: returnOverviewProvider totalCount=8
```

| Check | Result |
|-------|--------|
| Reads stale filter? | **NO** |
| Caches old filter values? | **NO** |
| Ignores generation on filter change? | **NO** - `ref.watch(returnAnalyticsFilterProvider)` refetches |
| Rebuilds with previous state? | **NO** - transitions 8 -> 0 -> 8 correctly |

---

## 5. Provider Matrix

| Provider | Filter Received (CASE A) | SQL Filter Applied | Result Correct? | Root Cause |
|----------|--------------------------|-------------------|-----------------|------------|
| `returnOverviewProvider` | 2026-06-01 normalized | Yes (ms params) | **NO** for May 25 with data | seconds/ms mismatch |
| `returnTrendProvider` | same | Yes | **NO** | seconds/ms mismatch |
| `topReturnedProductsProvider` | same | Yes | **NO** | seconds/ms mismatch |
| `cashierReturnStatsProvider` | same | Yes | **NO** | seconds/ms mismatch |
| `suspiciousFlagsProvider` | NONE | fixed windows only | N/A | by design |
| `recentActivityProvider` | same | Yes | **NO** | seconds/ms + readTimestampMs |

**May 25 2026:** ms bind returns 0 rows; sec bind returns 4 rows (correct).

---

## 6. Symptom Reconciliation

| User report | Runtime evidence |
|-------------|------------------|
| Data still appears after Apply | **8 rows = NO FILTER path.** Filtered path with ms params returns **0**, not 8. |
| All historical returns | Matches empty WHERE (8 rows). Does not match ms-filtered SQL. |
| ~1970 dates | DB stores seconds; display reads as ms. |

---

## 7. Root Cause Summary

1. **`created_at` stored as epoch seconds; SQL binds epoch milliseconds (95%)**
2. **`readTimestampMs` treats seconds as ms (95%)**
3. **UI/provider sync if user sees 8 after Apply (60%)** - provider test shows Apply yields 0 rows when filter reaches SQL
4. **Provider stale cache: RULED OUT**

---

*End of report.*
