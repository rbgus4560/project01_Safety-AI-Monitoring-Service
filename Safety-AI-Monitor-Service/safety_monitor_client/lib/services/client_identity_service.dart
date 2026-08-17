import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;


String _hostToken() {
  final raw = Platform.localHostname.trim().toLowerCase();
  final safe = raw.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_').replaceAll(RegExp(r'_+'), '_');
  return safe.isEmpty ? 'windows_client' : safe;
}

class ClientIdentity {
  const ClientIdentity({required this.clientId, required this.clientName, required this.serverBaseUrl, required this.authToken});
  final String clientId;
  final String clientName;
  final String serverBaseUrl;
  final String authToken;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'client_name': clientName,
    'server_base_url': serverBaseUrl,
    'auth_token': authToken,
  };
  factory ClientIdentity.fromJson(Map<String, dynamic> json) => ClientIdentity(
    clientId: json['client_id']?.toString() ?? '',
    clientName: json['client_name']?.toString() ?? '',
    serverBaseUrl: json['server_base_url']?.toString() ?? '',
    authToken: json['auth_token']?.toString() ?? '',
  );
}

class ClientIdentityService {
  static ClientIdentity? current;

  Directory? findProjectRoot() {
    final starts = <Directory>[Directory.current, File(Platform.resolvedExecutable).parent];
    for (final start in starts) {
      Directory? currentDir = start;
      for (var i = 0; i < 8 && currentDir != null; i++) {
        if (File('${currentDir.path}${Platform.pathSeparator}embedded_backend${Platform.pathSeparator}main.py').existsSync()) return currentDir;
        final parent = currentDir.parent;
        currentDir = parent.path == currentDir.path ? null : parent;
      }
    }
    return null;
  }

  File? get _identityFile {
    final root = findProjectRoot();
    return root == null ? null : File('${root.path}${Platform.pathSeparator}client_identity.json');
  }

  String loadConfiguredServerBaseUrl({String fallback = 'http://127.0.0.1:8000'}) {
    final root = findProjectRoot();
    if (root == null) return fallback;
    final settingsFile = File('${root.path}${Platform.pathSeparator}client_settings.json');
    if (!settingsFile.existsSync()) return fallback;
    try {
      final decoded = jsonDecode(settingsFile.readAsStringSync());
      if (decoded is Map) {
        final value = decoded['remote_server_base_url']?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return fallback;
  }

  ClientIdentity? load() {
    final file = _identityFile;
    if (file == null || !file.existsSync()) return null;
    try {
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map) return null;
      final identity = ClientIdentity.fromJson(Map<String, dynamic>.from(data));
      if (identity.clientId.isEmpty || identity.serverBaseUrl.isEmpty) return null;
      current = identity;
      return identity;
    } catch (_) { return null; }
  }

  Future<ClientIdentity?> register({required String serverBaseUrl, required String clientName, required String registrationCode}) async {
    final normalized = serverBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$normalized/api/portfolio/clients/register'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'client_name': clientName.trim(), 'registration_code': registrationCode.trim()}),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['item'] is! Map) return null;
      final item = Map<String, dynamic>.from(decoded['item'] as Map);
      final identity = ClientIdentity(
        clientId: item['client_id']?.toString() ?? '',
        clientName: item['client_name']?.toString() ?? clientName.trim(),
        serverBaseUrl: normalized,
        authToken: item['auth_token']?.toString() ?? '',
      );
      if (identity.clientId.isEmpty) return null;
      save(identity);
      return identity;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  void save(ClientIdentity identity) {
    final root = findProjectRoot();
    if (root == null) return;
    final identityFile = File('${root.path}${Platform.pathSeparator}client_identity.json');
    identityFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(identity.toJson()));
    final settingsFile = File('${root.path}${Platform.pathSeparator}client_settings.json');
    Map<String, dynamic> settings = {};
    if (settingsFile.existsSync()) {
      try {
        final decoded = jsonDecode(settingsFile.readAsStringSync());
        if (decoded is Map) settings = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    settings['remote_server_base_url'] = identity.serverBaseUrl;
    settings['client_id'] = identity.clientId;
    settings['client_name'] = identity.clientName;
    settings['client_auth_token'] = identity.authToken;
    settings['machine_id'] = 'host_${_hostToken()}';
    settingsFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(settings));
    current = identity;
  }
}
