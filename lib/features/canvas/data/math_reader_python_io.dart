import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:serious_python/serious_python.dart';

import 'math_reader_endpoint.dart';

const _defaultPort = 17831;
const _readyFileName = 'mathreader_ready.json';

Future<MathReaderSidecar?>? _inFlight;

void _log(String msg) {
  if (kDebugMode) debugPrint('MathReader: $msg');
}

Future<MathReaderSidecar?> ensureMathReaderSidecar() {
  return _inFlight ??= _ensureMathReaderSidecar().then((sidecar) {
    if (sidecar == null) _inFlight = null;
    return sidecar;
  });
}

Future<MathReaderSidecar?> _ensureMathReaderSidecar() async {
  final tmp = await getTemporaryDirectory();
  final ready = File('${tmp.path}/$_readyFileName');
  final logFile = File(p.join(tmp.path, 'mathreader.log'));

  var host = 'localhost';
  var port = _defaultPort;

  Future<bool> readReady() async {
    try {
      if (!await ready.exists()) return false;
      final data = jsonDecode(await ready.readAsString());
      if (data is! Map) return false;
      final h = data['host'];
      final p0 = data['port'];
      if (h is String && h.isNotEmpty) {
        host = (h == '127.0.0.1' || h == '::1') ? 'localhost' : h;
      }
      if (p0 is int) {
        port = p0;
        return true;
      }
      if (p0 is num) {
        port = p0.toInt();
        return true;
      }
    } catch (e) {
      _log('ready file unreadable: $e');
    }
    return false;
  }

  Future<String?> probe() async {
    try {
      final sock = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 400),
      );
      await sock.close();
    } catch (e) {
      return 'tcp $e';
    }
    try {
      final resp = await http
          .get(Uri.parse('http://$host:$port/health'))
          .timeout(const Duration(milliseconds: 800));
      if (resp.statusCode != 200) {
        return 'http ${resp.statusCode} ${resp.body}';
      }
      _logSidecarHealth(resp.body);
      return null;
    } catch (e) {
      return 'http $e';
    }
  }

  await readReady();
  if (await probe() == null) {
    _log('already up at $host:$port');
    return MathReaderSidecar(host: host, port: port);
  }

  final env = {
    'MATHREADER_HOST': '127.0.0.1',
    'MATHREADER_PORT': '$_defaultPort',
    'MATHREADER_READY_PATH': ready.path,
    'MATHREADER_LOG_PATH': logFile.path,
  };

  try {
    _log('unpacking Python app…');
    final appDir = await SeriousPython.prepareApp();
    await _overlaySidecarSources(appDir);
    final mainPy = File(p.join(appDir, 'main.py'));
    _log('app dir=$appDir main.py=${mainPy.existsSync()}');
    final result = await SeriousPython.run(
      appFileName: 'main.py',
      environmentVariables: env,
      sync: false,
    );
    _log('SeriousPython.run returned: $result');
  } catch (e, st) {
    _log('SeriousPython.run failed: $e\n$st');
    if (!Platform.isAndroid && !Platform.isIOS) {
      await _spawnLocalPython(env);
    }
  }

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  var lastProbe = 'not checked';
  while (DateTime.now().isBefore(deadline)) {
    await readReady();
    lastProbe = await probe() ?? '';
    if (lastProbe.isEmpty) {
      _log('healthy at $host:$port');
      return MathReaderSidecar(host: host, port: port);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  _log('sidecar did not become healthy ($lastProbe)');
  try {
    if (await logFile.exists()) {
      _log('python log:\n${await logFile.readAsString()}');
    } else {
      _log('no python log at ${logFile.path}');
    }
  } catch (e) {
    _log('could not read python log: $e');
  }
  return null;
}

void _logSidecarHealth(String body) {
  try {
    final data = jsonDecode(body);
    if (data is! Map) return;
    final rev = data['sidecar'];
    if (rev != mathReaderSidecarRev) {
      _log(
        'STALE Python sidecar=$rev expected=$mathReaderSidecarRev '
        '— fully quit the app (press q) so grammar failures can return latex',
      );
    } else {
      _log('sidecar rev=$rev');
    }
  } catch (_) {}
}

/// Serious Python unpacks app.zip once. Overlay the Flutter-bundled handler
/// so `main.py` edits ship with `flutter run` without re-pip.
Future<void> _overlaySidecarSources(String appDir) async {
  try {
    final src = await rootBundle.loadString('python/mathreader_app/main.py');
    final dest = File(p.join(appDir, 'main.py'));
    await dest.writeAsString(src);
    _log('overlaid main.py (${src.length} chars) sidecar=$mathReaderSidecarRev');
  } catch (e) {
    _log('could not overlay main.py: $e');
  }
}

Future<void> _spawnLocalPython(Map<String, String> environment) async {
  final script = _findMainPy();
  if (script == null) {
    _log('main.py not found for local Python fallback');
    return;
  }
  final python = _pythonExecutable();
  try {
    await Process.start(
      python,
      [script],
      environment: {
        ...Platform.environment,
        ...environment,
      },
      workingDirectory: File(script).parent.path,
      mode: ProcessStartMode.detached,
    );
    _log('started local sidecar: $python $script');
  } catch (e) {
    _log('local Python failed: $e');
  }
}

String _pythonExecutable() {
  final override = Platform.environment['MATHREADER_PYTHON'];
  if (override != null && override.isNotEmpty) return override;
  return Platform.isWindows ? 'python' : 'python3';
}

String? _findMainPy() {
  final names = [
    p.join(Directory.current.path, 'python', 'mathreader_app', 'main.py'),
    p.join(Directory.current.path, 'mathreader_app', 'main.py'),
  ];
  for (final path in names) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
