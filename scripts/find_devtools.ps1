#Requires -Version 5.1
<#
.SYNOPSIS
    检测微信开发者工具安装位置、HTTP 端口和运行状态
.DESCRIPTION
    多层 fallback 检测微信开发者工具的安装路径和运行端口。
    输出 JSON 格式结果，方便 Codex 自动化解析。
.OUTPUTS
    JSON
#>
param(
    [string]$CliPath,       # 手动指定 cli.bat 路径，跳过自动检测
    [int]$Port,             # 手动指定 HTTP 端口
    [int]$AutoPort          # 手动指定自动化端口
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$result = @{
    found               = $false
    cliPath             = $null
    cliExists           = $false
    installPath         = $null
    httpPort            = $null
    autoPort            = $null
    devtoolsRunning     = $false
    servicePortEnabled  = $false
    errors              = @()
}

# ============================================================
# 步骤 1: 定位 cli.bat
# ============================================================
function Find-CliBat {
    if ($CliPath -and (Test-Path $CliPath)) {
        return $CliPath
    }

    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Tencent\微信web开发者工具\cli.bat",
        "$env:ProgramFiles\Tencent\微信web开发者工具\cli.bat",
        "${env:LocalAppData}\Programs\微信开发者工具\cli.bat",
        "D:\Tencent\微信web开发者工具\cli.bat",
        "E:\Tencent\微信web开发者工具\cli.bat"
    )

    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }

    # 注册表搜索 (HKCU)
    try {
        $regPath = "HKCU:\Software\Tencent\微信开发者工具"
        if (Test-Path $regPath) {
            $installDir = (Get-ItemProperty $regPath -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
            if ($installDir) {
                $cli = Join-Path $installDir "cli.bat"
                if (Test-Path $cli) { return $cli }
            }
        }
    } catch { }

    # 注册表搜索 (HKLM)
    try {
        $regPath = "HKLM:\SOFTWARE\Tencent\微信开发者工具"
        if (Test-Path $regPath) {
            $installDir = (Get-ItemProperty $regPath -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
            if ($installDir) {
                $cli = Join-Path $installDir "cli.bat"
                if (Test-Path $cli) { return $cli }
            }
        }
    } catch { }

    # 通过进程路径探测
    $proc = Get-Process -Name "微信开发者工具" -ErrorAction SilentlyContinue
    if (-not $proc) {
        $proc = Get-Process -Name "wechatdevtools" -ErrorAction SilentlyContinue
    }
    if ($proc) {
        $procPath = $proc[0].Path
        if ($procPath) {
            $installDir = Split-Path $procPath -Parent
            $cli = Join-Path $installDir "cli.bat"
            if (Test-Path $cli) { return $cli }
            $cli = Join-Path (Split-Path $installDir -Parent) "cli.bat"
            if (Test-Path $cli) { return $cli }
        }
    }

    return $null
}

# ============================================================
# 步骤 2: 检测 DevTools 进程是否运行
# ============================================================
function Test-DevToolsRunning {
    $proc = Get-Process -Name "微信开发者工具" -ErrorAction SilentlyContinue
    if (-not $proc) {
        $proc = Get-Process -Name "wechatdevtools" -ErrorAction SilentlyContinue
    }
    return [bool]$proc
}

# ============================================================
# 步骤 3: 读取 .ide 文件获取端口号
# ============================================================
function Get-DevToolsPorts {
    param([string]$InstallPath)

    if (-not $InstallPath) { return @{ httpPort = $null; autoPort = $null } }

    # .ide 文件可能在多个位置
    $userDataPaths = @()

    # 标准 User Data 目录
    if (Test-Path "${env:LocalAppData}\微信开发者工具\User Data") {
        $userDataPaths += "${env:LocalAppData}\微信开发者工具\User Data"
    }

    # 安装在非标准位置的情况
    if ($InstallPath) {
        $udPath = Join-Path $InstallPath "User Data"
        if (Test-Path $udPath) { $userDataPaths += $udPath }
    }

    $ports = @{ httpPort = $null; autoPort = $null }

    foreach ($udBase in $userDataPaths) {
        # 遍历所有子目录，查找 .ide 文件
        $ideFiles = Get-ChildItem -Path $udBase -Recurse -Filter ".ide" -Depth 3 -ErrorAction SilentlyContinue
        foreach ($f in $ideFiles) {
            try {
                $content = Get-Content $f.FullName -Raw -Encoding UTF8
                # .ide 文件格式示例: {"port":27462,"autoPort":9420,...}
                if ($content -match '"port"\s*:\s*(\d+)') {
                    $ports.httpPort = [int]$Matches[1]
                }
                if ($content -match '"autoPort"\s*:\s*(\d+)') {
                    $ports.autoPort = [int]$Matches[1]
                }
                if ($ports.httpPort) { break }
            } catch { }
        }
        if ($ports.httpPort) { break }
    }

    return $ports
}

# ============================================================
# 步骤 4: 验证 HTTP 端口是否可达
# ============================================================
function Test-HttpPortReachable {
    param([int]$Port)

    if (-not $Port) { return $false }

    try {
        $req = Invoke-WebRequest -Uri "http://127.0.0.1:${Port}/v2/islogin" `
            -Method GET -TimeoutSec 3 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ============================================================
# 主逻辑
# ============================================================

# 1. 定位 cli.bat
$cliPath = Find-CliBat

if (-not $cliPath) {
    $result.errors += "未检测到微信开发者工具安装。请从 https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html 下载安装。"
    $result | ConvertTo-Json -Depth 3
    exit 1
}

$result.cliPath = $cliPath
$result.cliExists = $true
$result.installPath = Split-Path $cliPath -Parent

# 2. 检测进程
$result.devtoolsRunning = Test-DevToolsRunning

if (-not $result.devtoolsRunning) {
    $result.errors += "微信开发者工具当前未运行。请手动启动微信开发者工具。"
    $result | ConvertTo-Json -Depth 3
    exit 0
}

# 3. 获取端口
$ports = Get-DevToolsPorts -InstallPath $result.installPath

if ($Port) {
    $result.httpPort = $Port
} elseif ($ports.httpPort) {
    $result.httpPort = $ports.httpPort
}

if ($AutoPort) {
    $result.autoPort = $AutoPort
} elseif ($ports.autoPort) {
    $result.autoPort = $ports.autoPort
} else {
    $result.autoPort = 9420  # 默认端口
}

# 4. 验证端口
if ($result.httpPort) {
    $result.servicePortEnabled = Test-HttpPortReachable -Port $result.httpPort
    if (-not $result.servicePortEnabled) {
        $result.errors += "服务端口 ${httpPort} 不可达。请在微信开发者工具 设置 -> 安全设置 中开启'服务端口'。"
    }
} else {
    $result.errors += "无法获取 HTTP 服务端口号。请在微信开发者工具 设置 -> 安全设置 中开启'服务端口'，并确保工具正在运行。"
}

$result.found = $true
$result | ConvertTo-Json -Depth 3
exit 0
