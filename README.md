# wechat-devtools - 微信开发者工具 Codex Skill

让 Codex 直接控制微信开发者工具（WeChat DevTools），实现小程序项目管理、真机预览和模拟器截图。

## 功能概览

| 功能 | 说明 |
|------|------|
| 环境检测 | 自动发现 DevTools 安装位置、HTTP 端口、运行状态 |
| 项目管理 | 打开/关闭小程序项目 |
| 真机预览 | 生成预览二维码（终端 ASCII / 图片 / base64） |
| 模拟器截图 | 通过 miniprogram-automator SDK 截取模拟器页面 |
| 批量截图 | 遍历 app.json pages 自动截取全部页面 |
| 构建管理 | 构建 npm、清除编译/文件缓存 |
| 状态查询 | 综合环境状态（含 Node.js/npx 可用性） |
| Claude Code 互通 | 共享临时目录 + JSON 协议实现跨 Agent 协同 |

## 安装

```bash
# 复制到 Codex skills 目录
cp -r wechat-devtools ~/.codex/skills/

# 或在 Codex 中通过 skill-installer 安装
```

## 前置条件

1. **微信开发者工具** [下载安装](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)
2. **设置 → 安全设置 → 开启"服务端口"**（CLI 和 HTTP API 必需）
3. 微信开发者工具已登录微信账号
4. **截图功能额外需要**：
   - [Node.js](https://nodejs.org/) 已安装
   - `npm install -g miniprogram-automator`

## 快速开始

### 环境检测

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  "$env:USERPROFILE\.codex\skills\wechat-devtools\scripts\wxtools.ps1" detect
```

返回 JSON：
```json
{
  "found": true,
  "cliPath": "E:\\wx-xcx\\微信web开发者工具\\cli.bat",
  "httpPort": 27462,
  "autoPort": 9420,
  "devtoolsRunning": true,
  "servicePortEnabled": true,
  "nodeAvailable": true
}
```

### 真机预览

```powershell
$WXTOOLS = "$env:USERPROFILE\.codex\skills\wechat-devtools\scripts\wxtools.ps1"

# 终端 ASCII 二维码（可直接扫）
powershell -File "$WXTOOLS" preview --project "E:\miniapp" --qr-format terminal

# 保存为 PNG 图片
powershell -File "$WXTOOLS" preview --project "E:\miniapp" --qr-format image --qr-output ".\qr.png"
```

### 模拟器截图

```powershell
$WXTOOLS = "$env:USERPROFILE\.codex\skills\wechat-devtools\scripts\wxtools.ps1"

# 单页面截图
powershell -File "$WXTOOLS" screenshot `
  --project "E:\miniapp" `
  --page "/pages/index/index" `
  --output ".\screenshot.png"

# 批量全页面截图
powershell -File "$WXTOOLS" screenshot-all `
  --project "E:\miniapp" `
  --output-dir ".\screenshots\"
```

## 全部命令

| 子命令 | 用途 | 关键参数 |
|--------|------|----------|
| `detect` | 检测 DevTools 环境 | 无 |
| `open` | 打开小程序项目 | `--project <path>`, `--pure-simulator` |
| `close` | 关闭项目窗口 | `--project <path>` |
| `preview` | 生成真机预览二维码 | `--project`, `--qr-format`, `--qr-output`, `--compile-condition` |
| `autopreview` | 自动预览（免扫码） | `--project` |
| `build-npm` | 构建 npm 依赖 | `--project` |
| `clear-cache` | 清除缓存 | `--project`, `--cache-type` |
| `start-auto` | 开启 Automator 端口 | `--project`, `--auto-port` |
| `screenshot` | 单页面截图 | `--project`, `--page`, `--output`, `--wait` |
| `screenshot-all` | 批量全页面截图 | `--project`, `--output-dir`, `--wait` |
| `status` | 综合状态查询 | 无 |

## 与 Claude Code 互通

截图保存到共享临时目录后，Claude Code 可读取并做视觉分析：

```
%TEMP%\wechat-devtools-screenshots\          # 共享截图目录
%TEMP%\wechat-devtools-screenshots\analysis-request.json  # 分析请求协议
```

> Codex (GPT-5.5) 本身拥有视觉能力，截图后可直接分析，无需跨 Agent。

## 错误处理

所有命令输出 JSON，失败时返回结构化错误：
```json
{
  "success": false,
  "errorCode": "ERR_NOT_LOGIN",
  "errorMessage": "未登录微信开发者工具",
  "hints": ["请在微信开发者工具中扫码登录"]
}
```

## 技术架构

```
Codex Skill (SKILL.md)
  └─ wxtools.ps1 (主控脚本)
       ├─ find_devtools.ps1 (环境检测)
       │    ├─ CLI 路径发现 (多层 fallback)
       │    ├─ .ide 端口读取
       │    └─ HTTP 端口可达性验证
       ├─ cli.bat (微信官方 CLI)
       │    ├─ open / close / preview / upload
       │    ├─ build-npm / clear-cache
       │    └─ auto (Automator WebSocket)
       ├─ screenshot_automator.js (截图核心)
       │    └─ miniprogram-automator (WebSocket)
       └─ JSON 结构化输出
```

## 参考

- [微信开发者工具 CLI 文档](https://developers.weixin.qq.com/miniprogram/dev/devtools/cli.html)
- [微信开发者工具 HTTP API](https://developers.weixin.qq.com/miniprogram/dev/devtools/http.html)
- [miniprogram-automator](https://developers.weixin.qq.com/miniprogram/dev/devtools/auto/automator.html)
- [miniprogram-ci](https://developers.weixin.qq.com/miniprogram/dev/devtools/ci.html)

## License

MIT
