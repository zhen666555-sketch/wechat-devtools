#Requires -Version 5.1
<#
.SYNOPSIS
    微信开发者工具 Codex Skill 主控脚本
.DESCRIPTION
    提供 11 个子命令控制和自动化微信开发者工具。
    所有子命令输出 JSON 格式，方便 Codex 解析。

    子命令:
      detect         检测环境
      open           打开小程序项目
      close          关闭项目
      preview        生成真机预览二维码
      autopreview    自动预览
      build-npm      构建 npm 依赖
      clear-cache    清除缓存
      start-auto     开启自动化端口
      screenshot     单页面截图
      screenshot-all 批量全页面截图
      status         综合状态查询

.EXAMPLE
    .\wxtools.ps1 detect
    .\wxtools.ps1 open --project "E:\miniapp"
    .\wxtools.ps1 preview --project "E:\miniapp" --qr-format image --qr-output ".\qr.png"
    .\wxtools.ps1 screenshot --project "E:\miniapp" --page "/pages/index/index" --output ".\shot.png"
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet("detect", "open", "close", "preview", "autopreview", "build-npm",
                 "clear-cache", "start-auto", "screenshot", "screenshot-all", "status")]
    [string]$Command,

    [string]$Project,               # 项目根目录路径
    [string]$QrFormat = "terminal", # terminal | image | base64
    [string]$QrOutput,              # 二维码输出路径 (QrFormat=image 时使用)
    [string]$CompileCondition,      # 编译条件 JSON
    [string]$Version,               # 上传版本号
    [string]$Desc,                  # 上传描述
    [string]$CacheType = "all",     # 缓存类型: compile|file|storage|session|auth|network|all
    [int]$AutoPort = 9420,          # Automator WebSocket 端口
    [string]$Page,                  # 目标页面路径 (如 /pages/index/index)
    [string]$Output,                # 截图输出路径
    [string]$OutputDir,             # 批量截图输出目录
    [int]$Wait = 2500,              # 页面渲染等待时间 ms
    [string]$CliPath,               # 手动指定 cli.bat 路径
    [int]$Port,                     # 手动指定 HTTP 端口
    [switch]$PureSimulator,         # 仅打开模拟器
    [switch]$NoSimulator,           # 不打开模拟器
    [string]$InfoOutput,            # 预览/上传附加信息输出路径
    [switch]$Help                   # 显示帮助
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$scriptDir = $PSScriptRoot
$findDevtoolsScript = Join-Path $scriptDir "find_devtools.ps1"
$screenshotScript = Join-Path $scriptDir "screenshot_automator.js"

# ============================================================
# 工具函数
# ============================================================

function Write-JsonResult {
    param($Result)
    $Result | ConvertTo-Json -Depth 5
}

function Write-ErrorResult {
    param(
        [string]$ErrorCode,
        [string]$ErrorMessage,
        [string[]]$Hints = @()
    )
    $result = @{
        success       = $false
        errorCode     = $ErrorCode
        errorMessage  = $ErrorMessage
        hints         = $Hints
    }
    Write-JsonResult $result
    exit 1
}

