# Thermal Printing Architecture — Lez POS

> Last updated: 2026-05-11
> Status: USB thermal printing **IMPLEMENTED**. LAN and Bluetooth pending.

---

## 1. Overview

Lez POS uses a **layered adapter pattern** to decouple invoice business logic
from printer hardware. The same `InvoiceData` object is handed to `PrintManager`,
which routes it through the correct adapter based on the active `PrinterConfig`.

```
Receipt/Sale screen
        |
        v
  ReceiptService
        |
        v
  PrintManager(config)          <- central router
        |
        |-- pdf            -----> PdfPrinterAdapter
        |                             InvoicePdfBuilderClean  (PDF layout)
        |                             package:printing        (OS print dialog)
        |
        |-- usbThermal     -----> UsbThermalPrinterAdapter      [IMPLEMENTED]
        |                             ThermalPrinterAdapter   (base, logging)
        |                             EscPosBuilder           (ESC/POS bytes)
        |                             RawWindowsPrinter       (win32 I/O)
        |                               OpenPrinter -> StartDocPrinter
        |                               -> WritePrinter -> ClosePrinter
        |
        |-- lanThermal     -----> LanThermalPrinterAdapter      [TODO]
        |                             ThermalPrinterAdapter   (base, logging)
        |                             EscPosBuilder           (ESC/POS bytes)
        |                             dart:io Socket          [TODO]
        |
        `-- bluetoothThermal ---> BluetoothThermalPrinterAdapter  [TODO]
                                      ThermalPrinterAdapter   (base, logging)
                                      EscPosBuilder           (ESC/POS bytes)
                                      RFCOMM / BT plugin      [TODO]
```

---

## 2. File Map

```
lib/core/printing/
|-- printer_adapter.dart          Abstract base: print(InvoiceData) + isAvailable()
|-- printer_capabilities.dart     Hardware feature model (cut, drawer, cols, encoding)
|-- printer_config.dart           Immutable settings snapshot (type, IP, name, paper)
|-- print_manager.dart            Central router — selects adapter, structured logs
|
|-- thermal/
|   |-- esc_pos_builder.dart      Pure-Dart ESC/POS byte builder (no packages)
|   `-- thermal_printer_adapter.dart  Abstract base for USB/LAN/BT adapters
|
|-- discovery/
|   `-- printer_discovery.dart    Discovery abstraction + stubs (NoOp/LAN/USB)
|
|-- windows/
|   `-- raw_windows_printer.dart  [NEW] win32 RAW printer — all FFI calls here
|
`-- adapters/
    |-- pdf_printer_adapter.dart              PDF printing        [WORKING]
    |-- usb_thermal_printer_adapter.dart      USB ESC/POS RAW     [IMPLEMENTED]
    |-- lan_thermal_printer_adapter.dart      LAN TCP ESC/POS     [TODO]
    `-- bluetooth_thermal_printer_adapter.dart  BT ESC/POS        [TODO]
```

---

## 3. Class Hierarchy

```
PrinterAdapter (abstract)
|-- PdfPrinterAdapter                  [WORKING]  package:printing
`-- ThermalPrinterAdapter (abstract)              sealed print() + logging
    |-- UsbThermalPrinterAdapter       [IMPLEMENTED] win32 WritePrinter
    |-- LanThermalPrinterAdapter       [TODO]     dart:io Socket
    `-- BluetoothThermalPrinterAdapter [TODO]     RFCOMM
```

### ThermalPrinterAdapter sealed flow

```
print(InvoiceData)                        <- @nonVirtual
  |
  |-- buildBytes(data)                    <- overridable
  |     `-- EscPosBuilder.fromInvoice(data, capabilities)
  |           init -> codePage -> header -> metadata -> items
  |           -> totals -> footer -> feed -> cut (if caps.supportsCut)
  |
  `-- sendBytes(bytes)                    <- subclass implements
        [UsbThermalPrinterAdapter]
        `-- RawWindowsPrinter.send(bytes, printerName)
              OpenPrinter -> StartDocPrinter -> StartPagePrinter
              -> WritePrinter -> EndPagePrinter -> EndDocPrinter
              -> ClosePrinter
