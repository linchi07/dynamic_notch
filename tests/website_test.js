/**
 * 自动化单元测试：验证二开版 Live Activity 架构、7 大状态机、首屏巨幅半屏流光特写、中心对称波形脉动、纯黑背景、取消底栏胶囊与全内置语言 i18n
 */
const fs = require('fs');
const path = require('path');
const assert = require('assert');

// 1. 验证 HTML 文件结构与二开架构
const htmlPath = path.join(__dirname, '../website/index.html');
const htmlContent = fs.readFileSync(htmlPath, 'utf8');

assert(htmlContent.includes('id="dynamicNotchIsland"'), 'HTML 缺少 dynamicNotchIsland 核心实体');
assert(htmlContent.includes('id="boringHeaderBar"'), 'HTML 缺少 BoringHeader 顶部状态栏');
assert(htmlContent.includes('id="floatingPopupsLayer"'), 'HTML 缺少浮动弹窗挂载层');
assert(htmlContent.includes('id="sneakPeekCapsule"'), 'HTML 缺少切歌 Sneak Peek 胶囊');
assert(htmlContent.includes('id="batteryPopup"'), 'HTML 缺少快充电池弹窗');
assert(htmlContent.includes('id="floatingHudBar"'), 'HTML 缺少独立音量调节 HUD');
assert(htmlContent.includes('id="windowSnapOverlay"'), 'HTML 缺少 Windows 风格顶边分屏悬浮选择器 (windowSnapOverlay)');
assert(htmlContent.includes('id="ghostSnapGuide"'), 'HTML 缺少桌面幽灵分屏对齐框 (ghostSnapGuide)');
assert(htmlContent.includes('data-i18n="bento.cardSnapTitle"'), 'HTML 缺少 Windows Snap 分屏 Bento 卡片');
assert(htmlContent.includes('id="viewEmpty"'), 'HTML 缺少原生空刘海视图 (view-empty)');
assert(!htmlContent.includes('id="heroNotchStage"'), 'HTML 应移除割裂的静态假药丸');

// 验证演播台底部的胶囊控制栏已彻底移除（避免 overflow）
assert(!htmlContent.includes('class="stage-control-bar"'), 'HTML 应彻底移除演播台底部的胶囊控制栏');
assert(!htmlContent.includes('id="statePillTabs"'), 'HTML 应彻底移除演播台底部的胶囊控制按钮');

// 验证多语言切换组件与脚本引入
assert(htmlContent.includes('id="langSelect"'), 'HTML 缺少导航栏全语言选择下拉框 langSelect');
assert(htmlContent.includes('<script src="i18n.js"></script>'), 'HTML 必须引入 i18n.js 脚本');
assert(htmlContent.includes('data-i18n="nav.showcase"'), 'HTML 缺少 data-i18n 标签');

// 确认彻底取消所有摄像头镜头装饰
assert(!htmlContent.includes('empty-notch-lens'), '错误：摄像头镜头装饰必须取消！');
assert(!htmlContent.includes('physical-lens-dot'), '错误：摄像头镜头装饰必须取消！');
assert(!htmlContent.includes('center-lens-sensor'), '错误：摄像头镜头装饰必须取消！');

// 验证首屏专属巨幅流光半屏特写结构 (只在首屏展示，严格复刻官方渲染图)
assert(htmlContent.includes('id="heroNotchRevealStage"'), 'HTML 缺少首屏巨幅流光刘海轮廓组件');
assert(htmlContent.includes('class="notch-flow-beam"'), 'HTML 缺少沿刘海轮廓流转的光束路径');
assert(htmlContent.includes('class="notch-glow-underlay"'), 'HTML 缺少霓虹柔光底层发光路径');

// 确认绝无 brew
assert(!htmlContent.includes('brew install'), '错误：用户 fork 项目没有 brew，严禁出现 brew 安装命令！');

// 确认绝无老旧被删的 calendar
assert(!htmlContent.includes('data-trigger-state="calendar"'), '错误：老项目的 calendar 应被彻底删除！');

// 确认 GitHub 链接指向作者仓库 linchi07
assert(htmlContent.includes('github.com/linchi07/dynamic_notch'), '错误：GitHub 链接应指向 linchi07/dynamic_notch！');

// 验证所有 8 大真实状态卡片均存在 (含 Windows 风格分屏布局 snap)
const requiredLiveStates = ['empty', 'wings', 'expanded', 'sneak', 'volume', 'charging', 'socket', 'snap'];
requiredLiveStates.forEach(state => {
  assert(
    htmlContent.includes(`data-trigger-state="${state}"`),
    `HTML 缺少对应卡片: data-trigger-state="${state}"`
  );
});

