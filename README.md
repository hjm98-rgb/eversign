# EverSign / 永签

全新的 iOS 永久签名安装器。界面、应用结构全部自研，不复用 TrollStore 的 UI 与代码结构；
唯一共用的底层是这个漏洞本身：**CVE-2023-41991 —— CoreTrust 对多签名者 CMS blob 校验不当**，
以及 iOS 15 遗留的「根证书链不校验」签名缺陷。

## 适用设备

- iPhone 7 / A10 / iOS 15.8.8 ✅（本仓库产物就是按这台编的）
- 其他 iOS 15.x 设备同样在漏洞影响范围内
- iOS 16.7 / 17.0.1 及以后：漏洞已修复，无解

## 已验证

| 项 | 结果 |
|---|---|
| theos 交叉编译 (Linux runner) | 通过 |
| 产物 EverSign.app (arm64 Mach-O) | 通过 |
| 签名链嵌入 | `TrollStore iPhone OS Application Signing` → `TrollStore iPhone Certification Authority` → `TrollStore iPhone Root CA` |
| entitlements 嵌入 | `platform-application` / `no-sandbox` / `AppBundles` / mobileinstall SPI 等 |

## 架构

```
EverSign/
├── main.m                   入口
├── ESAppDelegate            窗口
├── ESRootController         底部三页签容器
├── ESStoreController        安装页（自定义深色卡片 + 环形进度）
├── ESInstalledController    已安装列表（扫描 /Applications）
├── ESSettingsController     设备信息 / 签名方式 / 安装目录
├── ESInstaller.m            安装引擎：解包 → 落盘 → 改权限 → 伪造签名 → 注册
├── ESZip.m                  自研 zip 解析（stored + deflate，只依赖 libz）
└── Resources/
    ├── ldid                 iOS arm64 签名器（构建时从 opa334/ldid 拉取）
    └── victim.p12           遗留 CoreTrust 签名证书
```

安装流程：

1. `ESZip` 解包 IPA 到临时目录
2. 找到 `Payload/*.app`，读 `Info.plist` 拿 BundleID
3. 整包写入 `/Applications`（这是系统 App 目录，才能绕过 FrontBoard 的 libmis 检查）
4. 递归修正所有权 `root:wheel` 与权限
5. 对每个 Mach-O 调 `ldid -K victim.p12 -S entitlements` 重签 —— 踩 CoreTrust 缺陷，让系统认它是合法签名
6. 通过 `LSApplicationWorkspace` 注册，图标出现在桌面

## 构建

推送到 `main` 即自动构建（GitHub Actions，Ubuntu 22.04 + theos 交叉编译），
产物在 Actions 的 `EverSign-ipa` artifact 里。

首次安装到设备需要一次注入（iPhone 7 是 checkm8 设备）：

- **palera1n**：越狱后把 `EverSign.app` 放进 `/Applications`，`chown -R root:wheel`、`chmod 755`，
  再 `uicache`，即可用
- 装好之后，EverSign 负责后续所有 IPA 的永久签名安装，不再需要电脑

## 待办

- [ ] 从 IPA 原有签名里读取 entitlements，而不是统一套用一份宽松权限
- [ ] 应用图标提取与展示
- [ ] 卸载 / 图标缓存重建入口
