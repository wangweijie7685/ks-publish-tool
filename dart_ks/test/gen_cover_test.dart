// gen_cover_test.dart — 命令行封面生成器（flutter test 当 CLI 用）
// ================================================================
// 用法（dart_ks 目录里）：
//   flutter test test/gen_cover_test.dart
// 环境变量：
//   KS_TEXT   主标题（\n 换行）      默认「限时秒杀\n最后3天」
//   KS_SUB    副标题                默认空
//   KS_THEME  deep_yellow_red / dark_yellow_scarlet / olive_darkred
//   KS_W KS_H  尺寸                 默认 1080x1440（3:4）
//   KS_OUT    输出路径              默认 cover_out.png
//   KS_FONT_TTF 可选：本地中文 .ttf（flutter_tester 在桌面上没有中文字体，
//               不指定会画成豆腐块；真机 iOS/Android 走系统字体没问题）
// 示例：
//   KS_TEXT="吉他课 99元4节" KS_SUB="六弦琴行 · 周六开课" KS_OUT=cover.png flutter test test/gen_cover_test.dart

// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ks_dart/ks_cover_painter.dart';

void main() {
  test('generate kuaishou theme cover', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final env = Platform.environment;

    // 可选：加载本地中文字体，让测试环境也画出真实字形
    String? family;
    final ttf = env['KS_FONT_TTF'] ?? _defaultFont();
    if (ttf != null && _loadable(ttf)) {
      final bytes = File(ttf).readAsBytesSync();
      family = 'KsCoverTestFont';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      print('已加载字体：$ttf');
    } else {
      print('⚠️ 未加载中文字体，测试环境可能显示豆腐块（真机走系统字体，不受影响）');
    }

    final out = await KsCover.save(
      env['KS_OUT'] ?? 'cover_out.png',
      text: env['KS_TEXT'] ?? '限时秒杀\\n最后3天',
      sub: env['KS_SUB'] ?? '',
      theme: KsCoverTheme.byName(env['KS_THEME'] ?? 'deep_yellow_red'),
      width: int.parse(env['KS_W'] ?? '1080'),
      height: int.parse(env['KS_H'] ?? '1440'),
      fontFamily: family,
    );
    print('封面已生成：${File(out).absolute.path}');
    expect(File(out).lengthSync(), greaterThan(1024));
  });
}

/// 桌面测试常见中文字体（单字体 .ttf；.ttc 字体集合 Flutter 的 FontLoader 加载不了）
String? _defaultFont() {
  const cands = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttf',
    '/System/Library/Fonts/PingFang.ttc', // macOS CI 上存在但加载不了，会被 _loadable 过滤
  ];
  for (final c in cands) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

/// FontLoader 只吃单一字体文件，.ttc 集合会抛异常导致 CI 失败，这里直接跳过
bool _loadable(String path) {
  final p = path.toLowerCase();
  return File(path).existsSync() && (p.endsWith('.ttf') || p.endsWith('.otf'));
}
