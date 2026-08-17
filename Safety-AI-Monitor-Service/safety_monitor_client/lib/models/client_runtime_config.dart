// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

class ClientRuntimeConfig {
  const ClientRuntimeConfig({
    required this.remoteServerBaseUrl,
    required this.analysisDevice,
    required this.modelType,
    required this.preferTensorRtEngine,
    required this.modelPath,
    required this.modelExists,
    required this.enginePath,
    required this.engineExists,
    required this.databasePath,
  });

  final String remoteServerBaseUrl;
  final String analysisDevice;
  final String modelType;
  final bool preferTensorRtEngine;
  final String modelPath;
  final bool modelExists;
  final String enginePath;
  final bool engineExists;
  final String databasePath;

  factory ClientRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return ClientRuntimeConfig(
      remoteServerBaseUrl: json['remote_server_base_url']?.toString() ?? '',
      analysisDevice: json['analysis_device']?.toString() ?? '',
      modelType: json['model_type']?.toString() ?? '',
      preferTensorRtEngine: json['prefer_tensorrt_engine'] == true,
      modelPath: json['model_path']?.toString() ?? '',
      modelExists: json['model_exists'] == true,
      enginePath: json['engine_path']?.toString() ?? '',
      engineExists: json['engine_exists'] == true,
      databasePath: json['database_path']?.toString() ?? '',
    );
  }
}
