// main.dart — 快手发布小工具（多账号 + 应用内登录）
// ================================================================
// 流程：登录/切换账号 → 填标题选主题 → 生成封面预览 → 上传视频 + 封面 → 发布/定时
// 依赖：flutter_inappwebview（应用内登录读 Cookie），其余全是 Flutter 官方库

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'account_store.dart';
import 'ks_cover_painter.dart';
import 'ks_publish.dart' as ks;
import 'login_webview.dart';

void main() => runApp(const KsApp());

class KsApp extends StatelessWidget {
  const KsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '快手发布',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB8860B)),
        useMaterial3: true,
      ),
      home: const KsHomePage(),
    );
  }
}

class KsHomePage extends StatefulWidget {
  const KsHomePage({super.key});

  @override
  State<KsHomePage> createState() => _KsHomePageState();
}

class _KsHomePageState extends State<KsHomePage> {
  final _store = AccountStore.instance;
  final _title = TextEditingController(text: '限时秒杀\n最后3天');
  final _sub = TextEditingController(text: '侯马六弦琴行');
  final _caption = TextEditingController();
  final _at = TextEditingController();
  final _video = TextEditingController();

  KsCoverTheme _theme = KsCoverTheme.deepYellowRed;
  int _w = 1080, _h = 1440;
  Uint8List? _preview;
  bool _busy = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _store.load().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_title, _sub, _caption, _at, _video]) {
      c.dispose();
    }
    super.dispose();
  }

  void _log(String s) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    setState(() => _logs.insert(0, '[$t] $s'));
  }

  // ---------------- 账号 ----------------

  Future<void> _loginNew() async {
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const KsLoginPage()),
    );
    if (cookie == null || cookie.isEmpty) return;
    await _store.add(name: '账号${_store.accounts.length + 1}', cookie: cookie);
    setState(() {});
    _log('已登录并保存账号：${_store.current?.name}');
  }

  Future<void> _addByPaste() async {
    final cookie = await showPasteCookieDialog(context);
    if (cookie == null) return;
    if (!cookie.contains('kuaishou.web.cp.api_ph=')) {
      _log('⚠️ Cookie 里没有 api_ph，发布大概率失败');
    }
    await _store.add(name: '粘贴${_store.accounts.length + 1}', cookie: cookie);
    setState(() {});
    _log('已添加账号：${_store.current?.name}');
  }

  Future<void> _openAccountSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('切换账号', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (_store.accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('还没有账号，先登录一个'),
              ),
            ..._store.accounts.map((a) => ListTile(
                  leading: Icon(a.lastOk ? Icons.check_circle : Icons.error_outline,
                      color: a.lastOk ? Colors.green : Colors.orange),
                  title: Text(a.name),
                  subtitle: Text('${a.hint}  ·  api_ph ${a.hasApiPh ? '✓' : '✗'}'),
                  trailing: a.id == _store.currentId
                      ? const Icon(Icons.radio_button_checked)
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () async {
                    await _store.select(a.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                    _log('已切换到：${a.name}');
                  },
                  onLongPress: () async {
                    await _store.remove(a.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                    _log('已删除账号');
                  },
                )),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫码登录新账号'),
              onTap: () {
                Navigator.pop(ctx);
                _loginNew();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴 Cookie 添加'),
              onTap: () {
                Navigator.pop(ctx);
                _addByPaste();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------- 封面 / 发布 ----------------

  Future<void> _genPreview() async {
    setState(() => _busy = true);
    try {
      final png = await KsCover.render(
        text: _title.text,
        sub: _sub.text,
        theme: _theme,
        width: _w,
        height: _h,
      );
      setState(() => _preview = png);
      _log('封面预览已生成（${_w}x$_h）');
    } catch (e) {
      _log('封面生成失败：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final acc = _store.current;
    if (acc == null) {
      _log('先登录/选择一个账号');
      return;
    }
    if (_video.text.trim().isEmpty) {
      _log('先填视频文件的本地路径');
      return;
    }
    setState(() => _busy = true);
    try {
      final h = ks.baseHeaders(acc.cookie);
      _log('使用账号「${acc.name}」→ 上传视频：${_video.text}');
      final fileId = await ks.uploadVideo(h, _video.text.trim());
      _log('视频 fileId=$fileId');

      final png = _preview ??
          await KsCover.render(
              text: _title.text, sub: _sub.text, theme: _theme, width: _w, height: _h);
      final coverKey = await ks.uploadCover(h, png);
      _log('封面 coverKey=$coverKey');

      final at = _at.text.trim().isEmpty ? null : ks.parseAt(_at.text.trim());
      await ks.submit(h, fileId, coverKey, _caption.text, at);

      if (mounted) {
        acc.lastOk = true;
        await _store.save();
      }
      _log(at == null ? '✅ 已立即发布' : '✅ 已定时发布：${at.toIso8601String()}');
    } catch (e) {
      if (mounted) {
        acc.lastOk = false;
        await _store.save();
      }
      _log('发布失败：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        minLines: 1,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _accountBar() {
    final acc = _store.current;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(acc == null ? Icons.person_off : Icons.person,
            color: acc == null ? Colors.grey : Colors.green),
        title: Text(acc?.name ?? '未登录'),
        subtitle: Text(acc == null ? '点右侧按钮登录快手账号' : '标识 ${acc.hint}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (acc != null)
              IconButton(
                tooltip: '切换/管理账号',
                icon: const Icon(Icons.swap_horiz),
                onPressed: _openAccountSheet,
              ),
            IconButton(
              tooltip: '登录新账号',
              icon: const Icon(Icons.login),
              onPressed: _loginNew,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快手发布'),
        actions: [
          IconButton(
            tooltip: '账号管理',
            icon: const Icon(Icons.manage_accounts),
            onPressed: _openAccountSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _accountBar(),
            _field(_title, '封面主标题（\\n 可换行）', lines: 2),
            _field(_sub, '封面副标题'),
            Wrap(
              spacing: 8,
              children: KsCoverTheme.all
                  .map((t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _theme.name == t.name,
                        onSelected: (_) => setState(() => _theme = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: {
                '3:4': [1080, 1440],
                '9:16': [1080, 1920],
                '1:1': [1080, 1080],
              }.entries.map((e) {
                final sel = _w == e.value[0] && _h == e.value[1];
                return ChoiceChip(
                  label: Text(e.key),
                  selected: sel,
                  onSelected: (_) => setState(() {
                    _w = e.value[0];
                    _h = e.value[1];
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _genPreview,
                child: const Text('生成封面预览'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _preview == null
                    ? const SizedBox.shrink()
                    : AspectRatio(
                        aspectRatio: _w / _h,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_preview!, fit: BoxFit.contain),
                        ),
                      ),
              ),
            ]),
            const Divider(height: 32),
            _field(_caption, '视频文案 / 话题', lines: 3),
            _field(_at, '发布时间（留空=立即，如 2026-10-31 20:00）'),
            _field(_video, '视频文件本地路径（可加 file_picker 选片）'),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _publish,
                child: Text(_busy ? '处理中…' : '上传并发布'),
              ),
            ),
            const Divider(height: 32),
            ..._logs.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(l,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                )),
          ],
        ),
      ),
    );
  }
}
