#!/usr/bin/env dart
// ks_publish.dart — 快手发布纯 Dart 移植（对应 ks_ios.py，零第三方依赖）
// =====================================================================
// 只依赖 dart:io，任何有 Dart SDK 的机器上 `dart run` 即可，不需要 Flutter。
//
// 用法
// ----
// dart run ks_publish.dart send --video a.mp4 --cover-image cover.png \
//        --caption "标题 #话题" --at "2026-10-31 20:00"
// dart run ks_publish.dart send --file-id 123456 --cover-image cover.png --at "20:00"
// dart run ks_publish.dart cover --image cover.jpg          # 只传封面拿 coverKey
// dart run ks_publish.dart check                            # 自检登录态
//
// 凭证（三选一，优先级从高到低）：
//   1) --cookie "kuaishou.web.cp.api_ph=...; ..."
//   2) 环境变量 KS_COOKIE
//   3) --config ks_config.json 里带的 headers（ks_from_curl.py 生成的那个）
// 提交模板：--config ks_config.json（44 字段 body，建议配着用）

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ============================== CONFIG ==============================
const String kBase = 'https://cp.kuaishou.com';
const String kSubmitPath = '/rest/cp/works/v2/video/pc/submit';
const String kUploadPrePath = '/rest/cp/works/v2/video/pc/upload/pre';
const String kCoverUploadPath = '/rest/cp/works/v2/video/pc/upload/cover/upload';
const String kUserinfoPath = '/rest/cp/works/v2/user/info';
const int kUploadTypeVideo = 1;
const int kChunk = 4 * 1024 * 1024; // 4MB/片
const int kDirectMax = 8 * 1024 * 1024;
const String kUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

/// 提交 payload 的通用默认值（从 ks_config.json 的真实 44 字段里抽出，已剔除
/// cookie 与「单条视频专属」字段：fileId / coverKey / caption / publishTime /
/// mediaId / photoIdStr / videoDuration / associateTasks）。
/// App 端不用带任何配置文件；字段若被平台新增，只在这里补一条即可。
const Map<String, dynamic> ksDefaultPayload = {
  'coverTimeStamp': 0,
  'photoStatus': 1,
  'coverType': 1,
  'coverTitle': '',
  'photoType': 0,
  'collectionId': '',
  'longitude': '',
  'latitude': '',
  'poiId': 0,
  'notifyResult': 0,
  'domain': '',
  'secondDomain': '',
  'coverCropped': false,
  'pkCoverKey': '',
  'profileCoverKey': '',
  'downloadType': 1,
  'disableNearbyShow': false,
  'allowSameFrame': true,
  'movieId': '',
  'openPrePreview': false,
  'declareInfo': <String, dynamic>{},
  'activityIds': <dynamic>[],
  'riseQuality': false,
  'chapters': <dynamic>[],
  'useAiCaptionCover': false,
  'useAiCaption': false,
  'isUseIdealTime': false, // 关智能推荐时间，否则平台会改 publishTime
  'useAiCover': false,
  'kceInfo': '',
  'projectId': '',
  'recTagIdList': <dynamic>[],
  'videoInfoMeta': '',
  'previewUrlErrorMessage': '',
  'coPublishUser': <dynamic>[],
  'triggerH265': false,
};

// ============================== 工具 ==============================