function Invoke-CliCommand {
    param(
        [string]$Arguments,
        [int]$TimeoutSeconds = 60
    )

    $env = Get-DevToolsEnv
    if (-not $env.found) {
        throw "DevTools 环境未就绪: $($env.errors -join '; ')"
    }

    $cli = $env.cliPath
    $fullArgs = "$Arguments"
    if ($env.httpPort -and $Arguments -notmatch '--port') {
        $fullArgs += " --port $($env.httpPort)"
    }

    try {
        $proc = Start-Process -FilePath $cli -ArgumentList $fullArgs `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\wxtools-stdout.txt" `
            -RedirectStandardError "$env:TEMP\wxtools-stderr.txt"

        $stdout = Get-Content "$env:TEMP\wxtools-stdout.txt" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$env:TEMP\wxtools-stderr.txt" -Raw -ErrorAction SilentlyContinue

        Remove-Item "$env:TEMP\wxtools-stdout.txt", "$env:TEMP\wxtools-stderr.txt" `
            -ErrorAction SilentlyContinue

        return @{
            exitCode = $proc.ExitCode
            stdout   = $stdout
            stderr   = $stderr
        }
    } catch {
        throw "执行 CLI 命令失败: $($_.Exception.Message)"
    }
}

function Get-DevToolsEnv {
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $findDevtoolsScript `
        @(if ($CliPath) { @('-CliPath', $CliPath) } else {} ) `
        @(if ($Port) { @('-Port', $Port) } else {} ) `
        @(if ($AutoPort) { @('-AutoPort', $AutoPort) } else {} )
    return $result | ConvertFrom-Json
}

function Test-NodeAvailable {
    try {
        $null = Get-Command node -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-NpxAvailable {
    try {
        $null = Get-Command npx -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-ProjectValid {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path $Path)) { return $false }
    return Test-Path (Join-Path $Path "project.config.json")
}

# ============================================================
# 子命令: detect
# ============================================================
function Invoke-Detect {
    $env = Get-DevToolsEnv
    Write-JsonResult $env
}

# ============================================================
# 子命令: open
# ============================================================
function Invoke-Open {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project" `
            -Hints @("请确认路径正确且包含 project.config.json 文件")
    }

    $args = "open --project `"$Project`""
    if ($PureSimulator) { $args += " --pure-simulator" }
    if ($NoSimulator) { $args += " --no-simulator" }

    try {
        $result = Invoke-CliCommand -Arguments $args
        if ($result.exitCode -eq 0) {
            Write-JsonResult @{ success = $true; action = "open"; project = $Project }
        } else {
            Write-ErrorResult "ERR_CLI_FAILED" "打开项目失败: $($result.stderr)" `
                -Hints @("请检查微信开发者工具是否正在运行", "确认项目路径正确且 project.config.json 有效")
        }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: close
# ============================================================
function Invoke-Close {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    try {
        $result = Invoke-CliCommand -Arguments "close --project `"$Project`""
        Write-JsonResult @{ success = $true; action = "close"; project = $Project }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: preview (真机预览)
# ============================================================
function Invoke-Preview {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    $qrFormat = $QrFormat.ToLower()
    $args = "preview --project `"$Project`" --qr-format $qrFormat"

    if ($InfoOutput) { $args += " --info-output `"$InfoOutput`"" }
    if ($CompileCondition) { $args += " --compile-condition '$CompileCondition'" }

    try {
        $result = Invoke-CliCommand -Arguments $args -TimeoutSeconds 120

        if ($result.exitCode -ne 0) {
            if ($result.stderr -match "未登录|login|not login") {
                Write-ErrorResult "ERR_NOT_LOGIN" "未登录微信开发者工具" `
                    -Hints @("请在微信开发者工具中扫码登录")
            }
            Write-ErrorResult "ERR_PREVIEW_FAILED" "预览生成失败: $($result.stderr)" `
                -Hints @("请检查编译错误", "确认项目配置正确")
        }

        $output = @{ success = $true; action = "preview"; format = $qrFormat }

        if ($qrFormat -eq "base64") {
            # 从输出中提取 base64 数据
            $output.base64 = $result.stdout.Trim()
        } elseif ($qrFormat -eq "image" -and $QrOutput) {
            # base64 → PNG 文件
            $base64Data = $result.stdout.Trim()
            if ($base64Data -match 'base64,') {
                $base64Data = $base64Data -replace '.*base64,', ''
            }
            try {
                $bytes = [Convert]::FromBase64String($base64Data)
                $qrDir = Split-Path $QrOutput -Parent
                if ($qrDir -and -not (Test-Path $qrDir)) {
                    New-Item -ItemType Directory -Path $qrDir -Force | Out-Null
                }
                [System.IO.File]::WriteAllBytes($QrOutput, $bytes)
                $output.qrPath = $QrOutput
            } catch {
                Write-ErrorResult "ERR_QR_CONVERT" "二维码 base64 转图片失败: $($_.Exception.Message)"
            }
        } else {
            $output.qrText = $result.stdout.Trim()
        }

        Write-JsonResult $output
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: autopreview
# ============================================================
function Invoke-AutoPreview {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    $args = "auto-preview --project `"$Project`""
    if ($InfoOutput) { $args += " --info-output `"$InfoOutput`"" }

    try {
        $result = Invoke-CliCommand -Arguments $args -TimeoutSeconds 120
        if ($result.exitCode -eq 0) {
            Write-JsonResult @{ success = $true; action = "autopreview"; project = $Project }
        } else {
            Write-ErrorResult "ERR_AUTOPREVIEW_FAILED" "自动预览失败: $($result.stderr)"
        }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: build-npm
# ============================================================
function Invoke-BuildNpm {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    try {
        $result = Invoke-CliCommand -Arguments "build-npm --project `"$Project`"" -TimeoutSeconds 120
        if ($result.exitCode -eq 0) {
            Write-JsonResult @{ success = $true; action = "build-npm"; project = $Project }
        } else {
            Write-ErrorResult "ERR_BUILD_NPM_FAILED" "npm 构建失败: $($result.stderr)"
        }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: clear-cache
# ============================================================
function Invoke-ClearCache {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    $validTypes = @("compile", "file", "storage", "session", "auth", "network", "all")
    if ($CacheType -notin $validTypes) {
        Write-ErrorResult "ERR_INVALID_CACHE" "无效的缓存类型: $CacheType" `
            -Hints @("有效值: $($validTypes -join ', ')")
    }

    try {
        $result = Invoke-CliCommand "cache --clean --cache-type $CacheType --project `"$Project`"" `
            -TimeoutSeconds 60
        if ($result.exitCode -eq 0) {
            Write-JsonResult @{ success = $true; action = "clear-cache"; project = $Project; cacheType = $CacheType }
        } else {
            Write-ErrorResult "ERR_CLEAR_CACHE_FAILED" "清除缓存失败: $($result.stderr)"
        }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: start-auto
# ============================================================
function Invoke-StartAuto {
    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    $env = Get-DevToolsEnv
    if (-not $env.found) {
        Write-ErrorResult "ERR_DEVENV" "DevTools 环境未就绪: $($env.errors -join '; ')"
    }

    # 检查 auto 端口是否已开启
    try {
        $testConn = Test-NetConnection -ComputerName 127.0.0.1 -Port $AutoPort `
            -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($testConn) {
            Write-JsonResult @{ success = $true; action = "start-auto"; autoPort = $AutoPort; alreadyStarted = $true }
            return
        }
    } catch { }

    # 开启 auto 端口
    try {
        $result = Invoke-CliCommand "auto --project `"$Project`" --auto-port $AutoPort" -TimeoutSeconds 30
        if ($result.exitCode -eq 0) {
            # 等待端口就绪
            $retries = 0
            $maxRetries = 10
            while ($retries -lt $maxRetries) {
                Start-Sleep -Milliseconds 500
                try {
                    $testConn = Test-NetConnection -ComputerName 127.0.0.1 -Port $AutoPort `
                        -InformationLevel Quiet -WarningAction SilentlyContinue
                    if ($testConn) {
                        Write-JsonResult @{ success = $true; action = "start-auto"; autoPort = $AutoPort; retries = $retries + 1 }
                        return
                    }
                } catch { }
                $retries++
            }
            Write-ErrorResult "ERR_AUTO_PORT_TIMEOUT" "Automator 端口 $AutoPort 在 $maxRetries 次重试后仍未就绪" `
                -Hints @("请检查微信开发者工具是否正常运行", "尝试重新调用 start-auto")
        } else {
            Write-ErrorResult "ERR_START_AUTO_FAILED" "开启 Automator 失败: $($result.stderr)" `
                -Hints @("确认项目编译成功", "检查 auto-port 未被占用")
        }
    } catch {
        Write-ErrorResult "ERR_CLI_EXECUTION" "CLI 执行异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: screenshot
# ============================================================
function Invoke-Screenshot {
    if (-not $Project -or -not $Page -or -not $Output) {
        Write-ErrorResult "ERR_USAGE" "缺少必需参数" `
            -Hints @("用法: wxtools.ps1 screenshot --project <path> --page <page> --output <path>")
    }

    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    if (-not (Test-NodeAvailable)) {
        Write-ErrorResult "ERR_NO_NODE" "未检测到 Node.js，截图功能需要 Node.js" `
            -Hints @("请从 https://nodejs.org/ 下载安装 Node.js")
    }

    # 检测环境
    $env = Get-DevToolsEnv
    if (-not $env.found) {
        Write-ErrorResult "ERR_DEVENV" "DevTools 环境未就绪: $($env.errors -join '; ')"
    }

    # 确定 cli 路径
    $cliPath = if ($CliPath) { $CliPath } else { $env.cliPath }
    $autoPort = if ($Port) { $Port } else { $env.autoPort }

    # 确保 auto 端口开启
    [Console]::Error.WriteLine("[wxtools] checking automator port $autoPort...")
    try {
        $testConn = Test-NetConnection -ComputerName 127.0.0.1 -Port $autoPort `
            -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $testConn) {
            [Console]::Error.WriteLine("[wxtools] starting automator...")
            Invoke-CliCommand "auto --project `"$Project`" --auto-port $autoPort" -TimeoutSeconds 30 | Out-Null
            Start-Sleep -Seconds 2
        }
    } catch { }

    # 执行截图
    [Console]::Error.WriteLine("[wxtools] taking screenshot of $Page...")
    try {
        $nodeArgs = @(
            $screenshotScript,
            $Project,
            $cliPath,
            $autoPort,
            $Page,
            $Output,
            $Wait
        )

        $proc = Start-Process -FilePath "node" -ArgumentList $nodeArgs `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\wxtools-screenshot-stdout.txt" `
            -RedirectStandardError "$env:TEMP\wxtools-screenshot-stderr.txt"

        $stdout = Get-Content "$env:TEMP\wxtools-screenshot-stdout.txt" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$env:TEMP\wxtools-screenshot-stderr.txt" -Raw -ErrorAction SilentlyContinue

        Remove-Item "$env:TEMP\wxtools-screenshot-stdout.txt", "$env:TEMP\wxtools-screenshot-stderr.txt" `
            -ErrorAction SilentlyContinue

        if ($proc.ExitCode -eq 0 -and (Test-Path $Output)) {
            $imgInfo = Get-Item $Output
            Write-JsonResult @{
                success  = $true
                action   = "screenshot"
                page     = $Page
                output   = $Output
                fileSize = $imgInfo.Length
            }
        } else {
            Write-ErrorResult "ERR_SCREENSHOT_FAILED" "截图失败" `
                -Hints @(
                    "错误输出: $stderr",
                    "请确认 miniprogram-automator 已安装: npm install -g miniprogram-automator",
                    "确认 automator 端口 $autoPort 已开启",
                    "检查页面路径 '$Page' 是否在 app.json 中注册"
                )
        }
    } catch {
        Write-ErrorResult "ERR_SCREENSHOT_FAILED" "截图异常: $($_.Exception.Message)"
    }
}

# ============================================================
# 子命令: screenshot-all
# ============================================================
function Invoke-ScreenshotAll {
    if (-not $Project -or -not $OutputDir) {
        Write-ErrorResult "ERR_USAGE" "缺少必需参数" `
            -Hints @("用法: wxtools.ps1 screenshot-all --project <path> --output-dir <path>")
    }

    if (-not (Test-ProjectValid $Project)) {
        Write-ErrorResult "ERR_INVALID_PROJECT" "项目路径无效: $Project"
    }

    # 读取 app.json 获取页面列表
    $appJsonPath = Join-Path $Project "app.json"
    if (-not (Test-Path $appJsonPath)) {
        Write-ErrorResult "ERR_NO_APPJSON" "项目根目录缺少 app.json"
    }

    try {
        $appJson = Get-Content $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $pages = @($appJson.pages)

        if ($pages.Count -eq 0) {
            Write-ErrorResult "ERR_NO_PAGES" "app.json 中未定义任何页面"
        }
    } catch {
        Write-ErrorResult "ERR_INVALID_APPJSON" "app.json 解析失败: $($_.Exception.Message)"
    }

    # 确保输出目录存在
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # 预处理: 确保 auto 端口开启
    $env = Get-DevToolsEnv
    $autoPort = if ($Port) { $Port } else { $env.autoPort }
    $cliPath = if ($CliPath) { $CliPath } else { $env.cliPath }

    try {
        $testConn = Test-NetConnection -ComputerName 127.0.0.1 -Port $autoPort `
            -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $testConn) {
            Invoke-CliCommand "auto --project `"$Project`" --auto-port $autoPort" -TimeoutSeconds 30 | Out-Null
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-ErrorResult "ERR_START_AUTO_FAILED" "无法开启 Automator: $($_.Exception.Message)"
    }

    # 遍历截图
    $results = @()
    $succeeded = 0
    $failed = 0
    $errors = @()

    foreach ($pagePath in $pages) {
        $pageName = ($pagePath -replace '[\\/]', '-').TrimStart('-')
        $outputPath = Join-Path $OutputDir "${pageName}.png"

        [Console]::Error.WriteLine("[wxtools] screenshot $pagePath -> $outputPath")

        $nodeArgs = @(
            $screenshotScript,
            $Project,
            $cliPath,
            $autoPort,
            $pagePath,
            $outputPath,
            $Wait
        )

        try {
            $proc = Start-Process -FilePath "node" -ArgumentList $nodeArgs `
                -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\wxtools-ss-stdout.txt" `
                -RedirectStandardError "$env:TEMP\wxtools-ss-stderr.txt"

            $stderr = Get-Content "$env:TEMP\wxtools-ss-stderr.txt" -Raw -ErrorAction SilentlyContinue

            Remove-Item "$env:TEMP\wxtools-ss-stdout.txt", "$env:TEMP\wxtools-ss-stderr.txt" `
                -ErrorAction SilentlyContinue

            if ($proc.ExitCode -eq 0 -and (Test-Path $outputPath)) {
                $results += @{ page = $pagePath; path = $outputPath; success = $true }
                $succeeded++
            } else {
                $results += @{ page = $pagePath; path = $null; success = $false; error = $stderr.Trim() }
                $failed++
                $errors += "$pagePath : $stderr"
            }
        } catch {
            $results += @{ page = $pagePath; path = $null; success = $false; error = $_.Exception.Message }
            $failed++
            $errors += "$pagePath : $($_.Exception.Message)"
        }

        # 截图间隔
        Start-Sleep -Milliseconds 500
    }

    Write-JsonResult @{
        success     = ($failed -eq 0)
        action      = "screenshot-all"
        total       = $pages.Count
        succeeded   = $succeeded
        failed      = $failed
        screenshots = $results
        errors      = $errors
    }
}

# ============================================================
# 子命令: status
# ============================================================
function Invoke-Status {
    $env = Get-DevToolsEnv

    $status = @{
        success          = $env.found
        cliPath          = $env.cliPath
        installPath      = $env.installPath
        httpPort         = $env.httpPort
        autoPort         = $env.autoPort
        devtoolsRunning  = $env.devtoolsRunning
        servicePortReady = $env.servicePortEnabled
        nodeAvailable    = Test-NodeAvailable
        npxAvailable     = Test-NpxAvailable
        errors           = $env.errors
    }

    # 尝试获取当前打开的项目 (通过 HTTP API)
    if ($env.servicePortEnabled -and $env.httpPort) {
        try {
            $openResp = Invoke-RestMethod -Uri "http://127.0.0.1:$($env.httpPort)/v2/open" `
                -Method GET -TimeoutSec 5 -ErrorAction Stop
            $status.openedProjects = $openResp
        } catch { }
    }

    Write-JsonResult $status
}

# ============================================================
# 帮助
# ============================================================
function Show-Help {
    @"
微信开发者工具 Codex Skill 主控脚本 (wxtools.ps1)

子命令:
  detect         检测微信开发者工具环境
  open           打开小程序项目
  close          关闭项目
  preview        生成真机预览二维码
  autopreview    自动预览 (免扫码，需白名单配置)
  build-npm      构建 npm 依赖
  clear-cache    清除编译/文件缓存
  start-auto     开启 Automator WebSocket 端口
  screenshot     截取单个页面截图
  screenshot-all 遍历 app.json pages 批量截图
  status         查询综合状态

示例:
  .\wxtools.ps1 detect
  .\wxtools.ps1 open --project "E:\miniapp"
  .\wxtools.ps1 preview --project "E:\miniapp" --qr-format terminal
  .\wxtools.ps1 preview --project "E:\miniapp" --qr-format image --qr-output ".\qr.png"
  .\wxtools.ps1 screenshot --project "E:\miniapp" --page "/pages/index/index" --output ".\shot.png"
  .\wxtools.ps1 screenshot-all --project "E:\miniapp" --output-dir ".\screenshots\"
  .\wxtools.ps1 clear-cache --project "E:\miniapp" --cache-type compile
"@
}

# ============================================================
# 入口
# ============================================================
if ($Help -or (-not $Command)) {
    Show-Help
    exit 0
}

switch ($Command) {
    "detect"         { Invoke-Detect }
    "open"           { Invoke-Open }
    "close"          { Invoke-Close }
    "preview"        { Invoke-Preview }
    "autopreview"    { Invoke-AutoPreview }
    "build-npm"      { Invoke-BuildNpm }
    "clear-cache"    { Invoke-ClearCache }
    "start-auto"     { Invoke-StartAuto }
    "screenshot"     { Invoke-Screenshot }
    "screenshot-all" { Invoke-ScreenshotAll }
    "status"         { Invoke-Status }
    default          { Show-Help }
}
