export 'web_download_stub.dart'
    if (dart.library.html) 'web_download_html.dart';
lib/utils/web_download_stub.dart
void descargarArchivoWeb({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError(
    'La descarga web no está disponible en esta plataforma.',
  );
}
lib/utils/web_download_html.dart
import 'dart:html' as html;

void descargarArchivoWeb({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) {
  final blob = html.Blob(
    [bytes],
    mimeType,
  );

  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();

  html.Url.revokeObjectUrl(url);
}
