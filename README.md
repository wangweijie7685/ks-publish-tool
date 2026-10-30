# ks-publish-tool

快手（cp.kuaishou.com 创作者平台）发布工具，支持 **主题封面生成 + 多账号 + 定时/立即发布**。

## 目录

| 路径 | 说明 |
|---|---|
| `dart_ks/` | Flutter App：多账号切换、应用内扫码登录（inappwebview 读 Cookie）、深黄底红字主题封面、一键发布 |
| `dart_ks/lib/ks_publish.dart` | 纯 Dart 发布链路（可 `dart run` 当 CLI 用，零第三方依赖） |
| `dart_ks/lib/ks_cover_painter.dart` | dart:ui 封面绘制（三套主题色卡） |
| `.github/workflows/ios-unsigned.yml` | 免签名 iOS 打包（无需 Apple 账号，产出可自签安装的 ipa） |
| `.github/workflows/ios-signed.yml` | 签名打包（需配置证书/描述文件 Secrets） |

## 快速开始

```bash
cd dart_ks
flutter pub get
flutter test test/gen_cover_test.dart   # 顺带生成一张封面预览
```

打 iOS 包：推到 GitHub → Actions → `iOS 打包（免签名）` → Run workflow → 下载 Artifacts 里的 `Runner-unsigned.ipa`。

## 安全说明

- 账号 Cookie 只存在设备本地（`HOME/Documents/.ks_accounts.json`），已在 `.gitignore` 排除
- 仓库内不含任何抓包配置（`ks_config.json`、`*.curl` 均已忽略）
- 本工具调用的是创作者平台内部接口，仅供本人账号使用，不对外分发

## 免责

非官方工具，与快手官方无关。请遵守平台规则，自担账号风险。
