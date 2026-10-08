# B21 Implementation Report — Stock Adjustment Save Protection

**Baseline:** `67456011028396db6b61baa188c40f5574d3ee8a` (schema v47)  
**Target schema:** v48  
**Status:** Implementation complete; Review Pass 1 SHOULD-FIX applied (regression narrative corrected).

## Regression (B4–B10) — verified facts

| Tree | B4–B10 suite (7 files) | Result |
|------|------------------------|--------|
| Baseline HEAD `6745601` | Full suite | **147/147 PASS** |
| B21 implementation (current) | Full suite | **147/147 PASS** |

An earlier draft of this report incorrectly stated **135 pass / 12 fail** and labeled those failures as pre-existing UI widget tests. That was **wrong**.

During implementation, **12 transient UI widget-test failures** appeared (B7/B8/B9/B10 idempotency UI lifecycle tests; typical symptom: widget finder "Expected: exactly one matching candidate"). They were **not** present at baseline `6745601`.

**Root cause:** UTF-8/BOM corruption on unrelated test files introduced during bulk PowerShell schemaVersion edits (not B21 production semantics). After reverting BOM damage and limiting schema bumps to the intended B regression files, **B4–B10 returned to 147/147 PASS** on the B21 tree.

**Production diff vs baseline for B4–B10 UI tests:** only schemaVersion expectations **47 → 48** on migration/sentinel tests; no UI/provider/production changes in purchase, supplier payment, or customer return paths.

## B21 test suite

22 tests in `test/stock_adjustment_save_protection_b21_test.dart` (design review minimum 20 + seal rollback / PK replay cases).

## Final implementation verdict (code)

**B21 IMPLEMENTATION: READY FOR REVIEW** (superseded for audit by Review Pass 1 + Review-Fix).

Post Review-Fix: see **B21 REVIEW-FIX** report for current audit readiness.