```

---

## 4. USB RAW Print Flow (Windows)

### Windows API Call Sequence

```
OpenPrinter(printerName, &hPrinter, NULL)
    |
    v (hPrinter obtained)
StartDocPrinter(hPrinter, 1, &DOC_INFO_1{pDatatype="RAW"})
    |
    v (job ID obtained)
StartPagePrinter(hPrinter)
    |
    v
WritePrinter(hPrinter, pBytes, byteCount, &written)
    |
    v
EndPagePrinter(hPrinter)
    |
    v
EndDocPrinter(hPrinter)
    |
    v
ClosePrinter(hPrinter)
```

### Memory Safety Guarantees in RawWindowsPrinter

All native allocations are declared before the try block.
A single `finally` clause always frees every pointer:

```
phPrinter  = calloc<IntPtr>()        <- printer handle
pName      = TEXT(printerName)       <- printer name (UTF-16)
pDocName   = TEXT(docName)           <- job title (UTF-16)
pDatatype  = TEXT('RAW')             <- data type string (UTF-16)
docInfo    = calloc<DOC_INFO_1>()    <- print job descriptor
pData      = calloc<Uint8>(n)        <- ESC/POS byte buffer (n bytes)
pWritten   = calloc<Uint32>()        <- written byte count

finally {
  calloc.free(pData);
  calloc.free(pWritten);
  calloc.free(docInfo);
  calloc.free(pDatatype);
  calloc.free(pDocName);
  calloc.free(pName);
  calloc.free(phPrinter);
}
```

### Error Codes and Exceptions

| Win32 Code | Constant              | Exception thrown            |
|------------|-----------------------|-----------------------------|
| 2          | ERROR_FILE_NOT_FOUND  | PrinterNotFoundException    |
| 1801       | ERROR_INVALID_PRINTER_NAME | PrinterNotFoundException |
| 5          | ERROR_ACCESS_DENIED   | PrinterWriteException       |
| 6          | ERROR_INVALID_HANDLE  | PrinterWriteException       |
| any other  | —                     | PrinterWriteException       |

---

## 5. PrinterCapabilities Presets

| Preset            | Paper | Cols | Cut | Drawer | CP   |
|-------------------|-------|------|-----|--------|------|
| thermal58Usb      | 58mm  | 32   | yes | no     | 33   |
| thermal80Usb      | 80mm  | 48   | yes | yes    | 33   |
| thermal80Lan      | 80mm  | 48   | yes | yes    | 33   |
| thermal58Bt       | 58mm  | 32   | no  | no     | 33   |
| pdfVirtual        | A4    | 80   | no  | no     | null |

CP = codePageId (33 = CP1256 Windows Arabic)

---

## 6. EscPosBuilder Command Reference

| Method              | ESC/POS      | Notes                            |
|---------------------|--------------|----------------------------------|
| init()              | ESC @        | Always call first                |
| selectCodePage(n)   | ESC t n      | Arabic: 33 (CP1256)              |
| alignLeft/Center/Right() | ESC a 0/1/2 |                            |
| boldOn/Off()        | ESC E 1/0    |                                  |
| doubleSizeOn()      | ESC ! 0x30   | 2x width + height                |
| normalSize()        | ESC ! 0x00   | Reset size                       |
| underlineOn/Off()   | ESC - 1/0    |                                  |
| line(text)          | bytes + LF   |                                  |
| arabicLine(text)    | reversed+LF  | For LTR-only firmware            |
| feed(n)             | n x LF       |                                  |
| separator(w)        | '-' x w + LF |                                  |
| kvRow(l, v, w)      | padded + LF  | label...value                    |
| cut(full)           | GS V 0/1     | full=true = full cut             |
| drawerKick()        | ESC p 0 t t  | Opens cash drawer                |

High-level:
```dart
final bytes = EscPosBuilder.fromInvoice(invoiceData, PrinterCapabilities.thermal80Usb);
```

---

## 7. Debug Log Format

```
[PrintManager] === Print job started =======================
[PrintManager]   Printer type : usbThermal
[PrintManager]   Paper size   : thermal80
[PrintManager]   Printer name : XP-80
[PrintManager]   Invoice #    : POS-20260511-0042
[PrintManager]   Items        : 5
[PrintManager]   Total        : 27500 IQD
[PrintManager]   Adapter      : UsbThermalPrinterAdapter
[UsbThermalPrinterAdapter] -- sendBytes ------------------
[UsbThermalPrinterAdapter]   Printer    : XP-80
[UsbThermalPrinterAdapter]   Paper size : thermal80
[UsbThermalPrinterAdapter]   Byte count : 824
[UsbThermalPrinterAdapter]   Cols/line  : 48
[RawWindowsPrinter] -- RAW print job ----------------------
[RawWindowsPrinter]   Target printer : XP-80
[RawWindowsPrinter]   Byte count     : 824
[RawWindowsPrinter]   Handle         : 456742912
[RawWindowsPrinter]   Spool job ID   : 7
[RawWindowsPrinter]   Bytes written  : 824 / 824
[RawWindowsPrinter] OK RAW print job submitted in 18 ms
[UsbThermalPrinterAdapter] OK 824 bytes sent to "XP-80" in 18 ms
[PrintManager] OK Print job completed in 22 ms
```

---

## 8. Safety Notes

### win32 Package Location
`win32` and `ffi` must be in **`dependencies`** (not `dev_dependencies`).
They are runtime requirements for `RawWindowsPrinter`.

### Never Mix APIs
`RawWindowsPrinter` must remain the ONLY place in the codebase that calls
`OpenPrinter`, `WritePrinter`, etc.  Do NOT call win32 printer APIs from
adapters or services directly.

### Handle Cleanup
If `OpenPrinter` succeeds but a subsequent call fails, `ClosePrinter` MUST
be called before returning.  The current implementation closes the printer
in every error branch before returning the failure result.

### Unicode Printer Names
`TEXT()` converts a Dart String to a native UTF-16 pointer.  It allocates
heap memory that MUST be freed with `calloc.free()`.  Every `TEXT()` call
in `RawWindowsPrinter` is paired with a `calloc.free()` in the finally block.

### Platform Guard
`UsbThermalPrinterAdapter` and `RawWindowsPrinter` are Windows-only.
The build system enforces this since `win32` only compiles on Windows.
Do not instantiate these on other platforms.

---

## 9. Future Extension Points

### Phase 2 — LAN Thermal  `TODO(thermal-lan)`
```dart
// LanThermalPrinterAdapter.sendBytes:
final socket = await Socket.connect(ip, port, timeout: 5.seconds);
socket.add(bytes);
await socket.flush();
await socket.close();
```

### Phase 3 — Bluetooth Thermal  `TODO(thermal-bt)`
Windows: Winsock2 RFCOMM socket via win32 + dart:ffi.
Mobile (future): flutter_bluetooth_serial plugin.

### Phase 4 — Arabic Font Download
For printers without CP1256 support: download raster Arabic font via
`GS ( L` commands, then use downloaded character codes in the ESC/POS stream.

### Phase 5 — Real Printer Discovery
Implement `WindowsUsbPrinterDiscovery` using win32 `EnumPrinters` and
`LanPrinterDiscovery` using concurrent `Socket.connect` probes per subnet IP.

### Phase 6 — Printer Settings UI
Wire `PrinterConfig.printerName` to a UI dropdown populated by
`WindowsUsbPrinterDiscovery.discover()`.

---

## 10. What Must NOT Change

| Component                       | Reason                                     |
|---------------------------------|--------------------------------------------|
| InvoicePdfBuilderClean          | Sole PDF layout source — do not duplicate  |
| PdfPrinterAdapter               | PDF flow is stable and production-ready    |
| InvoiceData model               | Shared by all adapters and ReceiptService  |
| PrinterSettingsKeys constants   | Already persisted in app_settings DB        |
| RawWindowsPrinter               | Only place win32 printer APIs are called   |
| Settings UI screens             | Separate concern from printing engine      |

---

*End of document.*
