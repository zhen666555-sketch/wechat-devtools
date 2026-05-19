---
name: "wechat-devtools"
description: >
  控制和自动化微信开发者工具（WeChat DevTools）。支持打开小程序项目、生成真机预览二维码、
  模拟器截图、清除缓存、构建 npm、上传代码。使用 miniprogram-automator SDK 进行模拟器截图
  和页面自动化。
  触发条件：(1) 任务涉及微信小程序、WeChat DevTools、miniprogram，(2) 需要真机预览二维码，
  (3) 需要对小程序模拟器截图做 UI 审查，(4) 需要自动化操作小程序页面，(5) 需要上传或构建小程序。
---

# 微信开发者工具 (WeChat DevTools) 技能

通过 CLI 和 HTTP API 控制微信开发者工具，实现项目管理、真机预览和模拟器截图。

## 前置条件检查（每次操作前必须执行）

在开始任何操作之前，运行环境检测检查四项前置条件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-path>/scripts/find_devtools.ps1"
```

检测项目：
1. **微信开发者工具已安装** - `cli.bat` 文件存在
2. **DevTools 正在运行** - 进程检测
3. **服务端口已开启** - `.ide` 文件可读且 HTTP 端口可达
4. **HTTP 端口可达** - `GET /v2/islogin` 有响应

### 常见失败处理

| 错误 | 修复操作 |
|------|----------|
| DevTools 未安装 | 请从 [微信官方](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html) 下载安装 |
| DevTools 未运行 | 请手动启动微信开发者工具 |
| 服务端口未开启 | 设置 → 安全设置 → 开启"服务端口" |
| 未登录 | 在微信开发者工具中扫码登录 |

如果自动检测失败，可通过参数手动指定路径和端口。

## 核心命令速查

所有命令通过主控脚本 `wxtools.ps1` 执行，输出 JSON 格式。

| 子命令 | 用途 | 关键参数 |
|--------|------|----------|
| `detect` | 检测 DevTools 环境 | 无 |
| `open` | 打开小程序项目 | `--project <path>` |
| `close` | 关闭项目窗口 | `--project <path>` |
| `preview` | 生成真机预览二维码 | `--project`, `--qr-format`, `--qr-output` |
| `autopreview` | 自动预览（免扫码） | `--project` |
| `build-npm` | 构建 npm 依赖 | `--project` |
| `clear-cache` | 清除缓存 | `--project`, `--cache-type` |
| `start-auto` | 开启 Automator 端口 | `--project`, `--auto-port` |
| `screenshot` | 单页面截图 | `--project`, `--page`, `--output` |
| `screenshot-all` | 批量全页面截图 | `--project`, `--output-dir` |
| `status` | 综合状态查询 | 无 |

## 工作流 A：真机预览

生成微信扫码预览的真机二维码。

```powershell
# 步骤 1: 环境检测 + 定义路径
$env:CODEX_HOME = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { "$env:USERPROFILE\.codex" }
$WXTOOLS = "$env:CODEX_HOME\skills\wechat-devtools\scripts\wxtools.ps1"

# 步骤 2: 环境检测
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" detect

# 步骤 3: 构建 npm (可选，如果项目有 npm 依赖)
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" build-npm --project "E:\miniapp"

# 步骤 4: 生成二维码 (三种格式选一)

# 终端 ASCII 二维码 (默认，可直接扫)
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" preview --project "E:\miniapp" --qr-format terminal

# 保存为 PNG 图片
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" preview --project "E:\miniapp" --qr-format image --qr-output ".\output\qr.png"

# 输出 base64 编码
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" preview --project "E:\miniapp" --qr-format base64

# 注意: 如果生成后看不到二维码，检查 DevTools 是否已登录微信账号
```

手动判断是否需要 `build-npm`：检查项目根目录是否有 `package.json` 且 `node_modules` 目录不存在或不完整。

## 工作流 B：模拟器截图 + 视觉分析

截取小程序模拟器中的页面，供视觉模型分析。

```powershell
# 步骤 1: 定义路径
$env:CODEX_HOME = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { "$env:USERPROFILE\.codex" }
$WXTOOLS = "$env:CODEX_HOME\skills\wechat-devtools\scripts\wxtools.ps1"