/// 在任意嵌套 JSON 里递归找字段（对应 python 的 deep_find）
dynamic deepFind(dynamic obj, List<String> keys, [int depth = 0]) {
  if (depth > 6 || obj == null) return null;
  if (obj is Map) {
    for (final k in keys) {
      final v = obj[k];
      if (v != null && v != '' && v != 0 && v != '0') return v;
    }
    for (final v in obj.values) {
      final r = deepFind(v, keys, depth + 1);
      if (r != null) return r;
    }
  } else if (obj is List) {
    for (final v in obj.take(20)) {
      final r = deepFind(v, keys, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

Map<String, String> baseHeaders(String cookie) => {
      'Cookie': cookie,
      'Accept': 'application/json, text/plain, */*',
      'Origin': kBase,
      'Referer': '$kBase/article/publish/video',
      'User-Agent': kUa,
      'kpf': 'PC_WEB',
      'kpn': 'KUAISHOU_VISION',
    };

/// 解析 "2026-10-31 20:00" / "2026-10-31 20:00:00" / "20:00"（后者取今天或明天）
DateTime parseAt(String s) {
  final now = DateTime.now();
  final t = s.trim();
  final full = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?$');
  var m = full.firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!), int.parse(m.group(4)!), int.parse(m.group(5)!),
        m.group(6) != null ? int.parse(m.group(6)!) : 0);
  }
  final hm = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(t);
  if (hm != null) {
    var d = DateTime(now.year, now.month, now.day, int.parse(hm.group(1)!),
        int.parse(hm.group(2)!), hm.group(3) != null ? int.parse(hm.group(3)!) : 0);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d;
  }
  _die('时间格式看不懂：$s');
}

String human(int n) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = n.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(1)}${units[u]}';
}

Never _die(String msg) {
  stderr.writeln('✗ $msg');
  exit(2);
}

// ============================== HTTP ==============================

Future<Map<String, dynamic>> _sendJson(
    {required String method,
    required String url,
    required Map<String, String> headers,
    List<int>? body,
    Map<String, dynamic>? json,
    bool lenient = false}) async {
  final req = await HttpClient().openUrl(method, Uri.parse(url));
  headers.forEach(req.headers.set);
  List<int> payload;
  if (json != null) {
    headers['Content-Type'] = 'application/json';
    req.headers.set('Content-Type', 'application/json');
    payload = utf8.encode(jsonEncode(json));
  } else {
    payload = body ?? const [];
    if (payload.isNotEmpty && !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
      req.headers.set('Content-Type', 'application/octet-stream');
    }
  }
  req.contentLength = payload.length; // 服务端要 content-length，别用 chunked
  if (payload.isNotEmpty) req.add(payload);
  final res = await req.close().timeout(const Duration(minutes: 5));
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    _die('HTTP ${res.statusCode} $url\n${text.substring(0, text.length.clamp(0, 300))}');
  }
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    if (lenient) return const {'result': 1, 'raw': true}; // 直传/合并的响应不保证是 JSON
    _die('返回非 JSON：${text.substring(0, text.length.clamp(0, 300))}');
  }
}

