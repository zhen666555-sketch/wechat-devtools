# 微信开发者工具 CLI & HTTP API 命令参考

## CLI 命令 (cli.bat)

### 前置条件
- 微信开发者工具需要在 **设置 → 安全设置** 中开启"服务端口"
- CLI V2 自工具版本 `1.02.202003092` (2020年3月) 引入

### 全局参数

| 参数 | 说明 |
|------|------|
| `--port <port>` | HTTP 服务端口号 |
| `--lang zh/en` | 语言选择 |
| `--debug` | 输出调试信息 |
| `--project <path>` | 小程序项目根路径（含 project.config.json） |
| `--appid <id>` | 小程序 AppID |
| `--ext-appid <id>` | 第三方平台开发者的 AppID |

### 项目管理

```bash
# 打开项目
cli open --project "path/to/project"

# 仅打开模拟器
cli open --project "path/to/project" --pure-simulator

# 关闭项目窗口
cli close --project "path/to/project"

# 退出开发者工具
cli quit

# 重置文件监听
cli reset-fileutils --project "path/to/project"
```

### 预览和上传

```bash
# 生成预览二维码 (终端 ASCII 输出)
cli preview --project "path/to/project"

# 生成 base64 编码的二维码
cli preview --project "path/to/project" --qr-format base64

# 生成二维码图片
cli preview --project "path/to/project" --qr-format image --qr-output ./qr.png

# 生成二维码并输出附加信息 (代码包大小等)
cli preview --project "path/to/project" --info-output ./info.json

# 指定编译条件 (打开特定页面+参数)
cli preview --project "path/to/project" --compile-condition '{"pathName":"pages/index/index","query":"x=1&y=2"}'

# 自动预览 (免扫码, 需白名单配置)
cli auto-preview --project "path/to/project" --info-output ./info.json

# 上传代码 (version 必填)
cli upload --project "path/to/project" --version "1.0.0" --desc "版本描述" --info-output ./info.json
```

### 构建和缓存

```bash
# 构建 npm 依赖
cli build-npm --project "path/to/project"

# 清除编译缓存
cli cache --clean --cache-type compile --project "path/to/project"

# 清除所有缓存
cli cache --clean --cache-type all --project "path/to/project"

# 清除文件缓存
cli cache --clean --cache-type file --project "path/to/project"

# 清除网络缓存
cli cache --clean --cache-type network --project "path/to/project"
```

### 自动化

```bash
# 开启自动化测试端口 WebSocket
cli auto --project "path/to/project" --auto-port 9420

# 自动化测试回放
cli auto-replay --project "path/to/project"
```

### 登录

```bash
# 检查登录状态
cli islogin

# 扫码登录 (输出 base64 二维码)
cli login --qr-format base64

# 登录 (终端 ASCII 二维码)
cli login --qr-format terminal
```

## HTTP API 接口

### 基础信息

- 基础 URL: `http://127.0.0.1:{端口号}/v2/{endpoint}`
- 端口号: 从 `.ide` 文件读取（位于 `%LocalAppData%\微信开发者工具\User Data\<MD5>\Default\.ide`）
- 方法: 所有接口均为 `GET`
- Content-Type: `application/json`

### 登录

```
GET /v2/login              # 获取登录二维码
GET /v2/islogin            # 检查登录状态 (返回 true/false)
```

### 项目管理

```
GET /v2/open?project=<path>&pure_simulator=true&no_simulator=false
  打开项目，可选参数 pure_simulator (仅模拟器), no_simulator (不启动模拟器)

GET /v2/close?project=<path>
  关闭项目窗口 (有 3 秒确认弹窗)

GET /v2/quit
  退出开发者工具 (有 3 秒确认弹窗)
```

### 预览和上传

```
GET /v2/preview?project=<path>&qr-format=image&qr-output=<path>&compile-condition=<json>
  生成预览二维码

GET /v2/autopreview?project=<path>&info-output=<path>
  自动预览 (免扫码)

GET /v2/upload?project=<path>&version=<ver>&desc=<desc>&info-output=<path>
  上传代码
```

### 构建和缓存

```
GET /v2/buildnpm?project=<path>&compile-type=miniprogram
  构建 npm，compile-type: miniprogram | plugin

GET /v2/cleancache?project=<path>&clean=<type>
  清除缓存，clean 可选值: compile|file|storage|session|auth|network|all

GET /v2/resetfileutils?project=<path>
  重置文件监听
```

### 云开发

```
GET /v2/cloud/env/list?project=<path>
  列出云环境

GET /v2/cloud/functions/list?env=<envId>
  列出云函数

GET /v2/cloud/functions/info?env=<envId>&names=<name1,name2>
  查看云函数详情

GET /v2/cloud/functions/deploy?env=<envId>&names=<names>&paths=<paths>&remote-npm-install=true
  上传云函数

GET /v2/cloud/functions/download?env=<envId>&name=<name>&path=<localPath>
  下载云函数
```

## 端口文件 (.ide)

.ide 文件存储了 HTTP 端口和 Automator 端口信息。

位置：
- Windows: `%LocalAppData%\微信开发者工具\User Data\<安装路径+版本MD5>\Default\.ide`
- macOS: `~/Library/Application Support/微信开发者工具/<MD5>/Default/.ide`

格式：
```json
{"port":27462,"autoPort":9420,"msg":""}
```

每次 DevTools 启动时端口可能变化，建议每次都重新读取。

## 常见问题

1. **HTTP API 返回空或连接拒绝** → 服务端口未开启，去设置→安全设置中开启
2. **preview 命令报未登录** → 先在微信开发者工具中扫码登录
3. **.ide 文件不存在** → DevTools 可能未正常启动，重启工具后再试
4. **端口号过期** → .ide 文件中的端口可能在工具重启后变化，重新读取即可
