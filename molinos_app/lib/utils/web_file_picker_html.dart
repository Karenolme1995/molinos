import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class FotoWebSeleccionada {
  final Uint8List bytes;
  final String filename;

  const FotoWebSeleccionada({
    required this.bytes,
    required this.filename,
  });
}

Future<FotoWebSeleccionada?> seleccionarImagenWeb() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';

  input.click();
  await input.onChange.first;

  final archivos = input.files;
  if (archivos == null || archivos.isEmpty) {
    return null;
  }

  final archivo = archivos.first;
  final reader = html.FileReader();
  final completer = Completer<FotoWebSeleccionada?>();

  reader.onLoad.listen((_) {
    final resultado = reader.result;

    if (resultado is Uint8List) {
      completer.complete(
        FotoWebSeleccionada(
          bytes: resultado,
          filename: archivo.name,
        ),
      );
      return;
    }

    if (resultado is List<int>) {
      completer.complete(
        FotoWebSeleccionada(
          bytes: Uint8List.fromList(resultado),
          filename: archivo.name,
        ),
      );
      return;
    }

    completer.complete(null);
  });

  reader.onError.listen((_) {
    completer.completeError(
      StateError('No se pudo leer la imagen seleccionada.'),
    );
  });

  reader.readAsArrayBuffer(archivo);

  return completer.future;
}
