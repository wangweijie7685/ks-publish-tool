// login_webview.dart — 应用内登录快手（WebView + 读取 Cookie 自动入库）
// ================================================================
// 流程：打开 cp.kuaishou.com 登录页 → 用户扫码/账密登录 → 点「我已登录，读取凭证」
//      → 用 flutter_inappwebview 的 CookieManager 读取该域名全部 Cookie
//      → 拼成 Cookie 字符串返回，由调用方存进账号池。
//
// 注意：kuaishou.web.cp.api_ph 这类 HttpOnly Cookie 只有原生 CookieManager 能读到，
//      网页 JS 的 document.cookie 读不到 —— 所以必须用 inappwebview 而不是普通 webview。

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class KsLoginPage extends StatefulWidget {
  /// 要登录的站点，默认创作者平台（发布接口就在这里）
  final String url;

  const KsLoginPage({super.key, this.url = 'https://cp.kuaishou.com/profile'});

  @override
  State<KsLoginPage> createState() => _KsLoginPageState();
}

class _KsLoginPageState extends State<KsLoginPage> {
  InAppWebViewController? _ctl;
  bool _loading = true;
  bool _busy = false;

  Future<void> _readCookie() async {
    setState(() => _busy = true);
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://cp.kuaishou.com'),
        webViewController: _ctl,
      );
      if (cookies.isEmpty) {
        _toast('没读到 Cookie，先在上方完成登录');
        return;
      }
      final str = cookies
          .map((c) => '${c.name}=${c.value ?? ''}')
          .where((s) => !s.endsWith('='))
          .join('; ');
      if (!str.contains('kuaishou.web.cp.api_ph=')) {
        _toast('缺少 api_ph（登录态还没生效），刷新页面再试或改用「粘贴 Cookie」');
        return;
      }
      if (mounted) Navigator.of(context).pop(str);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录快手'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _readCookie,
            child: Text(_busy ? '读取中…' : '我已登录，读取凭证'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                useHybridComposition: true,
                userAgent:
                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
              ),
              onWebViewCreated: (c) => _ctl = c,
              onLoadStop: (c, url) => setState(() => _loading = false),
              onReceivedError: (c, req, err) => _toast('加载出错：${err.description}'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 手动粘贴 Cookie 的兜底入口（扫码登录被封控/读不到 Cookie 时用）
Future<String?> showPasteCookieDialog(BuildContext context) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('粘贴 Cookie'),
      content: TextField(
        controller: ctl,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: 'kuaishou.web.cp.api_ph=...; did=...; ...',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final s = ctl.text.trim();
            Navigator.pop(ctx, s.isEmpty ? null : s);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