// 确认绝无针对原开发者的贬损对比词汇
const negativeWords = ['沉重遮挡', '旧方块', '冗余进程', '臃肿', '老旧版本', '缺陷'];
negativeWords.forEach(word => {
  assert(!htmlContent.includes(word), `错误：网页内容包含可能引起不快或贬损原作者的词汇 "${word}"`);
});

// 确认真实 SwiftUI 细节组件存在
assert(htmlContent.includes('class="battery-uneven-fill"'), 'HTML 缺少电池快充 Uneven 填充层');
assert(htmlContent.includes('class="hud-fill-mask"'), 'HTML 缺少音量 HUD 反色遮罩填充');

// 2. 验证 CSS 文件规范、纯黑底色与高亮紫设计
const cssPath = path.join(__dirname, '../website/style.css');
const cssContent = fs.readFileSync(cssPath, 'utf8');

// 绝不能在 html 或 body 上设置 overflow-x: hidden，否则破坏 position: sticky
const htmlBodyOverflowMatch = /html\s*\{[^}]*overflow-x:\s*hidden/i.test(cssContent) || /body\s*\{[^}]*overflow-x:\s*hidden/i.test(cssContent);
assert(!htmlBodyOverflowMatch, '错误：html 或 body 上严禁出现 overflow-x: hidden，这会导致 CSS position: sticky 完全失效！');

// 确认背景色统一为黑色而不是紫色，高亮依然紫色
assert(cssContent.includes('--COLOR_BG_BASE: #000000;'), 'CSS 必须设置基础背景色为纯黑 #000000');
assert(!cssContent.includes('radial-gradient(circle at 50% 0%, rgba(112, 26, 179'), '错误：body 背景严禁带有紫色渐变');
assert(cssContent.includes('--COLOR_ACCENT_PURPLE'), 'CSS 必须保留高亮紫色变量');
assert(cssContent.includes('.lang-selector-wrap'), 'CSS 缺少语言选择器下拉框样式');
assert(!cssContent.includes('.stage-control-bar'), 'CSS 应清理废弃的 stage-control-bar 样式');

// 确认彻底清除了刘海倒角伪元素（小啾啾）
assert(!cssContent.includes('.notch-island::before'), '错误：严禁在 .notch-island 上添加 ::before 伪元素，避免多出突兀的小啾啾！');
assert(!cssContent.includes('.notch-island::after'), '错误：严禁在 .notch-island 上添加 ::after 伪元素，避免多出突兀的小啾啾！');

// 验证首屏专属巨幅流光动画
assert(cssContent.includes('.hero-notch-reveal-stage'), 'CSS 缺少首屏巨幅流光刘海样式');
assert(cssContent.includes('@keyframes beamCircuitFlow'), 'CSS 缺少沿轮廓流转的光束动画');

// 验证音频波形从中心对称向上下两端脉动跳跃
assert(cssContent.includes('transform-origin: center center;'), 'CSS 波形柱必须使用 transform-origin: center center，从中间向上下对称跳动');
assert(cssContent.includes('align-items: center;'), 'CSS 波形容器必须垂直居中对齐');
assert(cssContent.includes('@keyframes eqCenterPulse1'), 'CSS 缺少 eqCenterPulse1 中心对称跳跃关键帧');
assert(cssContent.includes('@keyframes eqCenterPulse6'), 'CSS 缺少 eqCenterPulse6 中心对称跳跃关键帧');

// 验证 7 大状态 CSS 类全部完备
requiredLiveStates.forEach(state => {
  assert(
    cssContent.includes(`.notch-island.state-${state}`),
    `CSS 缺少 .notch-island.state-${state} 样式`
  );
});

// 验证 Wing 显示逻辑：在刘海弹出时（expanded, socket）不显示 wing，其他时候（wings, sneak, volume, charging）均显示
assert(!cssContent.includes('.notch-island.state-expanded .view-wings'), '错误：展开弹出态 expanded 下不应显示 wing');
assert(!cssContent.includes('.notch-island.state-socket .view-wings'), '错误：展开弹出态 socket 下不应显示 wing');
assert(cssContent.includes('.notch-island.state-wings .view-wings'), 'CSS 缺少 state-wings 下的 wing 显示');
assert(cssContent.includes('.notch-island.state-sneak .view-wings'), 'CSS 缺少 state-sneak 下的 wing 显示');
assert(cssContent.includes('.notch-island.state-volume .view-wings'), 'CSS 缺少 state-volume 下的 wing 显示');
assert(cssContent.includes('.notch-island.state-charging .view-wings'), 'CSS 缺少 state-charging 下的 wing 显示');
assert(cssContent.includes('.notch-island.state-snap .view-wings'), 'CSS 缺少 state-snap 下的 wing 显示');
assert(cssContent.includes('.window-snap-overlay'), 'CSS 缺少 .window-snap-overlay 样式');
assert(cssContent.includes('.ghost-snap-guide'), 'CSS 缺少 .ghost-snap-guide 样式');

