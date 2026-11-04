# 发布与自动更新

Slimshot 用 Sparkle 2 做应用内更新，用 GitHub Actions 做标准发布。本文是维护者的一次性配置和每次发版流程。

## 一次性配置

### 1. 拉取 Sparkle

```bash
make sparkle        # 下载 Sparkle 2.7.1 到 vendor/sparkle（已 gitignore）
```

`scripts/fetch-sparkle.sh` 固定版本和 SHA-256；CI 也会自动执行。

### 2. 生成 Sparkle EdDSA 密钥

```bash
./scripts/sparkle-setup.sh
```

脚本会：

- 在 Keychain 生成/读取 EdDSA 密钥
- 打印公钥
- 把私钥导出到 `sparkle-private-key`（权限 600，已在 `.gitignore`）

然后到 GitHub 仓库设置：

| 类型 | 名称 | 值 |
| --- | --- | --- |
| Repository variable | `SPARKLE_PUBLIC_KEY` | 脚本打印的公钥 |
| Repository secret | `SPARKLE_PRIVATE_KEY` | `sparkle-private-key` 文件内容 |

**私钥永远不要提交到仓库。** 公钥会写进 `Info.plist` 的 `SUPublicEDKey`。

### 3. 签名证书（强烈建议）

CI 可以 ad-hoc 构建，但 ad-hoc 的屏幕录制权限会在每次更新后失效。正式发布请配置稳定自签名证书：

1. 本地运行 `./scripts/create-dev-cert.sh`（只需要一次）
2. 从 Keychain 导出该身份的 `.p12`
3. 设置 GitHub secrets：

| Secret | 说明 |
| --- | --- |
| `CODESIGN_CERT_P12` | `.p12` 的 base64（`base64 -i cert.p12 | pbcopy`） |
| `CODESIGN_CERT_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `CODESIGN_IDENTITY` | 证书 CN，例如 `Slimshot Dev` |

没有这三个 secret 时，CI 会 ad-hoc 签名并打印警告；应用能构建，但更新后的 TCC 权限可能重置。

## 每次发布

1. 确认工作区干净，更新版本号相关文案（如有）
2. 打标签并推送：

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions `Release` 会：

- 检查 `SPARKLE_PUBLIC_KEY` / `SPARKLE_PRIVATE_KEY`
- 拉取 Sparkle
- 导入签名证书（如果配置了）
- 构建 **arm64 + x86_64** universal app
- 把版本写进 `CFBundleShortVersionString`，把 `GITHUB_RUN_NUMBER` 写进 `CFBundleVersion`
- 写 `SUFeedURL=https://github.com/<repo>/releases/latest/download/appcast.xml`
- 生成：
  - `Slimshot-<version>.zip`：用户安装包（app + install.command + LICENSE + README）
  - `Slimshot-<version>-update.zip`：Sparkle 更新包（app 在 zip 根目录）
  - 两个 `.sha256`
  - `appcast.xml`：带 EdDSA 签名的 Sparkle feed
- 创建 GitHub Release 并上传全部资产

`BUILD_NUMBER` 使用 workflow run number，单调递增；Sparkle 用它比较版本。

## 本地测试更新

```bash
make sparkle

SPARKLE_PUBLIC_KEY="<public key>" \
SPARKLE_FEED_URL="https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml" \
make

make dist
```

本地没有 feed/公钥时，菜单「检查更新…」会置灰，日志写 `sparkle disabled: missing feed URL or public key`，不影响截图功能。

## appcast

`scripts/generate-appcast.sh` 用 Sparkle 的 `sign_update -p` 生成签名，写一个最小 appcast：

- `sparkle:version` = `CFBundleVersion` / run number
- `sparkle:shortVersionString` = tag 去掉 `v`
- `sparkle:minimumSystemVersion` = 14.0
- enclosure 指向 `Slimshot-<version>-update.zip`，带 `sparkle:edSignature` 和 `length`

`SUFeedURL` 固定为 `releases/latest/download/appcast.xml`，所以每次发布只要把 `appcast.xml` 作为 release asset 上传即可。

## 故障排查

- **检查更新置灰**：Info.plist 的 `SUFeedURL` 或 `SUPublicEDKey` 为空。确认 CI 变量/本地环境变量。
- **更新提示签名无效**：`SPARKLE_PUBLIC_KEY` 和 `SPARKLE_PRIVATE_KEY` 不是同一对密钥；重新运行 `scripts/sparkle-setup.sh` 并同步两处。
- **更新安装失败**：优先检查签名身份是否稳定；ad-hoc 构建的 XPC/权限可能被系统拒绝。
- **更新后权限丢失**：使用稳定的 `CODESIGN_IDENTITY`，不要每次 ad-hoc 重建。
- **feed 404**：release 必须包含 `appcast.xml`，并且是最新 release（`latest`）。