/// 发起上传资格：返回 {token, fileId, gateway}
Future<Map<String, dynamic>> uploadPre(Map<String, String> h) async {
  final d = await _sendJson(
      method: 'POST', url: kBase + kUploadPrePath, headers: h, json: {'uploadType': kUploadTypeVideo});
  final data = (d['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  if (d['result'] != 1 || data['token'] == null) {
    _die('upload/pre 失败：${jsonEncode(d)}');
  }
  var eps = data['endPoints'];
  final list = eps is String
      ? eps.replaceAll(RegExp("[\\[\\]'\" ]"), '').split(',').where((e) => e.isNotEmpty).toList()
      : (eps as List?)?.map((e) => e.toString()).toList() ?? const [];
  final ep = list.isNotEmpty ? list.first : 'upload.kuaishouzt.com';
  return {
    'token': data['token'].toString(),
    'fileId': data['fileId'],
    'gateway': ep.startsWith('http') ? ep : 'https://$ep',
  };
}

/// 视频上传：≤8MB 直传，否则 4MB 分片；返回 fileId
Future<String> uploadVideo(Map<String, String> h, String path) async {
  final f = File(path);
  if (!f.existsSync()) _die('文件不存在：$path');
  final bytes = f.readAsBytesSync();
  final pre = await uploadPre(h);
  final token = pre['token'] as String;
  final gw = pre['gateway'] as String;
  print('upload/pre ok：fileId=${pre['fileId']}  endpoint=$gw');
  final upH = {
    'Accept': 'application/json, text/plain, */*',
    'Origin': kBase,
    'Referer': '$kBase/',
    'User-Agent': h['User-Agent'] ?? kUa,
  };
  if (bytes.length <= kDirectMax) {
    print('直传 ${human(bytes.length)} …');
    await _sendJson(
        method: 'POST',
        url: '$gw/api/upload?upload_token=$token',
        headers: {...upH, 'Content-Type': 'application/octet-stream'},
        body: bytes,
        lenient: true);
  } else {
    final total = (bytes.length + kChunk - 1) ~/ kChunk;
    final t0 = DateTime.now();
    for (var i = 0; i < total; i++) {
      final end = (i + 1) * kChunk < bytes.length ? (i + 1) * kChunk : bytes.length;
      final blob = bytes.sublist(i * kChunk, end);
      final d = await _sendJson(
          method: 'POST',
          url: '$gw/api/upload/fragment?upload_token=$token&fragment_id=$i',
          headers: {...upH, 'Content-Type': 'video/mp4'},
          body: blob);
      if (d['result'] != null && d['result'] != 1) {
        _die('分片 $i 被拒：${jsonEncode(d)}');
      }
      final sent = end;
      final el = DateTime.now().difference(t0).inMilliseconds / 1000;
      final speed = el > 0 ? sent / el : 0.0;
      print('  ${i + 1}/$total  ${(sent * 100 / bytes.length).toStringAsFixed(1)}%  ${human(speed ~/ 1)}/s');
    }
  }
  final done = await _sendJson(
      method: 'POST',
      url: '$gw/api/upload/complete?upload_token=$token&fragment_count=${bytes.length <= kDirectMax ? 1 : (bytes.length + kChunk - 1) ~/ kChunk}',
      headers: upH,
      lenient: true);
  print('complete: ${jsonEncode(done).substring(0, jsonEncode(done).length.clamp(0, 120))}');
  return pre['fileId'].toString();
}

/// 封面上传（multipart field=file），返回 coverKey
Future<String> uploadCover(Map<String, String> h, List<int> img, {String name = 'cover.png'}) async {
  final boundary = 'dartks${DateTime.now().millisecondsSinceEpoch}';
  final bb = BytesBuilder();
  bb.add(utf8.encode('--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$name"\r\n'
      'Content-Type: image/png\r\n\r\n'));
  bb.add(img);
  bb.add(utf8.encode('\r\n--$boundary--\r\n'));
  final hh = {...h}
    ..removeWhere((k, _) => k.toLowerCase() == 'content-type')
    ..['Content-Type'] = 'multipart/form-data; boundary=$boundary';
  final d = await _sendJson(
      method: 'POST', url: kBase + kCoverUploadPath, headers: hh, body: bb.takeBytes());
  final key = deepFind(d, ['coverKey', 'key']);
  if (key == null) _die('封面上传没返回 coverKey：${jsonEncode(d)}');
  print('封面上传 ok：coverKey=$key');
  return key.toString();
}

/// 提交发布（复用 ks_config.json 里的 44 字段模板；at=null 即立即发布）
Future<void> submit(Map<String, String> h, String fileId, String coverKey,
    String caption, DateTime? at, {Map<String, dynamic>? template}) async {
  final payload = <String, dynamic>{...(template ?? ksDefaultPayload)};
  for (final k in ['fileId', 'coverKey', 'caption', 'publishTime', 'mediaId',
    'photoIdStr', 'videoDuration', 'associateTasks', 'kuaishou.web.cp.api_ph']) {
    payload.remove(k);
  }
  payload['fileId'] = int.tryParse(fileId) ?? fileId;
  payload['photoStatus'] = 1;
  payload['caption'] = caption;
  payload['coverKey'] = coverKey; // 必须字符串
  payload['isUseIdealTime'] = false; // 关智能推荐时间，防止平台改发布时间
  final ph = RegExp(r'kuaishou\.web\.cp\.api_ph=([^;]+)').firstMatch(h['Cookie'] ?? '')?.group(1);
  if (ph != null) payload['kuaishou.web.cp.api_ph'] = ph;
  if (at != null) {
    payload['publishTime'] = at.millisecondsSinceEpoch; // 已实测：毫秒
  }
  print('提交：$kSubmitPath  fileId=$fileId  publishTime=${payload['publishTime']}  字段数=${payload.length}');
  final d = await _sendJson(method: 'POST', url: kBase + kSubmitPath, headers: h, json: payload);
  final ok = d['result'] == 1 || deepFind(d, ['photoId']) != null;
  print(jsonEncode(d).substring(0, jsonEncode(d).length.clamp(0, 400)));
  if (!ok) {
    final msg = '${d['message'] ?? d['msg'] ?? ''}';
    var hint = '';
    if (msg.contains('缺少参数')) hint = ' → 缺字段，把字段名补进 CONFIG';
    if (msg.contains('参数传值有误')) hint = ' → 字段名对但类型不对（coverKey 要字符串）';
    _die('提交失败（另常见原因：cookie 过期、时间早于当前）$hint');
  }
  print('已提交${at == null ? '立即' : '定时'}发布');
}

// ============================== 命令 ==============================

String _cookie(Map<String, String> a) {
  final c = a['cookie'] ?? Platform.environment['KS_COOKIE'] ?? '';
  if (c.isEmpty) _die('没拿到 Cookie：--cookie 或环境变量 KS_COOKIE（抓包 cp.kuaishou.com 后提取）');
  return c;
}

Map<String, dynamic>? _loadTemplate(String? path) {
  if (path == null || !File(path).existsSync()) return null;
  final cfg = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return (cfg['payload'] as Map?)?.cast<String, dynamic>();
}

Future<void> cmdSend(Map<String, String> a) async {
  final h = baseHeaders(_cookie(a));
  String? fileId = a['file-id'] ?? a['video-id'];
  if (fileId == null && a['video'] != null) {
    fileId = await uploadVideo(h, a['video']!);
  }
  if (fileId == null) _die('给 --video / --file-id / --video-id 之一');

  String? coverKey = a['cover-key'];
  if (coverKey == null && a['cover-image'] != null) {
    final img = File(a['cover-image']!).readAsBytesSync();
    coverKey = await uploadCover(h, img,
        name: a['cover-image']!.split(Platform.pathSeparator).last);
  }
  if (coverKey == null) _die('缺封面：--cover-image 或 --cover-key');

  DateTime? at = a['at'] != null ? parseAt(a['at']!) : null;
  await submit(h, fileId, coverKey, a['caption'] ?? '', at,
      template: _loadTemplate(a['config']));
}

Future<void> cmdCover(Map<String, String> a) async {
  if (a['image'] == null) _die('给 --image 封面图片路径');
  final h = baseHeaders(_cookie(a));
  final key = await uploadCover(h, File(a['image']!).readAsBytesSync(),
      name: a['image']!.split(Platform.pathSeparator).last);
  print('\ncoverKey = $key');
}

Future<void> cmdCheck(Map<String, String> a) async {
  final h = baseHeaders(_cookie(a));
  final d = await _sendJson(method: 'GET', url: kBase + kUserinfoPath, headers: h);
  print(jsonEncode(d).substring(0, jsonEncode(d).length.clamp(0, 300)));
  if ('${d['result']}' == '1000') print('→ cookie 可能已失效');
}

/// 极简参数解析：--key value / --flag
Map<String, String> parseArgs(List<String> argv, int from) {
  final out = <String, String>{};
  for (var i = from; i < argv.length; i++) {
    final s = argv[i];
    if (s.startsWith('--')) {
      final key = s.substring(2);
      if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
        out[key] = argv[++i];
      } else {
        out[key] = 'true';
      }
    }
  }
  return out;
}

Future<void> main(List<String> argv) async {
  final cmd = argv.isNotEmpty ? argv.first : 'help';
  final a = parseArgs(argv, 1);
  switch (cmd) {
    case 'send':
      await cmdSend(a);
    case 'cover':
      await cmdCover(a);
    case 'check':
      await cmdCheck(a);
    default:
      stdout.writeln('''快手发布 Dart 版（对应 ks_ios.py）
  dart run ks_publish.dart send   --video a.mp4 --cover-image cover.png --caption "标题" --at "2026-10-31 20:00"
  dart run ks_publish.dart send   --file-id 123 --cover-key KEY --caption "标题"   # 立即发布
  dart run ks_publish.dart cover  --image cover.jpg
  dart run ks_publish.dart check''');
  }
}