# 步骤 2: 打开项目
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" open --project "E:\miniapp"

# 步骤 3: 开启 Automator 端口 (截图前置步骤)
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" start-auto --project "E:\miniapp" --auto-port 9420

# 步骤 4: 截图
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" screenshot `
  --project "E:\miniapp" `
  --page "/pages/index/index" `
  --output "$env:TEMP\wechat-screenshots\index.png" `
  --wait 2000

# 步骤 5: 读取截图进行视觉分析
# Codex/Claude 使用内置视觉能力读取截图文件并分析 UI 布局、对齐等
```

截图功能依赖：
- Node.js 已安装（`node --version` 可用）
- `miniprogram-automator` 可用（`npx -y miniprogram-automator` 能自动拉取）
- Automator 端口 9420 未被占用

## 工作流 C：批量全页面截图

遍历 `app.json` 中定义的所有页面，自动生成全部截图。

```powershell
$WXTOOLS = "$env:USERPROFILE\.codex\skills\wechat-devtools\scripts\wxtools.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" screenshot-all `
  --project "E:\miniapp" `
  --output-dir ".\screenshots\" `
  --wait 2000
```

返回 JSON 汇总报告，包含成功/失败数量和每个页面的截图路径。

内部逻辑：读取 `app.json` → 遍历 `pages` 数组 → 逐页 `reLaunch` → 等待渲染 → 截图 → 汇总结果。

## 工作流 D：Claude Code 互通

截图的共享路径和协议，实现 Codex ↔ Claude Code 协同。

### 共享目录

```
Windows:  %TEMP%\wechat-devtools-screenshots\
macOS:    $TMPDIR/wechat-devtools-screenshots/
```

### 互通流程

1. **Codex 执行截图** → 保存到共享目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$WXTOOLS" screenshot `
  --project "E:\miniapp" `
  --page "/pages/index/index" `
  --output "$env:TEMP\wechat-devtools-screenshots\index.png"
```

2. **Codex 写入分析请求**：

写入 `%TEMP%\wechat-devtools-screenshots\analysis-request.json`：
```json
{
  "version": "1.0",
  "timestamp": "2026-05-19T20:00:00Z",
  "screenshots": [
    {
      "page": "/pages/index/index",
      "path": "C:\\Users\\33508\\AppData\\Local\\Temp\\wechat-devtools-screenshots\\index.png",
      "width": 375,
      "height": 812
    }
  ],
  "task": "ui-review",
  "context": "审查首页 UI 布局一致性和对齐问题"
}
```

3. **切换到 Claude Code** → Claude 读取 JSON 和截图文件 → 视觉分析 → 输出报告。

> **推荐做法：** Codex 本身拥有视觉能力（GPT-5.5 默认支持图片读取），截图后 Codex 可以直接读取 PNG 并分析，无需跨 Agent 切换。Claude Code 互通仅在用户明确指定使用 Claude 做视觉分析时使用。

## 参考文档

按需打开：

- `references/cli-reference.md` — 完整的 CLI 和 HTTP API 命令参数参考
- `references/automator-reference.md` — miniprogram-automator SDK 截图 API 详细说明

## 注意事项

- **截图仅限模拟器** — `miniprogram-automator` 的 `screenshot()` 只能在模拟器中截图，无法在真机上执行
- **真机预览需要扫码** — `preview` 命令生成的二维码需要用微信扫码才能在真机上预览
- **服务端口必须手动开启** — 首次使用需在微信开发者工具 设置→安全设置 中开启
- **登录态** — 预览和上传功能需要微信开发者工具已登录
- **端口区分** — HTTP 服务端口（CLI 操作）和 Automator 端口（截图）是两个不同的端口
- **截图等待时间** — 不同页面的渲染时间不同，复杂页面可能需要更大 `--wait` 值
- **Windows 路径空格** — 所有路径参数必须用引号包裹
