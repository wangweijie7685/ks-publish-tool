// account_store.dart — 快手账号池（多账号切换，纯 Dart 持久化，无插件依赖）
// ================================================================
// 每个账号存一份 Cookie（cp.kuaishou.com 网页端凭证），互不干扰。
// 存储位置：iOS/macOS 取 HOME/Documents；其他平台取当前目录下的 .ks_accounts.json。
// Cookie 是敏感信息，这里只落本地沙盒，不进代码仓库、不上传。

import 'dart:convert';
import 'dart:io';

class KsAccount {
  final String id;
  String name; // 备注名/昵称，自己认得就行
  String cookie;
  int createdAt; // ms
  bool lastOk; // 上次校验结果（默认 true，校验失败置 false）

  KsAccount({
    required this.id,
    required this.name,
    required this.cookie,
    int? createdAt,
    this.lastOk = true,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 从 Cookie 里粗略推一个标识，便于列表展示（快手号/用户 id 通常在这些字段里）
  String get hint {
    for (final key in ['kuaishou.web.cp.api_ph', 'userId', 'user_id', 'did']) {
      final m = RegExp('$key=([^;]+)').firstMatch(cookie);
      if (m != null) {
        final v = m.group(1)!;
        return v.length > 10 ? '${v.substring(0, 10)}…' : v;
      }
    }
    return '未知';
  }

  bool get hasApiPh => cookie.contains('kuaishou.web.cp.api_ph=');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cookie': cookie,
        'createdAt': createdAt,
        'lastOk': lastOk,
      };

  static KsAccount fromJson(Map<String, dynamic> j) => KsAccount(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        cookie: (j['cookie'] ?? '') as String,
        createdAt: (j['createdAt'] as num?)?.toInt(),
        lastOk: (j['lastOk'] ?? true) as bool,
      );
}

class AccountStore {
  static final AccountStore instance = AccountStore._();
  AccountStore._();

  List<KsAccount> accounts = [];
  String? currentId;

  KsAccount? get current {
    for (final a in accounts) {
      if (a.id == currentId) return a;
    }
    return null;
  }
  bool get isEmpty => accounts.isEmpty;

  File get _file {
    // iOS/macOS 沙盒：HOME/Documents 可写；Windows/Linux 退回当前目录
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && (Platform.isIOS || Platform.isMacOS)) {
      final dir = Directory('$home/Documents');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/.ks_accounts.json');
    }
    return File('${Directory.current.path}/.ks_accounts.json');
  }

  Future<void> load() async {
    try {
      if (_file.existsSync()) {
        final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
        accounts = (j['accounts'] as List? ?? [])
            .map((e) => KsAccount.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        currentId = j['currentId'] as String?;
        if (currentId == null && accounts.isNotEmpty) currentId = accounts.first.id;
      }
    } catch (_) {
      accounts = [];
    }
  }

  Future<void> save() async {
    final j = {
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'currentId': currentId,
    };
    _file.writeAsStringSync(jsonEncode(j));
  }

  Future<KsAccount> add({required String name, required String cookie}) async {
    final acc = KsAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? '账号${accounts.length + 1}' : name.trim(),
      cookie: cookie.trim(),
    );
    accounts.add(acc);
    currentId = acc.id;
    await save();
    return acc;
  }

  Future<void> updateCookie(String id, String cookie) async {
    final i = accounts.indexWhere((a) => a.id == id);
    if (i >= 0) {
      accounts[i].cookie = cookie.trim();
      accounts[i].lastOk = true;
      await save();
    }
  }

  Future<void> rename(String id, String name) async {
    final i = accounts.indexWhere((a) => a.id == id);
    if (i >= 0) {
      accounts[i].name = name.trim();
      await save();
    }
  }

  Future<void> remove(String id) async {
    accounts.removeWhere((a) => a.id == id);
    if (currentId == id) currentId = accounts.isEmpty ? null : accounts.first.id;
    await save();
  }

  Future<void> select(String id) async {
    currentId = id;
    await save();
  }
}
