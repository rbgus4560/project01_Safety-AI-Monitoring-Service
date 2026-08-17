// 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
// 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'models/clip_window_arguments.dart';
import 'screens/clip_player_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit 초기화
  MediaKit.ensureInitialized();

  final commandLineArguments = _tryResolveClipWindowArguments(args);
  if (commandLineArguments != null) {
    runApp(
      SafetyMonitorClientApp(
        title: commandLineArguments.title,
        home: ClipPlayerWindow(arguments: commandLineArguments),
      ),
    );
    return;
  }

  final windowController = await WindowController.fromCurrentEngine();
  final clipWindowArguments = ClipWindowArguments.tryParse(
    windowController.arguments,
  );
  if (clipWindowArguments != null) {
    runApp(
      SafetyMonitorClientApp(
        title: clipWindowArguments.title,
        home: ClipPlayerWindow(arguments: clipWindowArguments),
      ),
    );
    return;
  }

  runApp(const SafetyMonitorClientApp());
}

ClipWindowArguments? _tryResolveClipWindowArguments(List<String> args) {
  for (final raw in args) {
    final parsed = ClipWindowArguments.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}
