// Flutter 쪽에서 서버 API나 로컬 프로세스 같은 외부 기능을 호출하는 파일입니다.
// HTTP 주소 생성, 요청 전송, 응답 JSON 변환 흐름이 포함되어 있습니다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class EmbeddedBackendService extends ChangeNotifier {
  EmbeddedBackendService._();

  static final EmbeddedBackendService instance = EmbeddedBackendService._();

  static const String localBaseUrl = 'http://127.0.0.1:8100';
  static const Duration _healthTimeout = Duration(seconds: 20);
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Process? _backendProcess;
  IOSink? _logSink;
  Timer? _shutdownTimer;
  bool _isStarting = false;
  bool _isRunning = false;
  bool _isPreparingEngine = false;
  String _lastErrorMessage = '';
  String _logFilePath = '';
  String _engineProgressMessage = '';

  bool get isStarting => _isStarting;
  bool get isRunning => _isRunning;
  bool get isPreparingEngine => _isPreparingEngine;
  String get lastErrorMessage => _lastErrorMessage;
  String get logFilePath => _logFilePath;
  String get engineProgressMessage => _engineProgressMessage;

  Future<void> ensureStarted() async {
    // 이미 종료 예약이 있으면 취소하고, 현재 백엔드 상태를 기준으로 시작/재사용 여부를 결정한다.
    _shutdownTimer?.cancel();
    _shutdownTimer = null;

    final projectRoot = _findClientProjectRoot();
    if (projectRoot == null) {
      _setError('Client project root could not be resolved.');
      return;
    }

    _logFilePath = _join(projectRoot.path, 'embedded_backend_runtime.log');
    if (await _isHealthy()) {
      // 이미 백엔드가 살아 있으면 새로 띄우지 않고 기존 프로세스를 재사용한다.
      await _syncRemoteServerUrlFromSettings(projectRoot);
      _isRunning = true;
      _lastErrorMessage = '';
      notifyListeners();
      return;
    }

    if (_isStarting) {
      // 시작 중인 상태라면 다른 호출이 기다리며 건강 상태가 될 때까지 대기한다.
      final ok = await _waitForHealth();
      if (!ok) {
        _setError('Embedded backend did not become healthy.');
      }
      return;
    }

    _isStarting = true;
    // 새로 시작할 때는 이전 프로세스와 충돌하지 않도록 상태를 먼저 갱신한다.
    _isRunning = false;
    _lastErrorMessage = '';
    notifyListeners();

    try {
      // 이전에 기록한 PID가 있으면 종료된 프로세스가 남아 있지 않은지 먼저 정리한다.
      await _terminateTrackedProcessIfNeeded(projectRoot);

      final backendDir = Directory(_join(projectRoot.path, 'embedded_backend'));
      final backendEntry = File(_join(backendDir.path, 'main.py'));
      final yoloConfigDir = _join(backendDir.path, 'data', 'ultralytics');
      Directory(yoloConfigDir).createSync(recursive: true);
      if (!backendEntry.existsSync()) {
        _setError('Embedded backend entry file was not found.');
        return;
      }

      final pythonExecutable = _findPythonExecutable(projectRoot);
      // 가상환경 안의 Python 실행 파일을 찾아야 백엔드 프로세스를 올릴 수 있다.
      if (pythonExecutable == null) {
        _setError('Python executable for the embedded backend was not found.');
        return;
      }

      final engineReady = await _prepareRuntimeEngineIfNeeded(
        // 모델 엔진이 없으면 미리 생성해 두고, 그 다음에 백엔드 서버를 띄운다.
        projectRoot: projectRoot,
        pythonExecutable: pythonExecutable,
      );
      if (!engineReady) {
        return;
      }

      final remoteServerUrl = _readRemoteServerUrl(projectRoot);
      final logFile = File(_logFilePath);
      logFile.parent.createSync(recursive: true);
      _logSink?.close();
      _logSink = logFile.openWrite(mode: FileMode.writeOnlyAppend);
      _writeLog('=== starting embedded backend ===');
      _writeLog('python=$pythonExecutable');
      _writeLog('backendDir=${backendDir.path}');
      if (remoteServerUrl.isNotEmpty) {
        _writeLog('remoteServer=$remoteServerUrl');
      }

      final process = await Process.start(
        pythonExecutable,
        const [
          '-m',
          'uvicorn',
          'main:app',
          '--host',
          '127.0.0.1',
          '--port',
          '8100',
          '--no-access-log',
        ],
        workingDirectory: backendDir.path,
        runInShell: false,
        environment: {
          ...Platform.environment,
          if (remoteServerUrl.isNotEmpty)
            'SAFETY_MONITOR_SERVER_URL': remoteServerUrl,
          'YOLO_CONFIG_DIR': yoloConfigDir,
        },
      );
      _backendProcess = process;
      await _writePidFile(projectRoot, process.pid);
      _attachLogging(process);

      final ok = await _waitForHealth();
      if (!ok) {
        _setError(
          'Embedded backend failed to start. Check $logFilePath for details.',
        );
        await shutdown();
        return;
      }

      _isRunning = true;
      _lastErrorMessage = '';
      await _syncRemoteServerUrlFromSettings(projectRoot);
      notifyListeners();
    } catch (error) {
      _setError('Embedded backend startup failed: $error');
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  Future<bool> _prepareRuntimeEngineIfNeeded({
    // 엔진 파일이 없을 때만 생성 스크립트를 실행해 초기화 비용을 줄인다.
    required Directory projectRoot,
    required String pythonExecutable,
  }) async {
    final backendDir = Directory(_join(projectRoot.path, 'embedded_backend'));
    final enginePath = File(
      _join(
        backendDir.path,
        'app',
        'analysis',
        'models',
        'weights',
        'best.engine',
      ),
    );
    if (enginePath.existsSync()) {
      return true;
    }

    final prepareScript = File(
      // 엔진 생성은 별도 Python 스크립트로 처리한다.
      _join(backendDir.path, 'ensure_runtime_engine.py'),
    );
    if (!prepareScript.existsSync()) {
      _setError('TensorRT engine preparation script was not found.');
      return false;
    }

    _isPreparingEngine = true;
    // 엔진 생성 중에는 UI에 진행 상태를 표시하고, 다른 시작 요청이 중복으로 들어오지 않게 한다.
    _engineProgressMessage = 'TensorRT engine 생성 중입니다. 첫 실행에서는 시간이 걸릴 수 있습니다.';
    notifyListeners();

    try {
      final process = await Process.start(
        pythonExecutable,
        [prepareScript.path],
        workingDirectory: backendDir.path,
        runInShell: false,
        environment: {
          ...Platform.environment,
          'YOLO_CONFIG_DIR': _join(backendDir.path, 'data', 'ultralytics'),
        },
      );
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().isEmpty) {
              return;
            }
            _engineProgressMessage = line.trim();
            _writeLog('ENGINE $line');
            notifyListeners();
          });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().isEmpty) {
              return;
            }
            _engineProgressMessage = line.trim();
            _writeLog('ENGINE ERR $line');
            notifyListeners();
          });

      final exitCode = await process.exitCode;
      if (exitCode != 0 || !enginePath.existsSync()) {
        _setError('TensorRT engine 생성에 실패했습니다. 로그를 확인해 주세요.');
        return false;
      }
      return true;
    } catch (error) {
      _setError('TensorRT engine 생성 중 오류가 발생했습니다: $error');
      return false;
    } finally {
      _isPreparingEngine = false;
      _engineProgressMessage = '';
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    // 백엔드 프로세스를 종료하고, PID 파일과 상태 플래그를 정리한다.
    _shutdownTimer?.cancel();
    _shutdownTimer = null;

    final process = _backendProcess;
    _backendProcess = null;
    _isRunning = false;
    _isPreparingEngine = false;
    notifyListeners();

    if (process != null) {
      // SIGTERM을 먼저 보내고, 실패하면 강제 종료를 시도해 프로세스가 남지 않게 한다.
      try {
        process.kill(ProcessSignal.sigterm);
      } catch (_) {
        try {
          process.kill();
        } catch (_) {
          // Ignore shutdown failures on app exit.
        }
      }
    }

    try {
      final projectRoot = _findClientProjectRoot();
      if (projectRoot != null) {
        final pidFile = File(_join(projectRoot.path, 'embedded_backend.pid'));
        if (pidFile.existsSync()) {
          pidFile.deleteSync();
        }
      }
    } catch (_) {
      // Ignore pid cleanup failures.
    }
  }

  void scheduleShutdown({Duration delay = const Duration(seconds: 5)}) {
    // 앱 종료나 재시작 전 잠깐 후에 백엔드를 자동으로 정리하기 위한 예약 메서드다.
    _shutdownTimer?.cancel();
    _shutdownTimer = Timer(delay, () {
      _shutdownTimer = null;
      unawaited(shutdown());
    });
  }

  Future<bool> _waitForHealth() async {
    // 서버가 완전히 올라올 때까지 짧은 간격으로 헬스 체크를 반복한다.
    final deadline = DateTime.now().add(_healthTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy()) {
        return true;
      }
      await Future<void>.delayed(_pollInterval);
    }
    return false;
  }

  Future<bool> _isHealthy() async {
    // 로컬 헬스 엔드포인트에 HTTP 요청을 보내 백엔드가 살아 있는지 확인한다.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$localBaseUrl/health'));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _syncRemoteServerUrlFromSettings(Directory projectRoot) async {
    // 백엔드가 실행된 뒤 원격 서버 주소를 설정 파일 기준으로 API에 전달해 동기화한다.
    final remoteServerUrl = _readRemoteServerUrl(projectRoot);
    if (remoteServerUrl.isEmpty) {
      return;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client
          .putUrl(Uri.parse('$localBaseUrl/api/admin/remote-server'))
          .timeout(const Duration(seconds: 2));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'remote_server_base_url': remoteServerUrl}));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _writeLog('synced remoteServer=$remoteServerUrl');
      } else {
        _writeLog(
          'remote server sync returned HTTP ${response.statusCode}: $remoteServerUrl',
        );
      }
    } catch (error) {
      _writeLog('remote server sync failed: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _terminateTrackedProcessIfNeeded(Directory projectRoot) async {
    // 이전 실행이 남아 있으면 PID 파일을 기준으로 정리해 중복 프로세스를 방지한다.
    final pidFile = File(_join(projectRoot.path, 'embedded_backend.pid'));
    if (!pidFile.existsSync()) {
      return;
    }

    final rawPid = pidFile.readAsStringSync().trim();
    final pid = int.tryParse(rawPid);
    if (pid == null) {
      pidFile.deleteSync();
      return;
    }

    if (await _isHealthy()) {
      return;
    }

    try {
      Process.killPid(pid, ProcessSignal.sigterm);
    } catch (_) {
      try {
        Process.killPid(pid);
      } catch (_) {
        // Ignore failures when the old process is already gone.
      }
    }
    pidFile.deleteSync();
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _writePidFile(Directory projectRoot, int pid) async {
    // 다음 실행 시 재사용하기 위해 현재 백엔드 프로세스 PID를 파일로 기록한다.
    final pidFile = File(_join(projectRoot.path, 'embedded_backend.pid'));
    await pidFile.writeAsString('$pid', flush: true);
  }

  void _attachLogging(Process process) {
    // 백엔드 stdout/stderr를 로컬 로그 파일에 연결해 문제 발생 시 원인을 추적할 수 있게 한다.
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _writeLog(line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _writeLog('ERR $line'));
    unawaited(
      process.exitCode.then((exitCode) {
        _writeLog('embedded backend exited with code $exitCode');
        if (_backendProcess == process) {
          _backendProcess = null;
          _isRunning = false;
          notifyListeners();
        }
      }),
    );
  }

  void _writeLog(String line) {
    // 로그 파일이 열려 있으면 타임스탬프와 함께 한 줄씩 기록한다.
    final sink = _logSink;
    if (sink == null) {
      return;
    }
    sink.writeln('${DateTime.now().toIso8601String()} $line');
  }

  void _setError(String message) {
    // 실패한 작업에 대한 메시지를 저장하고 상태를 비정상으로 표시한다.
    _lastErrorMessage = message;
    _isRunning = false;
    notifyListeners();
  }

  Directory? _findClientProjectRoot() {
    // 현재 작업 디렉터리나 실행 파일 위치를 기준으로 클라이언트 루트를 상위로 탐색한다.
    final roots = <Directory>{
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    };
    for (final root in roots) {
      Directory? current = root.absolute;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        final backendEntry = File(
          _join(current.path, 'embedded_backend', 'main.py'),
        );
        if (backendEntry.existsSync()) {
          return current;
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return null;
  }

  String? _findPythonExecutable(Directory projectRoot) {
    // 백엔드 실행에 사용할 Python 실행 파일을 가상환경 후보 경로에서 찾는다.
    final workspaceRoot = projectRoot.parent;
    final candidates = <String>[
      _join(workspaceRoot.path, '.venv', 'Scripts', 'python.exe'),
      _join(workspaceRoot.path, '.venv', 'Scripts', 'pythonw.exe'),
      _join(workspaceRoot.path, '.venv', 'Scripts', 'py.exe'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  String _readRemoteServerUrl(Directory projectRoot) {
    // client_settings.json에 저장된 원격 서버 주소를 읽어 백엔드 환경 변수로 전달한다.
    final settingsFile = File(_join(projectRoot.path, 'client_settings.json'));
    if (!settingsFile.existsSync()) {
      return '';
    }
    try {
      final decoded = jsonDecode(settingsFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return '';
      }
      final value = decoded['remote_server_base_url']?.toString().trim() ?? '';
      return value;
    } catch (_) {
      return '';
    }
  }

  String _join(
    // 플랫폼별 경로 구분자를 사용해 파일 경로를 안전하게 조합한다.
    String first,
    String second, [
    String? third,
    String? fourth,
    String? fifth,
    String? sixth,
  ]) {
    final parts = <String>[first, second, ?third, ?fourth, ?fifth, ?sixth];
    return parts.join(Platform.pathSeparator);
  }
}