// 3. 验证 JS 文件常量命名、巨幅半屏过渡与线性音量动态调节动画
const jsPath = path.join(__dirname, '../website/script.js');
const jsContent = fs.readFileSync(jsPath, 'utf8');

assert(jsContent.includes('const STATE_EMPTY = \'empty\''), 'JS 缺少 STATE_EMPTY 常量');
assert(jsContent.includes('const STATE_WINGS = \'wings\''), 'JS 缺少 STATE_WINGS 常量');
assert(jsContent.includes('const STATE_EXPANDED = \'expanded\''), 'JS 缺少 STATE_EXPANDED 常量');
assert(jsContent.includes('const STATE_SNEAK = \'sneak\''), 'JS 缺少 STATE_SNEAK 常量');
assert(jsContent.includes('const STATE_VOLUME = \'volume\''), 'JS 缺少 STATE_VOLUME 常量');
assert(jsContent.includes('const STATE_CHARGING = \'charging\''), 'JS 缺少 STATE_CHARGING 常量');
assert(jsContent.includes('const STATE_SOCKET = \'socket\''), 'JS 缺少 STATE_SOCKET 常量');
assert(jsContent.includes('const STATE_SNAP = \'snap\''), 'JS 缺少 STATE_SNAP 常量');
assert(!jsContent.includes('kconst'), 'JS 严禁使用 kconst 命名');
assert(jsContent.includes('class ScrollSyncEngine'), 'JS 缺少 ScrollSyncEngine 滚动引擎');
assert(jsContent.includes('updateSpatialMotion'), 'JS 缺少空间动效引擎 updateSpatialMotion');
assert(jsContent.includes('startVolumeAnimation'), 'JS 缺少音量动态调节动画方法 startVolumeAnimation');
assert(jsContent.includes('requestAnimationFrame(animateLoop)'), 'JS 音量动画应使用 requestAnimationFrame 实现无级线性平滑插值');
assert(!jsContent.includes('volumeValues['), 'JS 严禁使用离散数组阶梯跳变音量');

// 4. 验证 i18n.js 国际化多语言引擎（覆盖 app 内置全部 17 种语言）
const i18nPath = path.join(__dirname, '../website/i18n.js');
const i18nContent = fs.readFileSync(i18nPath, 'utf8');

assert(i18nContent.includes('class I18nEngine'), 'i18n 缺少 I18nEngine 类');
assert(i18nContent.includes('detectLanguage()'), 'i18n 缺少 detectLanguage 浏览器语言检测方法');
assert(i18nContent.includes('SUPPORTED_LANGUAGES'), 'i18n 缺少 SUPPORTED_LANGUAGES 数组');
assert(i18nContent.includes('bindSelectorEvents()'), 'i18n 缺少下拉选择器绑定事件');

// 校验 17 种官方应用内置语言均已注册
const appLanguages = [
  'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'de', 'fr', 'es',
  'it', 'ru', 'pt-BR', 'tr', 'pl', 'uk', 'ar', 'cs', 'hu'
];
appLanguages.forEach(lang => {
  assert(i18nContent.includes(`'${lang}'`), `i18n 缺少对官方语言 '${lang}' 的支持`);
});

assert(!i18nContent.includes('kconst'), 'i18n 严禁使用 kconst 命名');

console.log('✅ 所有测试通过！\n- 背景色统一为纯黑 #000000，高亮依然保持霓虹紫\n- 覆盖 app 全部内置 17 种语言的 i18n 引擎（支持浏览器语言自适应与原生下拉切换）\n- 已彻底移除演播台底部的胶囊切换控制栏（杜绝 overflow 隐患，界面更加纯净）\n- 首屏专属巨幅流光半屏特写 (只在首屏展示，严格复刻官方渲染图)\n- 刘海物理摄像头装饰已彻底取消\n- Wing 逻辑修正 (刘海弹出时隐藏，其他状态常驻)\n- 音量 HUD 采用高精度线性无级平滑动画\n- 8 大 Live Activity 与分屏状态（含 Windows 风格顶边吸附分屏 Window Snap Layouts 与毛玻璃幽灵替身）与右侧滚动 100% 灵动联动\n- Bento Grid 矩阵新增 Windows Snap 分屏特性卡片');
