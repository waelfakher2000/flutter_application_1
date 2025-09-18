// Stub implementation for non-web platforms.
// Conditional import target: import 'csv_download/download_csv_stub.dart'
// Replaced at compile time on web by download_csv_web.dart.

Future<void> triggerCsvDownload(String fileName, String csvContent) async {
  // No-op on non-web; caller will handle native file creation & sharing.
  return;
}
