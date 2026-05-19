#!/usr/bin/env node
/**
 * 微信小程序模拟器截图工具
 *
 * 通过 miniprogram-automator SDK 连接到微信开发者工具的 WebSocket 端口，
 * 对指定页面进行截图。这是微信开发者工具模拟器截图的唯一可用方式。
 *
 * 用法:
 *   node screenshot_automator.js <projectPath> <cliPath> <autoPort> <page> <outputPath> [waitMs]
 *
 * 参数:
 *   projectPath  - 小程序项目根目录
 *   cliPath      - 微信开发者工具 cli.bat (Windows) 路径
 *   autoPort     - Automator WebSocket 端口 (默认 9420)
 *   page         - 目标页面路径 (如 /pages/index/index)
 *   outputPath   - 截图输出路径 (PNG)
 *   waitMs       - 页面渲染后等待时间 (ms, 默认 2000)
 */

const { spawn } = require("child_process");
const path = require("path");

const args = process.argv.slice(2);

if (args.length < 5) {
  console.error(
    JSON.stringify({
      success: false,
      errorCode: "ERR_USAGE",
      errorMessage:
        "用法: node screenshot_automator.js <projectPath> <cliPath> <autoPort> <page> <outputPath> [waitMs]",
    })
  );
  process.exit(1);
}

const projectPath = args[0];
const cliPath = args[1];
const autoPort = parseInt(args[2], 10);
const page = args[3];
const outputPath = args[4];
const waitMs = parseInt(args[5], 10) || 2000;

/**
 * 通过 npx 调用 miniprogram-automator，因为该 SDK 不支持直接的 programmatic API
 * 在较新版本已废弃。使用子进程方式执行内联脚本。
 */
function runAutomator() {
  return new Promise((resolve, reject) => {
    const scriptContent = `
const automator = require("miniprogram-automator");

(async () => {
  try {
    const miniProgram = await automator.launch({
      projectPath: ${JSON.stringify(projectPath)},
      cliPath: ${JSON.stringify(cliPath)},
      autoPort: ${autoPort},
    });

    try {
      await miniProgram.reLaunch(${JSON.stringify(page)});
      await new Promise(r => setTimeout(r, ${waitMs}));
      await miniProgram.screenshot({ path: ${JSON.stringify(outputPath)} });
      process.stdout.write(JSON.stringify({ success: true, output: ${JSON.stringify(outputPath)} }));
    } finally {
      await miniProgram.close();
    }
  } catch (err) {
    process.stderr.write(JSON.stringify({ success: false, errorCode: "ERR_AUTOMATOR", errorMessage: err.message }));
    process.exit(1);
  }
})();
`.trim();

    // 确保输出目录存在
    const outputDir = path.dirname(outputPath);
    const fs = require("fs");
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    const child = spawn("npx", ["-y", "miniprogram-automator", "-e", scriptContent], {
      stdio: ["pipe", "pipe", "pipe"],
      shell: true,
      cwd: process.cwd(),
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    child.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    child.on("close", (code) => {
      if (code === 0) {
        try {
          // 尝试从 stdout 的第一/最后一行 JSON 提取结果
          const lines = stdout.trim().split("\n");
          const lastLine = lines[lines.length - 1];
          const parsed = JSON.parse(lastLine);
          resolve(parsed);
        } catch (e) {
          resolve({ success: true, output: outputPath });
        }
      } else {
        // 尝试从 stderr 提取错误信息
        try {
          const errMatch = stderr.match(/\{[\s\S]*"errorCode"[\s\S]*\}/);
          if (errMatch) {
            reject(JSON.parse(errMatch[0]));
          } else {
            reject({
              success: false,
              errorCode: "ERR_AUTOMATOR_FAILED",
              errorMessage: stderr.trim() || `miniprogram-automator 退出码: ${code}`,
            });
          }
        } catch (e) {
          reject({
            success: false,
            errorCode: "ERR_AUTOMATOR_FAILED",
            errorMessage: stderr.trim() || `miniprogram-automator 退出码: ${code}`,
          });
        }
      }
    });
  });
}

// 执行并输出结果
runAutomator()
  .then((result) => {
    console.log(JSON.stringify(result));
    process.exit(0);
  })
  .catch((err) => {
    // err 可能是 JSON 字符串或对象
    if (typeof err === "string") {
      try {
        err = JSON.parse(err);
      } catch (_) {}
    }
    if (typeof err === "object" && err.errorCode) {
      console.error(JSON.stringify(err));
    } else {
      console.error(
        JSON.stringify({
          success: false,
          errorCode: "ERR_UNKNOWN",
          errorMessage: err.message || String(err),
        })
      );
    }
    process.exit(1);
  });
