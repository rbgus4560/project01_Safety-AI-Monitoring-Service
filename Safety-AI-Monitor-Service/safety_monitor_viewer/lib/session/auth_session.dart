class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  String serverBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  String token = '';
  String username = '';
  String displayName = '';
  String role = '';

  bool get isLoggedIn => token.isNotEmpty;
  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  void signIn({
    required String baseUrl,
    required String accessToken,
    required String user,
    required String name,
    required String userRole,
  }) {
    serverBaseUrl = baseUrl.trim();
    token = accessToken;
    username = user;
    displayName = name;
    role = userRole;
  }

  void clear() {
    token = '';
    username = '';
    displayName = '';
    role = '';
  }
}
