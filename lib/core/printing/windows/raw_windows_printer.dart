// lib/core/printing/windows/raw_windows_printer.dart
//
// Low-level Windows RAW printer helper.
//
// Sends a pre-built ESC/POS byte buffer directly to a Windows printer
// queue using the spooler RAW datatype.  This bypasses GDI completely —
// bytes are delivered verbatim to the printer firmware.
//
// Windows print call sequence:
//   OpenPrinter  --► StartDocPrinter  --► StartPagePrinter
//        --► WritePrinter  --► EndPagePrinter  --► EndDocPrinter
//        --► ClosePrinter
//
// Memory management:
//   Every native allocation (TEXT, calloc) is paired with a free() in a
//   finally block.  Even on error paths, all memory is released before
//   returning to the caller.
//
// This file is the ONLY place in the codebase that calls win32 printer APIs.
// UsbThermalPrinterAdapter delegates entirely to [RawWindowsPrinter.send].

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

// ---------------------------------------------------------------------------
// RawPrintResult — outcome of a single print job
// ---------------------------------------------------------------------------

/// Result returned by [RawWindowsPrinter.send].
class RawPrintResult {
  final bool ok;
  final int bytesRequested;
  final int bytesWritten;
  final int elapsedMs;
  final String? errorMessage;
  final int? win32ErrorCode;

  const RawPrintResult._({
    required this.ok,
    this.bytesRequested = 0,
    this.bytesWritten = 0,
    this.elapsedMs = 0,
    this.errorMessage,
    this.win32ErrorCode,
  });

  factory RawPrintResult.success({
    required int bytesRequested,
    required int bytesWritten,
    required int elapsedMs,
  }) =>
      RawPrintResult._(
        ok: true,
        bytesRequested: bytesRequested,
        bytesWritten: bytesWritten,
        elapsedMs: elapsedMs,
      );

  factory RawPrintResult.failure(String message, {int? win32Code}) =>
      RawPrintResult._(
        ok: false,
        errorMessage: message,
        win32ErrorCode: win32Code,
      );

  @override
  String toString() => ok
      ? 'RawPrintResult.ok(written=$bytesWritten/$bytesRequested, ${elapsedMs}ms)'
      : 'RawPrintResult.error("$errorMessage", win32=$win32ErrorCode)';
}

// ---------------------------------------------------------------------------
// RawWindowsPrinter
// ---------------------------------------------------------------------------

/// Sends raw ESC/POS bytes to a Windows printer via the spooler RAW channel.
///
/// All methods are static; no instance state is needed.
/// Windows-only — do not call on other platforms without a platform guard.
///
/// Usage:
/// ```dart
/// final result = await RawWindowsPrinter.send(
///   bytes: escPosBytes,
///   printerName: 'XP-80',   // null or '' → OS default printer
///   docName: 'Lez POS Invoice',
/// );
/// if (!result.ok) throw Exception(result.errorMessage);
/// ```
class RawWindowsPrinter {
  RawWindowsPrinter._(); // static-only class

  // -- Public API ------------------------------------------------------------

