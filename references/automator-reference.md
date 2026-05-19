# miniprogram-automator SDK / 截图 API 参考

## 概述

`miniprogram-automator` 是微信官方提供的小程序自动化测试 SDK，通过 WebSocket 连接到微信开发者工具的 Automator 端口进行操作和截图。

- npm 包: `miniprogram-automator`
- 最低工具版本: 1.02.1906042
- 截图最低版本: `automator >= 0.9.0` + `基础库 >= 2.9.5` + `DevTools >= 1.02.2001082`

## 安装

```bash
# 全局安装
npm install -g miniprogram-automator

# 或通过 npx (无需安装)
npx -y miniprogram-automator
```

## 前提条件

1. 微信开发者工具已启动并打开项目
2. Automator 端口已开启：`cli auto --project <path> --auto-port 9420` 或通过 HTTP API: `GET /v2/auto?project=<path>&auto-port=9420`
3. 默认 Automator 端口: 9420

## 启动连接

```javascript
const automator = require('miniprogram-automator');

const miniProgram = await automator.launch({
  projectPath: '/path/to/miniprogram/project',
  cliPath: '/path/to/cli.bat',  // Windows
  // cliPath: '/Applications/wechatwebdevtools.app/Contents/MacOS/cli',  // macOS
  autoPort: 9420,
});
```

## MiniProgram 类 API

### 页面导航

```javascript
// 保留当前页面跳转
await miniProgram.navigateTo('/pages/detail/detail');

// 关闭当前页面跳转
await miniProgram.redirectTo('/pages/login/login');

// 返回上一页
await miniProgram.navigateBack();

// 重启到指定页面
await miniProgram.reLaunch('/pages/index/index');

// 切换到 tabBar 页
await miniProgram.switchTab('/pages/logs/logs');

// 获取当前页面对象
const page = await miniProgram.currentPage();

// 获取页面栈
const stack = await miniProgram.pageStack();
```

### 截图 (核心功能)

```javascript
// 返回 base64 数据
const base64 = await miniProgram.screenshot();

// 保存到文件
await miniProgram.screenshot({ path: './screenshot.png' });
```

**重要限制：**
- **只能在模拟器中截图**，不能在真机上执行
- 无法对 `<web-view>` 内部进行截图
- 截图是模拟完整页面的内容（含超出屏幕部分）

### 其他

```javascript
// 获取系统信息
const sysInfo = await miniProgram.systemInfo();

// 调用 wx 方法
await miniProgram.callWxMethod('showToast', { title: 'hello' });

// Mock wx 方法
await miniProgram.mockWxMethod('getSystemInfo', { platform: 'ios' });
await miniProgram.restoreWxMethod('getSystemInfo');

// 注入代码到 AppService
const title = await miniProgram.evaluate(() => document.title);

// 页面滚动
await miniProgram.pageScrollTo(100);

// 暴露全局函数
await miniProgram.exposeFunction('myFn', () => 'hello');

// 多账号调试
const accounts = await miniProgram.testAccounts();

// 体验评分
const report = await miniProgram.stopAudits({ path: './audit-report.md' });

// 真机调试
await miniProgram.remote(true);  // 开启
await miniProgram.remote(false); // 关闭

// 登录票据管理
const ticket = await miniProgram.getTicket();
await miniProgram.setTicket(ticket);
await miniProgram.refreshTicket();

// 断开 / 关闭
await miniProgram.disconnect();
await miniProgram.close();
```

## Page 类 API

```javascript
const page = await miniProgram.currentPage();

// 元素查询
const el = await page.$('.container');
const els = await page.$$('.item');

// 等待条件
await page.waitFor(2000);           // 毫秒
await page.waitFor('.loaded');       // 选择器
await page.waitFor(() => window.ready === true);  // 函数

// 页面数据
const data = await page.data();
await page.setData({ key: 'value' });

// 页面尺寸
const size = await page.size();

// 滚动位置
const scrollTop = await page.scrollTop();

// 调用页面方法
await page.callMethod('onLoad');

// 截图 (通过 MiniProgram 实例)
await miniProgram.screenshot({ path: './page.png' });
```

## Element 类 API

```javascript
const el = await page.$('.btn');

// 子元素
const child = await el.$('.title');
const children = await el.$$('.item');

// 交互
await el.tap();
await el.longpress();
await el.input('text value');
await el.trigger('tap', { x: 10, y: 20 });

// 触摸事件
await el.touchstart({ touches: [{ x: 10, y: 10 }] });
await el.touchmove({ touches: [{ x: 20, y: 20 }] });
await el.touchend({ touches: [] });

// 内容获取
const text = await el.text();
const attr = await el.attribute('class');
const prop = await el.property('value');
const val = await el.value();
const style = await el.style('color');
const wxml = await el.wxml();

// 位置尺寸
const size = await el.size();
const offset = await el.offset();

// 自定义组件专属
const compData = await el.data();
await el.setData({ prop: 'value' });
await el.callMethod('refresh');

// 组件专属滚动/滑动
await el.scrollTo(100);
await el.swipeTo(200);
await el.moveTo(0, 100);
await el.slideTo(1);
```

## 截图工作流最佳实践

```javascript
const automator = require('miniprogram-automator');

(async () => {
  const miniProgram = await automator.launch({
    projectPath: process.argv[2],
    cliPath: process.argv[3],
    autoPort: parseInt(process.argv[4]),
  });

  try {
    // 1. 重启到目标页面（确保干净的状态）
    await miniProgram.reLaunch(process.argv[5] || '/pages/index/index');

    // 2. 等待页面渲染完成
    await miniProgram.waitFor(2500);

    // 3. 验证页面加载
    const page = await miniProgram.currentPage();
    await page.waitFor(500);

    // 4. 截图
    await miniProgram.screenshot({ path: process.argv[6] });
  } finally {
    await miniProgram.close();
  }
})();
```

## 常见问题和故障排查

### 连接失败
- 确认 Automator 端口已开启：检查 `cli auto` 是否成功执行
- 检查端口号：默认 9420，可通过 `--auto-port` 自定义
- 检查防火墙：确保端口未被阻止

### 截图空白/白屏
- 增加等待时间：`waitFor` 的值不够大，复杂页面需要更长渲染时间
- 确认页面路径在 `app.json` 的 `pages` 数组中注册
- 检查页面是否有编译错误

### 找不到 miniprogram-automator
```bash
# 通过 npx 自动安装
npx -y miniprogram-automator --help

# 或全局安装
npm install -g miniprogram-automator

# 验证
node -e "require('miniprogram-automator'); console.log('OK');"
```

### 基础库版本过低
- 截图功能要求基础库 >= 2.9.5
- 在 project.config.json 中设置 `"libVersion": "2.9.5"` 或更高

### 工具版本过低
- 截图要求 DevTools >= 1.02.2001082
- 建议升级到最新版本

### Windows 路径问题
- `.bat` 文件路径中的空格需要正确处理
- 使用 `cliPath` 参数明确指定 `cli.bat` 的完整路径
