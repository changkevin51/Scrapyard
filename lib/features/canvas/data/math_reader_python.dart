import 'math_reader_endpoint.dart';
import 'math_reader_python_stub.dart'
    if (dart.library.io) 'math_reader_python_io.dart' as impl;

export 'math_reader_endpoint.dart';

/// Start the embedded MathReader process and wait until HTTP is up.
Future<MathReaderSidecar?> ensureMathReaderSidecar() {
  return impl.ensureMathReaderSidecar();
}
