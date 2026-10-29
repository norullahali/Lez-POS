# B41 Stage 1 — Printer Settings Guard — Implementation Report

**Date:** 2026-10-28  
**Scope:** B41 Stage 1 only (printer settings validation / unsupported-type guard)  
**Baseline:** `ce3586b91cf9ce532ae3616bdf3dcde25422bc36` on `main` (= `origin/main`, 0/0)

---

## 1. Baseline and initial working-tree status

| Check | Result |
|-------|--------|
| Branch | `main` |
| HEAD | `ce3586b91cf9ce532ae3616bdf3dcde25422bc36` |
| `origin/main` | Matches HEAD |
| Staged tracked changes | None |
| Unstaged tracked changes (start) | None |
| Untracked | Pre-existing `docs/*`, `tool/*` preserved |

Preflight completed before edits. No reset, stash, stage, commit, or push.

---

## 2. Relevant files inspected

| Area | Path |
|------|------|
| Router | `lib/core/printing/print_manager.dart` |
| Config model | `lib/core/printing/printer_config.dart` |
| PDF adapter | `lib/core/printing/adapters/pdf_printer_adapter.dart` |
| USB thermal | `lib/core/printing/adapters/usb_thermal_printer_adapter.dart` |
| LAN stub | `lib/core/printing/adapters/lan_thermal_printer_adapter.dart` (`UnimplementedError` in `sendBytes`) |
| Bluetooth stub | `lib/core/printing/adapters/bluetooth_thermal_printer_adapter.dart` (same) |
| Persistence | `lib/core/services/settings_service.dart` (`getPrinterConfig` / `savePrinterConfig`) |
| Settings UI | `lib/features/settings/screens/invoice_settings_screen.dart` |
| Production print entry | `lib/core/services/receipt_service.dart` → `PrintManager` |
| Design reference | `docs/b41_thermal_printing_design_review.md` |

---

## 3. Findings — printer support and persistence

### Implementation status (verified in source)

| `PrinterType` | Delivery path | Stage 1 treatment |
|---------------|---------------|-------------------|
| `pdf` | `PdfPrinterAdapter` + `Printing.layoutPdf` | **Supported** |
| `usbThermal` | `UsbThermalPrinterAdapter` + `RawWindowsPrinter` | **Supported** |
| `lanThermal` | ESC/POS built; `sendBytes` throws `UnimplementedError` | **Not supported** — guarded before adapter |
| `bluetoothThermal` | Same as LAN | **Not supported** — guarded before adapter |

### Persistence (unchanged semantics)

- Printer type and connection fields persist in `app_settings` via `SettingsService.savePrinterConfig`.
- **No** automatic migration or silent rewrite of saved type on print failure.
- Invalid/unknown type strings still fall back to `pdf` only at **load** time (`firstWhere` `orElse`) — pre-existing behavior, not introduced in Stage 1.

### Before Stage 1

- `PrintManager.print()` always built LAN/BT adapters → checkout/settings test print could surface raw `UnimplementedError`.
- Settings dropdown allowed selecting LAN/BT as if operational.
- Saved LAN/BT configs were already persisted but unsafe at print time.

---

## 4. Files changed and rationale

| File | Change |
|------|--------|
| `lib/core/printing/printer_type_support.dart` | **New.** Canonical set of types with operational print delivery (`pdf`, `usbThermal`). |
| `lib/core/printing/unsupported_printer_type_exception.dart` | **New.** Typed failure with Arabic `messageAr` for settings test print. |
| `lib/core/printing/print_manager.dart` | Guard `print()` and `isAvailable()` before adapter construction for unsupported types. |
| `lib/features/settings/screens/invoice_settings_screen.dart` | Disable LAN/BT for **new** dropdown selection; explanatory label + inline notice when saved type is unsupported; map exception to Arabic in test print only. |
| `test/print_manager_b41_stage1_test.dart` | **New.** Focused tests for guard, persistence, and support matrix. |

**Not changed:** checkout/reprint UX (still logs print errors only), receipt totals, adapters, schema, LAN/BT implementation.

---

## 5. Behavior before and after

| Scenario | Before | After |
|----------|--------|-------|
| Checkout with saved LAN/BT | `UnimplementedError` from adapter | `UnsupportedPrinterTypeException` from `PrintManager` (still caught silently at checkout — unchanged UX) |
| Settings test print, LAN/BT | `UnimplementedError` in SnackBar | Arabic `messageAr` via `UnsupportedPrinterTypeException` |
| Save/load LAN config | Persisted | **Still persisted**; IP/port fields still shown when type is LAN |
| User picks LAN/BT in dropdown | Allowed | **Disabled** for new selection; existing saved value still displayed |
| Silent switch to PDF/USB | Did not occur | **Still does not occur** |
| `isAvailable()` for LAN | `false` via adapter | `false` without invoking stub send path |

---

## 6. Tests and analysis

### Commands and results

```text
flutter test test/print_manager_b41_stage1_test.dart
→ 00:00 +7: All tests passed!

flutter analyze lib/core/printing/print_manager.dart lib/core/printing/printer_type_support.dart lib/core/printing/unsupported_printer_type_exception.dart lib/features/settings/screens/invoice_settings_screen.dart test/print_manager_b41_stage1_test.dart
→ 3 info (prefer_const_constructors in test only); no errors

git diff --check
→ (no output — clean)

dart test test/print_manager_b41_stage1_test.dart
→ FAILED — project uses flutter_test; use flutter test (documented limitation)
```

### Test coverage (7 cases)

1. PDF/USB marked supported in `PrinterTypeSupport`.
2. LAN/BT marked unsupported.
3. LAN print throws `UnsupportedPrinterTypeException` (not `UnimplementedError`).
4. Bluetooth print throws `UnsupportedPrinterTypeException`.
5. `isAvailable()` false for LAN without adapter send.
6. Saved `lanThermal` config unchanged after guarded print attempt.
7. `usbThermal` config round-trip via `SettingsService`.

**Physical printer:** Not tested (not required for Stage 1).

---

## 7. Known limitations and manual verification

- **Checkout/reprint** still swallow all print errors (no SnackBar) — intentional; Stage 2 contract not in scope.
- **USB thermal** on non-Windows may fail at adapter layer; still considered “supported” in matrix (Windows desktop target).
- **Legacy invalid** `printer_type` DB values still map to PDF on read — unchanged.
- **Manual QA suggested:** Open invoice settings with a pre-saved LAN type → dropdown shows LAN, notice visible, test print shows Arabic message, save/restart → type still LAN.

---

## 8. Final Git status

**Modified (tracked):**

- `lib/core/printing/print_manager.dart`
- `lib/features/settings/screens/invoice_settings_screen.dart`

**New (untracked):**

- `lib/core/printing/printer_type_support.dart`
- `lib/core/printing/unsupported_printer_type_exception.dart`
- `test/print_manager_b41_stage1_test.dart`
- `docs/b41_stage1_printer_settings_guard_report.md`

**Not staged, not committed, not pushed.** All pre-existing untracked `docs/` and `tool/` files preserved.

---

## 9. Stage boundary

Stage 1 complete. Stage 2+ (print result contract, receipt fidelity, raster Arabic/Kurdish, etc.) **not** started. Awaiting review and authorization before proceeding.
