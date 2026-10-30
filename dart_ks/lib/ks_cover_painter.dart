// ks_cover_painter.dart — 快手主题封面绘制（Flutter / dart:ui，中文原生支持）
// =====================================================================
// 深黄底 + 红字主题，文字可编辑；与 ks_cover_ios.py 的主题保持一致。
// 只用 dart:ui，无第三方依赖；在 Flutter App 内调用，
// 或用 flutter test 当命令行生成器（见 test/gen_cover_test.dart）。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 封面主题色卡（与 ks_cover_ios.py THEMES 一一对应）
class KsCoverTheme {
  final String name;
  final String label;
  final ui.Color bg; // 底色
  final ui.Color fg; // 主标题字色
  final ui.Color stroke; // 描边色
  final ui.Color sub; // 副标题字色

  const KsCoverTheme(this.name, this.label,
      {required this.bg, required this.fg, required this.stroke, required this.sub});

  /// 深黄底 · 中国红字（默认）
  static const deepYellowRed = KsCoverTheme(
    'deep_yellow_red', '深黄底·红字（默认）',
    bg: ui.Color(0xFFB8860B), fg: ui.Color(0xFFE60012),
    stroke: ui.Color(0xFF6B3400), sub: ui.Color(0xFF5A2D00),
  );

  /// 深黄底 · 亮红字（对比更炸）
  static const darkYellowScarlet = KsCoverTheme(
    'dark_yellow_scarlet', '深黄底·亮红字',
    bg: ui.Color(0xFFCC9900), fg: ui.Color(0xFFFF3B30),
    stroke: ui.Color(0xFF4A2E00), sub: ui.Color(0xFF4A2E00),
  );

  /// 土黄底 · 暗红字（沉稳款）
  static const oliveDarkRed = KsCoverTheme(
    'olive_darkred', '土黄底·暗红字',
    bg: ui.Color(0xFFC8961E), fg: ui.Color(0xFF8B0000),
    stroke: ui.Color(0xFF3D2500), sub: ui.Color(0xFF3D2500),
  );

  static const all = [deepYellowRed, darkYellowScarlet, oliveDarkRed];

  static KsCoverTheme byName(String name) =>
      all.firstWhere((t) => t.name == name, orElse: () => deepYellowRed);
}

class KsCover {
  KsCover._();

