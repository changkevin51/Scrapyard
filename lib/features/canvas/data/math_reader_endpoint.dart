/// Must match `SIDECAR_REV` in `python/mathreader_app/main.py`.
const mathReaderSidecarRev = '4';

class MathReaderSidecar {
  final String host;
  final int port;

  const MathReaderSidecar({required this.host, required this.port});

  Uri get recognizeUri => Uri.parse('http://$host:$port/recognize');

  Uri get healthUri => Uri.parse('http://$host:$port/health');
}
