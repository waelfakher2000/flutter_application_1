// Web implementation for CSV download.
// Uses a Blob + anchor element to trigger browser download.
// Only compiled on web via conditional import.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> triggerCsvDownload(String fileName, String csvContent) async {
  final blob = html.Blob([csvContent], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body!.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}
