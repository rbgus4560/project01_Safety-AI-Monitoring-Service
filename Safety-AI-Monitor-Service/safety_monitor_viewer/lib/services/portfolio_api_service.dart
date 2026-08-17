import 'dart:convert';
import 'package:http/http.dart' as http;
import '../session/auth_session.dart';

class PortfolioApiService {
  PortfolioApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  String get baseUrl => AuthSession.instance.serverBaseUrl.replaceAll(RegExp(r'/$'), '');
  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (AuthSession.instance.token.isNotEmpty)
      'Authorization': 'Bearer ${AuthSession.instance.token}',
  };

  void dispose() => _client.close();

  Future<Map<String, dynamic>?> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    try {
      final response = await _client.post(
        Uri.parse('$normalized/api/portfolio/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username.trim(), 'password': password}),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }


  Future<void> logout() async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/api/portfolio/auth/logout'),
        headers: authHeaders,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> fetchCameraGroups() async =>
      _fetchItems('/api/portfolio/camera-groups');

  Future<Map<String, dynamic>?> saveCameraGroup({
    int? groupId,
    required String name,
    required List<String> sourceKeys,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/portfolio/camera-groups${groupId == null ? '' : '/$groupId'}',
      );
      final body = jsonEncode({'name': name.trim(), 'source_keys': sourceKeys});
      final response = groupId == null
          ? await _client.post(uri, headers: authHeaders, body: body)
          : await _client.put(uri, headers: authHeaders, body: body);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['item'] is! Map) return null;
      return Map<String, dynamic>.from(decoded['item'] as Map);
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteCameraGroup(int groupId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/api/portfolio/camera-groups/$groupId'),
        headers: authHeaders,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchViewerLayout() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/portfolio/layout'),
        headers: authHeaders,
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['item'] is! Map) return null;
      return Map<String, dynamic>.from(decoded['item'] as Map);
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveViewerLayout({
    required int gridCount,
    int? activeGroupId,
    required List<String> sourceOrder,
  }) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/api/portfolio/layout'),
        headers: authHeaders,
        body: jsonEncode({
          'grid_count': gridCount,
          'active_group_id': activeGroupId,
          'source_order': sourceOrder,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchUsers() async =>
      _fetchItems('/api/portfolio/users');

  Future<List<Map<String, dynamic>>> fetchClients() async =>
      _fetchItems('/api/portfolio/clients');

  Future<String> createRegistrationCode() async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/portfolio/clients/registration-code'),
        headers: authHeaders,
      );
      if (response.statusCode != 200) return '';
      final data = jsonDecode(response.body);
      return data is Map ? data['registration_code']?.toString() ?? '' : '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> createUser({
    required String username,
    required String password,
    required String role,
    required String displayName,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/portfolio/users'),
        headers: authHeaders,
        body: jsonEncode({
          'username': username.trim(),
          'password': password,
          'role': role,
          'display_name': displayName.trim(),
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setUserActive(String username, bool active) async {
    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/api/portfolio/users/${Uri.encodeComponent(username)}/active'),
        headers: authHeaders,
        body: jsonEncode({'is_active': active}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setClientActive(String clientId, bool active) async {
    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/api/portfolio/clients/${Uri.encodeComponent(clientId)}/active'),
        headers: authHeaders,
        body: jsonEncode({'is_active': active}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acknowledgeEvent(String eventKey, String sourceKey) async {
    try {
      final uri = Uri.parse('$baseUrl/api/portfolio/events/${Uri.encodeComponent(eventKey)}/ack')
          .replace(queryParameters: {'source_key': sourceKey});
      final response = await _client.post(uri, headers: authHeaders);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchItems(String path) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl$path'), headers: authHeaders);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body);
      if (data is! Map || data['items'] is! List) return const [];
      return (data['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
