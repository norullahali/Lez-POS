# Review: Purchase Barcode Search Fix

**Date:** 2026-05-11
**File modified:** lib/features/purchases/screens/purchase_form_screen.dart
**No stock logic, save logic, or UI design was modified.**

---

## Root Cause — Why the Behavior Was Intermittent

Three bugs in _PurchaseFormScreenState combined to produce non-deterministic results.

---

### Bug 1 — _showAddItemDialog was never awaited (primary cause)

Location: _addByBarcode() method

Before:
  _showAddItemDialog(...);   // NOT awaited
  _barcodeCtrl.clear();     // runs BEFORE dialog finishes opening
  _barcodeFocus.requestFocus(); // runs BEFORE dialog is shown

_showAddItemDialog is itself async and calls await showDialog(...) internally.
Calling it without await starts its execution up to the first suspension point
and immediately returns a dangling Future. _barcodeCtrl.clear() and
_barcodeFocus.requestFocus() execute synchronously on the same event-loop tick,
BEFORE the dialog has even been painted to the screen.

Consequence:
- The barcode field is cleared while the dialog is still opening.
- Focus returns to the barcode field while the dialog animation is mid-way.
- If the scanner is fast (all HID scanners are), it can inject a second barcode
  into the already-focused field while the first dialog is still being shown.
  onSubmitted fires for the second barcode, starting a second concurrent call.

---

### Bug 2 — No re-entrancy guard (amplifies Bug 1)

Before: No guard existed. Multiple overlapping calls to _addByBarcode could run.

What happened:
1. Call A starts: findByBarcode("111") — async, yields.
2. Focus immediately returns to field (Bug 1).
3. Scanner sends "222". onSubmitted fires -> Call B starts: findByBarcode("222").
4. Call A resolves -> opens dialog for product "111".
5. Call B resolves -> tries to open a second dialog for "222" on top.

In some orderings, _barcodeCtrl.clear() from Call A runs between the scanner
sending "222" and onSubmitted firing for "222", so Call B receives an empty
string and silently returns — making the product disappear entirely.

---

### Bug 3 — The dropdown Consumer never reacted to typing

Location: Consumer widget inside the Add Product card.

Before:
  // initState:
  _barcodeCtrl.addListener(() {}); // no-op, does nothing

  // In build:
  Consumer(builder: (ctx, r, _) {
    final productsAsync = ref.watch(productsNotifierProvider);
    // productsNotifierProvider emits ONCE on load.
    // At that moment _barcodeCtrl.text is empty -> SizedBox returned forever.
    if (_barcodeCtrl.text.isEmpty) return SizedBox.shrink();
  })

The dropdown was visually non-functional. The addListener no-op never triggered
a rebuild.

---

## Exact Fixes Applied

### Fix 1 — await the dialog + move cleanup to finally

  Future<void> _addByBarcode(String barcode) async {
    barcode = barcode.trim();
    if (barcode.isEmpty) return;

    if (_isBarcodeProcessing) {
      debugPrint('[Purchase] Barcode ignored -- already processing a scan.');
      return;
    }

    debugPrint('[Purchase] Barcode scan triggered: "$barcode"');
    _isBarcodeProcessing = true;

    try {
      final repo = ref.read(productsRepositoryProvider);
      debugPrint('[Purchase] Searching DB for barcode: "$barcode"');
      final product = await repo.findByBarcode(barcode);

      if (!mounted) return;

      if (product != null) {
        debugPrint('[Purchase] Product found: "${product.name}" (id=${product.id})');
        await _showAddItemDialog(   // NOW awaited
            product.id!, product.name, product.unit, product.costPrice);
      } else {
        debugPrint('[Purchase] No product found for barcode: "$barcode"');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('لم يتم العثور على منتج: $barcode'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
          ));
        }
      }
    } finally {
      _isBarcodeProcessing = false;
      if (mounted) {
        _barcodeCtrl.clear();          // only after dialog fully closes
        _barcodeFocus.requestFocus();  // only after dialog fully closes
        debugPrint('[Purchase] Barcode field cleared, focus restored.');
      }
    }
  }

Why this fixes the intermittency:
- await _showAddItemDialog(...) suspends _addByBarcode until the dialog is
  dismissed. _barcodeCtrl.clear() and requestFocus() only run after the dialog
  is gone -- no window for accidental second-scan injection.
- The finally block guarantees cleanup even if findByBarcode throws.
- if (!mounted) return prevents calling _showAddItemDialog on a disposed widget.

### Fix 2 — Re-entrancy guard

  bool _isBarcodeProcessing = false;

If a scan is already being processed, any new onSubmitted call returns
immediately with a log message. When the first dialog closes, the finally block
resets the flag and restores focus, making the field ready for the next scan.

### Fix 3 — Reactive dropdown via ValueListenableBuilder

Before: Consumer watching productsNotifierProvider (emits once, dropdown frozen).

After: ValueListenableBuilder<TextEditingValue> wrapping the Consumer.

TextEditingController extends ValueNotifier<TextEditingValue>.
ValueListenableBuilder subscribes to it and rebuilds its subtree on every
character change. The inner Consumer still watches productsNotifierProvider
for the actual product list. Visual output and layout are unchanged.

The no-op _barcodeCtrl.addListener(() {}) in initState was removed.

### Fix 4 — User feedback when barcode not found

A SnackBar is shown for 2 seconds with the unmatched barcode text, making the
"not found" case visible to the user instead of silently clearing the field.

---

## Debug Logs Added

All logs are tagged [Purchase]:

  [Purchase] Barcode scan triggered: "..."     -- onSubmitted fired, guard clear
  [Purchase] Searching DB for barcode: "..."   -- findByBarcode starting
  [Purchase] Product found: "..." (id=...)     -- match found, dialog opening
  [Purchase] No product found for barcode: "..." -- DB returned null
  [Purchase] Barcode field cleared, focus restored. -- finally block ran
  [Purchase] Barcode ignored -- already processing a scan. -- guard blocked call

---

## Files NOT Modified

  purchases_repository.dart     -- findByBarcode correct (exact indexed match)
  products_repository.dart      -- already fixed in Phase 2
  purchases_provider.dart       -- save logic out of scope
  _saveInvoice()                -- out of scope
  _showAddItemDialog()          -- dialog content unchanged; call site fixed only
  All stock/inventory/POS files -- out of scope

---

## Why the Issue Was Intermittent

The race window depended on three timing factors:

  findByBarcode DB latency   -> how long the guard is missing
  Scanner speed              -> whether a second onSubmitted fires inside the window
  Dialog animation duration  -> how long the focus is contested (~300 ms)

On a fast local SQLite read (< 1 ms) the race window was tiny -- the dialog
opened before the scanner could fire again, making it look like it worked.
On a slightly slower read (e.g., first open after cold start, or when the DB is
under load from a parallel write), the window was large enough for a second scan
to race in, causing the product to not appear. This explains the "sometimes
works, sometimes does not" pattern.
