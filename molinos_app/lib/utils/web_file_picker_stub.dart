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
  throw UnsupportedError(
    'La selección de imágenes solo está disponible en la versión web.',
  );
}