  /// 生成主题封面 PNG。
  ///
  /// [text] 主标题，`\n` 强制换行；超过 [maxLines] 行自动缩字号。
  /// [sub] 副标题（小字，可空）。宽高默认 1080x1440（3:4），9:16 传 1920。
  /// [fontFamily] 可指定 App 内已加载的字体，默认走系统回退（iOS 会用 PingFang）。
  static Future<Uint8List> render({
    required String text,
    String sub = '',
    KsCoverTheme theme = KsCoverTheme.deepYellowRed,
    int width = 1080,
    int height = 1440,
    double fontScale = 0.15,
    int maxLines = 2,
    String? fontFamily,
  }) async {
    assert(width > 0 && height > 0);
    final w = width.toDouble(), h = height.toDouble();
    final maxW = w * 0.82;
    final baseSize = (_min(w, h) * fontScale).round();

    // 1) 主标题：先排后量，超行自动缩字（每档先做空格断行预处理）
    var norm = _normalize(text);
    var size = baseSize;
    late final ui.Paragraph mainPar;
    while (true) {
      norm = _rebalance(norm, size.toDouble(), maxW, fontFamily);
      final p = _build(norm, size.toDouble(), theme, fontFamily, maxW: maxW);
      final lineCount = p.computeLineMetrics().length;
      final floor = _max((baseSize * 0.45).round(), 14).toInt();
      if (lineCount <= maxLines || size <= floor) {
        mainPar = p;
        break;
      }
      size = _max((size * 0.92).round(), 12).toInt();
    }

    // 2) 副标题
    final subNorm = _normalize(sub);
    final subSize = _max((size * 0.42).round(), 20).toDouble();
    final subPar = subNorm.isEmpty
        ? null
        : _build(subNorm, subSize, theme, fontFamily, maxW: maxW, isSub: true);

    // 3) 主标题描边层（同排版描一遍再叠填充，红字压深黄更立体）
    final strokePar = _build(norm, size.toDouble(), theme, fontFamily,
        maxW: maxW, stroke: true, strokeWidth: _max(2.0, size / 16));

    // 4) 整体垂直居中：主标题块 + 间距 + 副标题块
    final gap = subPar == null ? 0.0 : size * 0.10;
    final totalH = mainPar.height + gap + (subPar?.height ?? 0);
    final top = (h - totalH) / 2;

    // 段落盒子宽度是 maxW，内部 textAlign.center 已把字居中；
    // 只要把盒子摆到居中位置（左右各留 (w-maxW)/2）即可，不要再按 longestLine 偏移
    final left = (w - maxW) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(ui.Offset.zero & ui.Size(w, h), ui.Paint()..color = theme.bg);
    canvas.drawParagraph(strokePar, ui.Offset(left, top));
    canvas.drawParagraph(mainPar, ui.Offset(left, top));
    if (subPar != null) {
      canvas.drawParagraph(
          subPar, ui.Offset(left, top + mainPar.height + gap));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// 生成并保存为 PNG 文件（在 Flutter App 或 flutter test 里用）
  static Future<String> save(
    String path, {
    required String text,
    String sub = '',
    KsCoverTheme theme = KsCoverTheme.deepYellowRed,
    int width = 1080,
    int height = 1440,
    double fontScale = 0.15,
    int maxLines = 2,
    String? fontFamily,
  }) async {
    final png = await render(
        text: text,
        sub: sub,
        theme: theme,
        width: width,
        height: height,
        fontScale: fontScale,
        maxLines: maxLines,
        fontFamily: fontFamily);
    File(path).writeAsBytesSync(png);
    return path;
  }

  // ---------------- 内部 ----------------

  static double _min(num a, num b) => (a < b ? a : b).toDouble();
  static double _max(num a, num b) => (a > b ? a : b).toDouble();

  static String _normalize(String s) => s.replaceAll('\\n', '\n').trim();

  static ui.Paragraph _build(String text, double size, KsCoverTheme theme,
      String? fontFamily,
      {required double maxW, bool stroke = false, double strokeWidth = 0,
      bool isSub = false}) {
    final paint = ui.Paint()
      ..color = stroke
          ? theme.stroke
          : (isSub ? theme.sub : theme.fg)
      ..style = stroke ? ui.PaintingStyle.stroke : ui.PaintingStyle.fill;
    if (stroke) {
      paint.strokeJoin = ui.StrokeJoin.round;
      paint.strokeCap = ui.StrokeCap.round;
    }
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontSize: size,
        fontFamily: fontFamily,
        height: 1.32, // 行高，与 python 版一致
      ),
    )
      ..pushStyle(ui.TextStyle(foreground: paint))
      ..addText(text);
    return pb.build()..layout(ui.ParagraphConstraints(width: maxW));
  }

  /// 过宽的段落优先在「最接近中点的空格」处断（「吉他课 99元4节」→「吉他课⏎99元4节」）
  static String _rebalance(
      String text, double size, double maxW, String? fontFamily) {
    return text.split('\n').map((para) {
      if (_build(para, size, KsCoverTheme.deepYellowRed, fontFamily, maxW: maxW)
              .longestLine <=
          maxW) {
        return para;
      }
      final parts = para.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) return para;
      String? best;
      var bestScore = double.infinity;
      for (var i = 1; i < parts.length; i++) {
        final a = parts.sublist(0, i).join(' ');
        final b = parts.sublist(i).join(' ');
        final wa = _build(a, size, KsCoverTheme.deepYellowRed, fontFamily, maxW: maxW).longestLine;
        final wb = _build(b, size, KsCoverTheme.deepYellowRed, fontFamily, maxW: maxW).longestLine;
        if (wa <= maxW && wb <= maxW) {
          final score = (wa - wb).abs();
          if (score < bestScore) {
            bestScore = score;
            best = '$a\n$b';
          }
        }
      }
      return best ?? para;
    }).join('\n');
  }
}