  /// Sends [bytes] to the named Windows printer using RAW datatype.
  ///
  /// Parameters:
  ///   [printerName] — Windows printer name (e.g. 'XP-80' or 'Generic / Text Only').
  ///                   Pass null or empty string to target the OS default printer.
  ///   [docName]     — Job title shown in the Windows print queue. Default: 'Lez POS'.
  ///
  /// Returns [RawPrintResult.success] on success, [RawPrintResult.failure]
  /// on any error.  Never throws; callers check [RawPrintResult.ok].
  static Future<RawPrintResult> send({
    required Uint8List bytes,
    required String? printerName,
    String docName = 'Lez POS',
  }) async {
    // -- Pre-flight validation ---------------------------------------------
    if (bytes.isEmpty) {
      const msg = '[RawWindowsPrinter] ✗ Empty byte buffer — nothing to print.';
      debugPrint(msg);
      return RawPrintResult.failure('Empty byte buffer — nothing to print.');
    }

    final effectiveName = (printerName ?? '').trim();
    final displayName = effectiveName.isEmpty ? '(OS default)' : effectiveName;

    debugPrint('[RawWindowsPrinter] -- RAW print job -------------------------');
    debugPrint('[RawWindowsPrinter]   Target printer : $displayName');
    debugPrint('[RawWindowsPrinter]   Byte count     : ${bytes.length}');
    debugPrint('[RawWindowsPrinter]   Doc name       : $docName');

    final sw = Stopwatch()..start();

    // -- Native allocations ------------------------------------------------
    // All pointers declared here so the outer finally can free them all.
    final phPrinter   = calloc<IntPtr>();
    final pName       = TEXT(effectiveName);       // printer name (UTF-16)
    final pDocName    = TEXT(docName);             // document name (UTF-16)
    final pDatatype   = TEXT('RAW');               // datatype = 'RAW' (UTF-16)
    final docInfo     = calloc<DOC_INFO_1>();
    final pData       = calloc<Uint8>(bytes.length);
    final pWritten    = calloc<Uint32>();

    try {
      // -- Step 1: OpenPrinter ---------------------------------------------
      final openOk = OpenPrinter(pName, phPrinter, nullptr);
      if (openOk == FALSE) {
        final err = GetLastError();
        debugPrint('[RawWindowsPrinter] ✗ OpenPrinter failed. '
            'Win32 error: $err (0x${err.toRadixString(16).toUpperCase()})');
        return RawPrintResult.failure(
          'OpenPrinter failed for "$displayName". '
          'The printer may be offline, not installed, or the name is wrong.',
          win32Code: err,
        );
      }

      final hPrinter = phPrinter.value;
      debugPrint('[RawWindowsPrinter]   Handle         : $hPrinter');

      // -- Step 2: Configure DOC_INFO_1 ------------------------------------
      docInfo.ref.pDocName    = pDocName;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype   = pDatatype;

      // -- Step 3: StartDocPrinter -----------------------------------------
      final jobId = StartDocPrinter(hPrinter, 1, docInfo.cast());
      if (jobId == 0) {
        final err = GetLastError();
        debugPrint('[RawWindowsPrinter] ✗ StartDocPrinter failed. Error: $err');
        ClosePrinter(hPrinter);
        return RawPrintResult.failure(
          'StartDocPrinter failed. Win32 error: $err',
          win32Code: err,
        );
      }
      debugPrint('[RawWindowsPrinter]   Spool job ID   : $jobId');

      // -- Step 4: StartPagePrinter ----------------------------------------
      final pageOk = StartPagePrinter(hPrinter);
      if (pageOk == FALSE) {
        final err = GetLastError();
        debugPrint('[RawWindowsPrinter] ✗ StartPagePrinter failed. Error: $err');
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return RawPrintResult.failure(
          'StartPagePrinter failed. Win32 error: $err',
          win32Code: err,
        );
      }

      // -- Step 5: Copy bytes to unmanaged buffer --------------------------
      final nativeBytes = pData.asTypedList(bytes.length);
      nativeBytes.setAll(0, bytes);

      // -- Step 6: WritePrinter --------------------------------------------
      final writeOk = WritePrinter(
        hPrinter,
        pData.cast(),       // Pointer<NativeType> (void*)
        bytes.length,
        pWritten,
      );

      final written = pWritten.value;
      debugPrint('[RawWindowsPrinter]   Bytes written  : $written / ${bytes.length}');

      if (writeOk == FALSE) {
        final err = GetLastError();
        debugPrint('[RawWindowsPrinter] ✗ WritePrinter failed. Error: $err');
        EndPagePrinter(hPrinter);
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return RawPrintResult.failure(
          'WritePrinter failed after writing $written/${bytes.length} bytes. '
          'Win32 error: $err',
          win32Code: err,
        );
      }

      if (written != bytes.length) {
        debugPrint('[RawWindowsPrinter] ⚠ Partial write — '
            '$written of ${bytes.length} bytes accepted by spooler. '
            'Job may still complete if the spooler buffers internally.');
      }

      // -- Step 7: End page + doc + close ----------------------------------
      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);

      sw.stop();
      debugPrint('[RawWindowsPrinter] ✓ RAW print job submitted in '
          '${sw.elapsedMilliseconds} ms. '
          'Job ID: $jobId, bytes: $written/${bytes.length}');

      return RawPrintResult.success(
        bytesRequested: bytes.length,
        bytesWritten: written,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e, s) {
      sw.stop();
      debugPrint('[RawWindowsPrinter] ✗ Unexpected exception after '
          '${sw.elapsedMilliseconds} ms: $e');
      debugPrint('$s');
      return RawPrintResult.failure(
        'Unexpected exception during RAW print: $e',
      );
    } finally {
      // Free ALL native memory regardless of outcome.
      calloc.free(pData);
      calloc.free(pWritten);
      calloc.free(docInfo);
      calloc.free(pDatatype);
      calloc.free(pDocName);
      calloc.free(pName);
      calloc.free(phPrinter);
    }
  }

  // -- Availability check ----------------------------------------------------

  /// Returns true if the named Windows printer can be opened.
  ///
  /// Opens and immediately closes the printer — no bytes are sent.
  /// Use this to validate [PrinterConfig.printerName] before printing.
  static Future<bool> checkAvailable(String? printerName) async {
    final effectiveName = (printerName ?? '').trim();
    final displayName = effectiveName.isEmpty ? '(OS default)' : effectiveName;

    final phPrinter = calloc<IntPtr>();
    final pName     = TEXT(effectiveName);

    try {
      final result = OpenPrinter(pName, phPrinter, nullptr);
      if (result != FALSE) {
        ClosePrinter(phPrinter.value);
        debugPrint('[RawWindowsPrinter] ✓ Printer "$displayName" is reachable.');
        return true;
      } else {
        final err = GetLastError();
        debugPrint('[RawWindowsPrinter] ✗ Printer "$displayName" not available. '
            'Win32 error: $err '
            '(0x${err.toRadixString(16).toUpperCase()})');
        return false;
      }
    } catch (e) {
      debugPrint('[RawWindowsPrinter] ✗ checkAvailable exception: $e');
      return false;
    } finally {
      calloc.free(pName);
      calloc.free(phPrinter);
    }
  }
}
