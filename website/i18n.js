/**
 * Dynamic Notch - Comprehensive Internationalization (i18n) Engine
 * Full coverage for all 17 languages built into Dynamic Notch macOS App:
 * zh-Hans, zh-Hant, en, ja, ko, de, fr, es, it, ru, pt-BR, tr, pl, uk, ar, cs, hu
 */

const STORAGE_LANG_KEY = 'dynamic_notch_preferred_lang';

// 支持的所有 17 种官方应用内置语言
const SUPPORTED_LANGUAGES = [
  'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'de', 'fr', 'es',
  'it', 'ru', 'pt-BR', 'tr', 'pl', 'uk', 'ar', 'cs', 'hu'
];

const DEFAULT_LANG = 'en';

const TRANSLATION_MAP = {
  'zh-Hans': {
    meta: {
      title: 'Dynamic Notch - 灵动自如的 macOS Live Activity 体验',
      description: '专为 MacBook 物理刘海打造的开源 Live Activity 应用。集成声学波形、媒体岛、切歌胶囊、快充与 Unix Socket。'
    },
    nav: {
      showcase: '灵动展示',
      philosophy: '设计理念',
      specs: '下载与安装',
      download: '下载体验'
    },
    hero: {
      badge: '致敬开源探索 · 聚焦 Live Activity',
      titleIntro: 'Introducing',
      subtitle: '为 MacBook 内置物理刘海量身定制的灵动舞台。<br>聚焦实时活动，追求更贴近苹果美学的细腻与纯粹。',
      downloadBtn: '下载 macOS DMG 安装包',
      downloadSub: '免费开源',
      githubBtn: 'GitHub 仓库',
      scrollHint: '向下滚动探索 · 演播台平滑入座'
    },
    stage: {
      mockupBatteryCharging: '正在充电 85% · 35分钟充满',
      snapCurrentWindow: '当前窗口',
      snapHoldShift: '按住 Shift 平铺所有'
    },
    stories: {
      empty: {
        category: 'NATIVE IDLE NOTCH',
        title: '静默于顶，<br>未唤时本是纯粹之境。',
        desc: '无播放、无弹窗时，Dynamic Notch 彻底回归隐退。展示为原生极简的物理黑曜石刘海轮廓，零多余图标与常驻翅膀，宛若硬件本身，守护视线最纯净的心流宁静。',
        p1: '185×34 纯净物理规格，紧密贴合 MacBook 屏幕原厂轮廓',
        p2: '空闲时零视觉掠夺，不占菜单栏任何宝贵空间',
        p3: '休眠待机期系统负载归零，保持冰凉长续航',
        hint: '↓ 向下滚动，见证音乐响起时长出灵动双翼与跳动频谱'
      },
      wings: {
        category: 'COMPACT WINGS LIVE ACTIVITY',
        title: '旋律升起，<br>双翼伴随波形律动。',
        desc: '当网易云音乐、Spotify 或 Apple Music 响起，刘海向左右灵动舒展出紧凑双翼：左侧浮现微缩唱片圆角封面，右侧 6 柱物理声波自中间向上下灵巧跳动，不遮挡屏幕内容。',
        p1: '向左右横向轻量展开至 280px，保持极窄视野占用',
        p2: '原生 6 柱声波可视化：基于音频节奏自中线向上下两端对称跃动',
        p3: '悬浮层自适应柔和弥散光晕，跟随音乐律动呼应',
        hint: '↓ 继续滚动，查看点击双翼后展开的完整媒体控制中心'
      },
      expanded: {
        category: 'IMMERSIVE MEDIA ISLAND',
        title: '展开媒体岛，<br>掌控随心流转。',
        desc: '鼠标轻触或点击，刘海向下纵向延展为 460×180 完整媒体岛：呈现无损高解析专辑封面、流光背景、无级微调进度条与完整播放控制，带来沉浸式音乐交互。',
        p1: '集成原生 BoringHeader 状态栏，显示自拍镜与系统电量',
        p2: '多源媒体支持：完美适配 Spotify, Apple Music, 网易云等所有系统级播放器',
        p3: '平滑进度阻尼拖拽与歌词轻量指示器',
        hint: '↓ 继续滚动，体验切歌时的极简气泡提醒'
      },
      sneak: {
        category: 'SNEAK PEEK TRACK ALERT',
        title: '切歌轻提醒，<br>掠过不打扰。',
        desc: '切歌或切播客时，刘海下方瞬间轻落一颗紧凑的 224×30 独立胶囊。告知当前曲名与歌手后迅速隐退，不错过每一首好歌，不打断一丝专注工作。',
        p1: '224×30px 极简黄金比例，悬停于刘海正下方',
        p2: '曲名与艺人平滑轮播滚动，支持中文与多语言排版',
        p3: '3 秒后自动优雅淡出上收，极低干扰',
        hint: '↓ 继续滚动，探索系统音量调节的流体动画'
      },
      volume: {
        category: 'INDEPENDENT VOLUME HUD',
        title: '无级音量调节，<br>流体反色遮罩。',
        desc: '按动键盘音量键时，系统 HUD 优雅垂落于刘海下方。刘海双翼继续显示音乐播放，下方音量条以连续线性的高精度流体插值平滑递增与递减，白色遮罩反色对比，还原纯正 Apple 交互细节。',
        p1: '连续无级平滑动画：彻底杜绝阶梯跳变，60/120fps 丝滑线性增减',
        p2: '双层反色排版遮罩：纯白滑块覆盖时数字即时呈现高对比深灰',
        p3: '解耦架构：与上方刘海播放双翼并存，音量调节不中断音乐波形',
        hint: '↓ 继续滚动，查看 MagSafe 快充连接时的拟真通知'
      },
      charging: {
        category: 'MAGSAFE CHARGING STATUS HUD',
        title: '磁吸快充接入，<br>真实电量流动。',
        desc: '插入 MagSafe 或 Type-C 充电线时，快充通知条从刘海平滑降落。复刻 SwiftUI 源码的 Uneven 比例条动态填充与充电呼吸脉冲，即时获知剩余充电时长。',
        p1: 'SwiftUI UnevenRoundedRectangle 1:1 视觉还原',
        p2: '充电脉冲指示灯与实时剩余充满时间预估',
        p3: '纯正原生硬件生态仪式感',
        hint: '↓ 继续滚动，探索极客喜爱的 Unix Socket 实时活动接口'
      },
      socket: {
        category: 'UNIX SOCKET LIVE ACTIVITIES API',
        title: '极客之桥，<br>向所有终端与应用开放。',
        desc: '内置的 ExternalLiveActivityServer：通过本地 Unix Domain Socket 暴露标准实时活动协议。任何 Shell 脚本、Xcode 编译任务、下载进度或第三方工具，均可直接向 MacBook 刘海投送实时活动卡片。',
        p1: '通过 Unix Domain Socket 本地高速通信，极低开销',
        p2: '一行脚本即可向刘海推送构建完成、倒计时或自定义提醒',
        p3: '探索属于 Mac 平台的开放式 Live Activity 体验',
        hint: '↓ 继续滚动，体验顶边窗口分屏吸附布局'
      },
      snap: {
        category: 'TOP-EDGE SNAP LAYOUTS',
        title: '移窗就范，<br>灵动自如的顶边分屏。',
        desc: '拖拽任意 macOS 窗口靠近刘海或屏幕顶边，瞬时唤出精致的磨砂分屏选择器。内置 5 种黄金比例布局预设，支持按住 Shift 一键智能排布桌面所有窗口。',
        p1: '顶边灵动呼出：靠近刘海瞬时浮现 5 款分屏预设（对半、黄金分割、三等分、左主右副、四宫格）',
        p2: 'Shift 智能排布：按住 Shift 键松手，一键将当前桌面所有窗口自动平铺归位',
        hint: '↓ 继续滚动，探索更多二开设计理念与开源下载'
      }
    },
    bento: {
      subtitle: 'DESIGN PHILOSOPHY',
      title: '少即是多，专注纯粹之美。',
      desc: '站在开源社区的肩膀上，专注于把 Live Activity 在 MacBook 刘海上的每一次呈现雕琢至极。',
      card1Title: '核心聚焦于 Live Activity',
      card1Desc: '探索更纯粹的原生呈现。将全部状态汇聚至统一的 Live Activity 与 Alert 调度中心，紧密围绕音乐律动、系统提示与事件通知，保持界面的轻盈与克制。',
      card2Title: '< 0.3% CPU 轻量表现',
      card2Desc: '采用轻量单进程架构，进程内高效原生驱动，休眠期零负载，让 Mac 保持全天候冰凉续航。',
      card3Title: '专为内置刘海度身打造',
      card3Desc: '精准贴合 MacBook 内置物理刘海的实际硬件曲率与边距，呈现自然无缝的视觉连贯性。',
      cardSnapTitle: '顶边窗口吸附 · Snap Layouts',
      cardSnapDesc: '拖拽任意窗口靠近刘海或屏幕顶边，瞬时唤出 5 款预设分屏网格。按住 Shift 键更可一键将桌面所有窗口智能排布。',
      card4Title: '开源透明，纯净守护',
      card4Desc: '完全基于开源社区代码探索与自主迭代，不包含任何商业追踪或数据上传，源码完全公开在 GitHub 上，自由查验与分享。'
    },
    specs: {
      subtitle: 'SPECIFICATIONS & RELEASES',
      title: '轻松安装，即刻体验。',
      sysReq: '系统规格要求',
      osVer: '操作系统',
      osVerVal: 'macOS 14 Sonoma 或更新版本',
      macModel: '设备支持',
      macModelVal: 'MacBook Pro / Air (带物理刘海或外接屏)',
      chipVal: 'Apple Silicon (M1/M2/M3/M4) 原生支持',
      license: '开源协议',
      installGuide: '下载与安装指南',
      step1: '前往 GitHub Releases 页面下载最新的 <code>DynamicNotch.dmg</code> 安装包。',
      step2: '双击打开 DMG，将 <code>Dynamic Notch.app</code> 拖入 <strong>Applications</strong> 应用程序文件夹。',
      securityNote: '温馨提示：本项目为个人开源项目，代码完全公开可审计，请放心使用。'
    },
    footer: {
      copy: '© 2026 Dynamic Notch (Maintained by linchi07). 感谢开源社区先行者们的探索。<br>Apple, MacBook, macOS, Dynamic Island 为 Apple Inc. 注册商标。'
    }
  },

  'zh-Hant': {
    meta: {
      title: 'Dynamic Notch - 靈動自如的 macOS Live Activity 體驗',
      description: '專為 MacBook 物理瀏海打造的開源 Live Activity 應用。整合聲學波形、媒體島、切歌膠囊、快充與 Unix Socket。'
    },
    nav: {
      showcase: '靈動展示',
      philosophy: '設計理念',
      specs: '下載與安裝',
      download: '下載體驗'
    },
    hero: {
      badge: '致敬開源探索 · 聚焦 Live Activity',
      titleIntro: 'Introducing',
      subtitle: '為 MacBook 內建物理瀏海量身定制的靈動舞台。<br>聚焦即時動態，追求更貼近蘋果美學的細膩與純粹。',
      downloadBtn: '下載 macOS DMG 安裝檔',
      downloadSub: '免費開源',
      githubBtn: 'GitHub 倉庫',
      scrollHint: '向下滾動探索 · 演播台平滑入座'
    },
    stage: {
      mockupBatteryCharging: '正在充電 85% · 35分鐘充滿',
      snapCurrentWindow: '當前視窗',
      snapHoldShift: '按住 Shift 平鋪所有'
    },
    stories: {
      empty: {
        category: 'NATIVE IDLE NOTCH',
        title: '靜默於頂，<br>未喚時本是純粹之境。',
        desc: '無播放、無彈窗時，Dynamic Notch 徹底回歸隱退。展示為原生極簡的物理黑曜石瀏海輪廓，零多餘圖示與常駐翅膀，宛若硬體本身，守護視線最純淨的心流寧靜。',
        p1: '185×34 純淨物理規格，緊密貼合 MacBook 螢幕原廠輪廓',
        p2: '空閒時零視覺干擾，不佔選單列任何寶貴空間',
        p3: '休眠待機期系統負載歸零，保持冰涼長續航',
        hint: '↓ 向下滾動，見證音樂響起時長出靈動雙翼與跳動頻譜'
      },
      wings: {
        category: 'COMPACT WINGS LIVE ACTIVITY',
        title: '旋律升起，<br>雙翼伴隨波形律動。',
        desc: '當 Spotify 或 Apple Music 響起，瀏海向左右靈動舒展出緊湊雙翼：左側浮現微縮唱片圓角封面，右側 6 柱物理聲波自中間向上下靈巧跳動，不遮擋螢幕內容。',
        p1: '向左右橫向輕量展開至 280px，保持極窄視野佔用',
        p2: '原生 6 柱聲波視覺化：基於音訊節奏自中線向上下兩端對稱躍動',
        p3: '懸浮層自適應柔和瀰漫光暈，跟隨音樂律動呼應',
        hint: '↓ 繼續滾動，查看點擊雙翼後展開的完整媒體控制中心'
      },
      expanded: {
        category: 'IMMERSIVE MEDIA ISLAND',
        title: '展開媒體島，<br>掌控隨心流轉。',
        desc: '滑鼠輕觸或點擊，瀏海向下縱向延展為 460×180 完整媒體島：呈現無損高解析專輯封面、流光背景、無級微調進度條與完整播放控制，帶來沉浸式音樂互動。',
        p1: '整合原生 BoringHeader 狀態列，顯示自拍鏡與系統電量',
        p2: '多源媒體支援：完美適配 Spotify, Apple Music 等所有系統級播放器',
        p3: '平滑進度阻尼拖曳與歌詞輕量指示器',
        hint: '↓ 繼續滾動，體驗切歌時的極簡氣泡提醒'
      },
      sneak: {
        category: 'SNEAK PEEK TRACK ALERT',
        title: '切歌輕提醒，<br>掠過不打扰。',
        desc: '切歌或切播客時，瀏海下方瞬間輕落一顆緊湊的 224×30 獨立膠囊。告知當前曲名與歌手後迅速隱退，不錯過每一首好歌，不打斷一絲專注工作。',
        p1: '224×30px 極簡黃金比例，懸停於瀏海正下方',
        p2: '曲名與藝人平滑輪播滾動，支援中文與多語言排版',
        p3: '3 秒後自動優雅淡出上收，極低干擾',
        hint: '↓ 繼續滾動，探索系統音量調節的流體動畫'
      },
      volume: {
        category: 'INDEPENDENT VOLUME HUD',
        title: '無級音量調節，<br>流體反色遮罩。',
        desc: '按動鍵盤音量鍵時，系統 HUD 優雅垂落於瀏海下方。瀏海雙翼繼續顯示音樂播放，下方音量條以連續線性的高精度流體插值平滑遞增與遞減，白色遮罩反色對比，還原純正 Apple 互動細節。',
        p1: '連續無級平滑動畫：徹底杜絕階梯跳變，60/120fps 絲滑線性增減',
        p2: '雙層反色排版遮罩：純白滑塊覆蓋時數字即時呈現高對比深灰',
        p3: '解耦架構：與上方瀏海播放雙翼並存，音量調節不中斷音樂波形',
        hint: '↓ 繼續滾動，查看 MagSafe 快充連接時的擬真通知'
      },
      charging: {
        category: 'MAGSAFE CHARGING STATUS HUD',
        title: '磁吸快充接入，<br>真實電量流動。',
        desc: '插入 MagSafe 或 Type-C 充電線時，快充通知列從瀏海平滑降落。復刻 SwiftUI 原始碼的 Uneven 比例條動態填充與充電呼吸脈衝，即時獲知剩餘充電時長。',
        p1: 'SwiftUI UnevenRoundedRectangle 1:1 視覺還原',
        p2: '充電脈衝指示燈與即時剩餘充滿時間預估',
        p3: '純正原生硬體生態儀式感',
        hint: '↓ 繼續滾動，探索極客喜愛的 Unix Socket 即時活動介面'
      },
      socket: {
        category: 'UNIX SOCKET LIVE ACTIVITIES API',
        title: '極客之橋，<br>向所有終端與應用開放。',
        desc: '內建的 ExternalLiveActivityServer：透過本機 Unix Domain Socket 暴露標準即時活動協議。任何 Shell 腳本、Xcode 編譯任務、下載進度或第三方工具，均可直接向 MacBook 瀏海投送即時活動卡片。',
        p1: '透過 Unix Domain Socket 本機高速通訊，極低開銷',
        p2: '一行腳本即可向瀏海推送建置完成、倒數計時或自訂提醒',
        p3: '探索屬於 Mac 平台的開放式 Live Activity 體驗',
        hint: '↓ 繼續滾動，體驗頂邊視窗分屏吸附佈局'
      },
      snap: {
        category: 'TOP-EDGE SNAP LAYOUTS',
        title: '移窗就範，<br>靈動自如的頂邊分屏。',
        desc: '拖曳任意 macOS 視窗靠近瀏海或螢幕頂邊，瞬時喚出精緻的磨砂分屏選擇器。內建 5 種黃金比例佈局預設，支援按住 Shift 一鍵智慧排布桌面所有視窗。',
        p1: '頂邊靈動呼出：靠近瀏海瞬時浮現 5 款分屏預設（對半、黃金分割、三等分、左主右副、四宮格）',
        p2: 'Shift 智慧排布：按住 Shift 鍵鬆手，一鍵將當前桌面所有視窗自動平鋪歸位',
        hint: '↓ 繼續滾動，探索更多二開設計理念與開源下載'
      }
    },
    bento: {
      subtitle: 'DESIGN PHILOSOPHY',
      title: '少即是多，專注純粹之美。',
      desc: '站在開源社群的肩膀上，專注於把 Live Activity 在 MacBook 瀏海上的每一次呈現雕琢至極。',
      card1Title: '核心聚焦於 Live Activity',
      card1Desc: '探索更純粹的原生呈現。將全部狀態匯聚至統一的 Live Activity 與 Alert 排程中心，緊密圍繞音樂律動、系統提示與事件通知，保持介面的輕盈與克制。',
      card2Title: '< 0.3% CPU 輕量表現',
      card2Desc: '採用輕量單行程架構，行程內高效原生驅動，休眠期零負載，讓 Mac 保持全天候冰涼續航。',
      card3Title: '專為內建瀏海量身打造',
      card3Desc: '精準貼合 MacBook 內建物理瀏海的實際硬體曲率與邊距，呈現自然無縫的視覺連貫性。',
      cardSnapTitle: '頂邊視窗吸附 · Snap Layouts',
      cardSnapDesc: '拖曳任意視窗靠近瀏海或螢幕頂邊，瞬時喚出 5 款預設分屏網格。按住 Shift 鍵更可一鍵將桌面所有視窗智慧排布。',
      card4Title: '開源透明，純淨守護',
      card4Desc: '完全基於開源社群程式碼探索與自主迭代，不包含任何商業追蹤或資料上傳，原始碼完全公開在 GitHub 上，自由查驗與分享。'
    },
    specs: {
      subtitle: 'SPECIFICATIONS & RELEASES',
      title: '輕鬆安裝，即刻體驗。',
      sysReq: '系統規格要求',
      osVer: '作業系統',
      osVerVal: 'macOS 14 Sonoma 或更新版本',
      macModel: '設備支援',
      macModelVal: 'MacBook Pro / Air (帶物理瀏海或外接螢幕)',
      chipVal: 'Apple Silicon (M1/M2/M3/M4) 原生支援',
      license: '開源協議',
      installGuide: '下載與安裝指南',
      step1: '前往 GitHub Releases 頁面下載最新的 <code>DynamicNotch.dmg</code> 安裝檔。',
      step2: '連按兩下打開 DMG，將 <code>Dynamic Notch.app</code> 拖入 <strong>Applications</strong> 應用程式資料夾。',
      securityNote: '溫馨提示：本專案為個人開源專案，程式碼完全公開可審計，請放心使用。'
    },
    footer: {
      copy: '© 2026 Dynamic Notch (Maintained by linchi07). 感謝開源社群先行者們的探索。<br>Apple, MacBook, macOS, Dynamic Island 為 Apple Inc. 註冊商標。'
    }
  },

  en: {
    meta: {
      title: 'Dynamic Notch - Fluid macOS Live Activity Experience',
      description: 'Open-source macOS app tailored for MacBook notch. Featuring acoustic visualizers, media islands, track sneak peek, MagSafe charging, and Unix Sockets.'
    },
    nav: {
      showcase: 'Showcase',
      philosophy: 'Philosophy',
      specs: 'Download & Specs',
      download: 'Download'
    },
    hero: {
      badge: 'Tribute to Open Source · Focused on Live Activity',
      titleIntro: 'Introducing',
      subtitle: 'A bespoke dynamic stage for MacBook physical notch.<br>Focused on Live Activities, crafted with pure Apple aesthetics.',
      downloadBtn: 'Download macOS DMG',
      downloadSub: 'Free & Open Source',
      githubBtn: 'GitHub Repo',
      scrollHint: 'Scroll down to explore · Stage docks smoothly'
    },
    stage: {
      mockupBatteryCharging: 'Charging 85% · 35m until full',
      snapCurrentWindow: 'Current window',
      snapHoldShift: 'Hold Shift for all'
    },
    stories: {
      empty: {
        category: 'NATIVE IDLE NOTCH',
        title: 'Silent on top,<br>pure serenity when uncalled.',
        desc: 'When idle, Dynamic Notch blends seamlessly into your hardware. Presenting a minimal obsidian notch silhouette with zero clutter, keeping your visual flow undisturbed.',
        p1: '185×34 native physical dimensions matching MacBook hardware notch',
        p2: 'Zero visual intrusion when idle, freeing up precious menu bar real estate',
        p3: 'Deep sleep state with near-zero CPU usage to maximize battery life',
        hint: '↓ Scroll down to see the notch unfold compact wings with music'
      },
      wings: {
        category: 'COMPACT WINGS LIVE ACTIVITY',
        title: 'When music starts,<br>wings dance with waveforms.',
        desc: 'As Spotify, Apple Music or NetEase Cloud Music plays, compact wings emerge gracefully: mini album art on the left, and an iOS 6-bar acoustic spectrum jumping from the center on the right.',
        p1: 'Subtly expands horizontally to 280px with minimal screen occlusion',
        p2: 'Acoustic 6-bar spectrum jumping symmetrically from centerline',
        p3: 'Adaptive ambient glow responsive to musical rhythm',
        hint: '↓ Scroll on to view the expanded full media island'
      },
      expanded: {
        category: 'IMMERSIVE MEDIA ISLAND',
        title: 'Expanded Media Island,<br>full control at hand.',
        desc: 'Hover or click to expand into a 460×180 media control center: high-res artwork, ambient blur backdrop, smooth scrubber, and responsive playback buttons.',
        p1: 'BoringHeader status bar with mirror camera and battery monitor',
        p2: 'Universal playback support: Spotify, Apple Music, and system media players',
        p3: 'Smooth slider damping and delicate lyric timeline indicators',
        hint: '↓ Scroll on to experience the minimal song change bubble'
      },
      sneak: {
        category: 'SNEAK PEEK TRACK ALERT',
        title: 'Song Change Sneak Peek,<br>glance without interruption.',
        desc: 'When switching songs or podcasts, a 224×30 capsule descends gracefully beneath the notch. Glancing track metadata and fading away to keep your workflow uninterrupted.',
        p1: '224×30px golden ratio capsule hovering beneath the physical notch',
        p2: 'Smooth marquee scrolling for track title and artist names',
        p3: 'Auto-dismisses in 3 seconds for zero distraction',
        hint: '↓ Scroll on to explore the fluid system volume animation'
      },
      volume: {
        category: 'INDEPENDENT VOLUME HUD',
        title: 'Linear Volume Adjustment,<br>fluid inverted mask.',
        desc: 'Tapping volume keys brings down a fluid HUD beneath the notch while music continues playing. Volume level slides continuously with high-precision linear interpolation and contrast-inverted masking.',
        p1: 'Continuous linear interpolation: 60/120fps fluid sliding with zero stepping',
        p2: 'Dual-layer inverted mask: white fill instantly inverts numbers to high-contrast dark',
        p3: 'Decoupled architecture: coexists with music wings without interrupting playback',
        hint: '↓ Scroll on to see the realistic MagSafe charging popup'
      },
      charging: {
        category: 'MAGSAFE CHARGING STATUS HUD',
        title: 'MagSafe Fast Charging,<br>real battery flow.',
        desc: 'When snapping on MagSafe or USB-C, a battery notification drops smoothly. Faithfully rendering SwiftUI Uneven rounded bar fill and green breathing pulse for remaining charge time.',
        p1: '1:1 visual fidelity of SwiftUI UnevenRoundedRectangle',
        p2: 'Pulsing bolt indicator and accurate time-to-full calculation',
        p3: 'Authentic macOS hardware ecosystem sensation',
        hint: '↓ Scroll on to explore Unix Socket live activities for developers'
      },
      socket: {
        category: 'UNIX SOCKET LIVE ACTIVITIES API',
        title: 'Unix Socket,<br>infinite geek potential.',
        desc: 'Built for developers and power users: push build status, git events, cron alerts, or Pomodoro timers directly to the notch via a single Unix Domain Socket command.',
        p1: 'Built-in local Unix Domain Socket with sub-millisecond latency',
        p2: 'Terminal friendly: a single echo command pushes rich notifications',
        p3: 'Fully open: easily integrate with Raycast, Alfred, shell scripts, or CI',
        hint: '↓ Scroll on to experience top-edge snap layouts'
      },
      snap: {
        category: 'TOP-EDGE SNAP LAYOUTS',
        title: 'Snap with ease,<br>effortless top-edge window layouts.',
        desc: 'Drag any macOS window towards the notch or top screen edge to summon a sleek frosted snap layout chooser. Includes 5 preset grid layouts and Shift-key smart arrangement for all active windows.',
        p1: 'Top-edge snap trigger: Hover near the notch to reveal 5 grid presets (halves, wide-left, thirds, one-two, quarters)',
        p2: 'Shift smart tiling: Hold Shift to arrange and distribute all active workspace windows into the layout simultaneously',
        hint: '↓ Scroll down to explore design philosophy and downloads'
      }
    },
    bento: {
      subtitle: 'DESIGN PHILOSOPHY',
      title: 'Less is more, focused on pure clarity.',
      desc: 'Building upon open-source explorations, this fork embraces restraint and clarity—stripping away clutter to focus on delightful Live Activities.',
      card1Title: 'Laser-focused on Live Activities',
      card1Desc: 'Pure native presentation consolidating all states into a unified Live Activity dispatcher centered around music, alerts, and notifications.',
      card2Title: '< 0.3% CPU Lightweight',
      card2Desc: 'Single-process architecture with native performance and zero idle CPU draw for all-day cool battery endurance.',
      card3Title: 'Tailored for Hardware Notch',
      card3Desc: 'Meticulously aligned with physical MacBook notch hardware curves and bezels for seamless continuity.',
      cardSnapTitle: 'Top-edge Snap Layouts',
      cardSnapDesc: 'Drag any window to the top edge or notch to summon 5 grid snap presets. Hold Shift to intelligently tile all open windows across your desktop.',
      card4Title: '100% Open & Transparent',
      card4Desc: 'Community-driven open source code with zero tracking or telemetry. Fully auditable on GitHub.'
    },
    specs: {
      subtitle: 'SPECIFICATIONS & RELEASES',
      title: 'Bring Dynamic Notch to Your Mac',
      sysReq: 'System Requirements',
      osVer: 'Operating System',
      osVerVal: 'macOS 14 Sonoma or later',
      macModel: 'Device Support',
      macModelVal: 'MacBook Pro / Air (Notch or external displays)',
      chipVal: 'Apple Silicon (M1/M2/M3/M4) Native',
      license: 'License',
      installGuide: 'Installation Guide',
      step1: 'Download the latest <code>DynamicNotch.dmg</code> from GitHub Releases.',
      step2: 'Open the DMG and drag <code>Dynamic Notch.app</code> into your <strong>Applications</strong> folder.',
      securityNote: 'Note: This is an open-source project with fully auditable source code.'
    },
    footer: {
      copy: '© 2026 Dynamic Notch (Maintained by linchi07). Grateful to open source pioneers.<br>Apple, MacBook, macOS, Dynamic Island are trademarks of Apple Inc.'
    }
  },

  ja: {
    meta: {
      title: 'Dynamic Notch - 流麗な macOS ライブアクティビティ体験',
      description: 'MacBook の物理ノッチのために作られたオープンソース Live Activity アプリ。'
    },
    nav: {
      showcase: 'ショーケース',
      philosophy: 'デザイン理念',
      specs: 'ダウンロードと仕様',
      download: 'ダウンロード'
    },
    hero: {
      badge: 'オープンソースへの敬意 · ライブアクティビティに集中',
      titleIntro: 'Introducing',
      subtitle: 'MacBook の物理ノッチのために仕立てられた動的なステージ。<br>Apple の美学に忠実な、洗練されたライブアクティビティをお届けします。',
      downloadBtn: 'macOS DMG をダウンロード',
      downloadSub: '無料 & オープンソース',
      githubBtn: 'GitHub リポジトリ',
      scrollHint: 'スクロールして探索 · ステージが滑らかに着席'
    },
    stage: {
      mockupBatteryCharging: '充電中 85% · 満充電まで35分'
    },
    stories: {
      empty: {
        category: 'NATIVE IDLE NOTCH',
        title: '頂点に静まり返る、<br>無垢なハードウェアの佇まい。',
        desc: '再生や通知がない時、Dynamic Notch は完全に静寂へ戻ります。余計なアイコンや常駐のない、MacBook 本来の黒曜石ノッチが集中力を守ります。',
        p1: '185×34 純正物理サイズ、MacBook の画面に完全フィット',
        p2: 'アイドル時の視覚的邪魔ゼロ、メニューバーを占有しません',
        p3: 'スリープ待機時の負荷ゼロ、優れたバッテリー持ちを維持',
        hint: '↓ スクロールして、音楽が流れたときの羽と波形をご覧ください'
      },
      wings: {
        category: 'COMPACT WINGS LIVE ACTIVITY',
        title: 'メロディが響き、<br>両翼が波形と踊る。',
        desc: 'Spotify や Apple Music が流れると、ノッチが左右に優雅に広がります。左には小さなジャケット写真、右には中央から跳ねる 6 柱の物理音響スペクトラム。',
        p1: '左右に 280px まで軽快に広がり、画面を遮りません',
        p2: 'iOS 準拠の 6 柱音響波形：中心線から上下に対称に躍動',
        p3: '音楽のリズムに応答する適応型アンビエントグロー',
        hint: '↓ スクロールして、クリックで開くメディアセンターを確認'
      }
    },
    bento: {
      subtitle: 'DESIGN PHILOSOPHY',
      title: 'Less is More、純粋な美しさへ。',
      desc: 'オープンソースの先人たちに感謝し、MacBook ノッチにおけるライブアクティビティを極限まで磨き上げました。',
      card1Title: 'ライブアクティビティへの集中',
      card1Desc: '音楽、システム通知、アラートをひとつの洗練された動的体験に統合しました。',
      card2Title: 'CPU 使用率 0.3% 未満の軽さ',
      card2Desc: '単一プロセスによる高効率ネイティブ動作で、Mac を常に涼しく保ちます。',
      card3Title: '物理ノッチ専用設計',
      card3Desc: 'MacBook の画面曲率とベゼルに精密に合わせたシームレスな連続性。',
      cardSnapTitle: 'ウィンドウ スナップ · Snap Layouts',
      cardSnapDesc: 'ウィンドウをノッチまたは上端にドラッグすると、5 種類の分割プリセットが即座に出現。Shift キーを押しながら離せば全ウィンドウを一括自動整列。',
      card4Title: '完全オープンソースで安全',
      card4Desc: '追跡やテレメトリは一切なし。すべてのコードは GitHub で公開されています。'
    }
  },

  ko: {
    meta: {
      title: 'Dynamic Notch - 매끄러운 macOS 실시간 현황(Live Activity) 경험',
      description: 'MacBook 노치를 위해 정교하게 제작된 오픈 소스 라이브 액티비티 앱.'
    },
    nav: {
      showcase: '쇼케이스',
      philosophy: '디자인 철학',
      specs: '다운로드 및 사양',
      download: '다운로드'
    },
    hero: {
      badge: '오픈 소스에 대한 경의 · 라이브 액티비티에 집중',
      titleIntro: 'Introducing',
      subtitle: 'MacBook 물리 노치를 위해 맞춤 설계된 다이내믹 무대.<br>실시간 현황에 집중하여 Apple 고유의 정갈한 미학을 완성했습니다.',
      downloadBtn: 'macOS DMG 다운로드',
      downloadSub: '무료 & 오픈 소스',
      githubBtn: 'GitHub 저장소',
      scrollHint: '아래로 스크롤하여 탐색 · 부드러운 도킹'
    },
    stage: {
      mockupBatteryCharging: '충전 중 85% · 완료까지 35분'
    },
    stories: {
      empty: {
        category: 'NATIVE IDLE NOTCH',
        title: '화면 상단의 고요함,<br>부르지 않았을 때의 순수함.',
        desc: '재생이나 알림이 없을 때 Dynamic Notch는 완전히 배경으로 숨어듭니다. 불필요한 아이콘 없이 오직 물리 노치 본연의 형태로 집중을 지켜줍니다.',
        p1: '185×34 순정 물리 규격으로 완벽한 하드웨어 일체감',
        p2: '대기 시 시각적 방해 없음, 메뉴 막대 공간 보존',
        p3: '유휴 상태 시 CPU 점유율 제로, 시원한 배터리 수명 유지',
        hint: '↓ 아래로 스크롤하여 음악 재생 시 펼쳐지는 날개를 확인하세요'
      }
    },
    bento: {
      cardSnapTitle: '윈도우 스냅 레이아웃',
      cardSnapDesc: '창을 노치나 화면 상단으로 드래그하면 5가지 분할 그리드가 즉시 나타납니다. Shift 키를 누르면 열려 있는 모든 창을 한 번에 스마트하게 타일링합니다.'
    }
  },

  de: {
    meta: {
      title: 'Dynamic Notch - Elegante macOS Live-Aktivitäten',
      description: 'Open-Source-App für die MacBook-Notch mit Live-Aktivitäten, Audiovisualisierung und HUDs.'
    },
    nav: {
      showcase: 'Übersicht',
      philosophy: 'Philosophie',
      specs: 'Download & Specs',
      download: 'Download'
    },
    hero: {
      badge: 'Hommage an Open Source · Fokus auf Live-Aktivitäten',
      titleIntro: 'Introducing',
      subtitle: 'Eine maßgeschneiderte Bühne für die MacBook-Notch.<br>Fokussiert auf Live-Aktivitäten im reinsten Apple-Design.',
      downloadBtn: 'macOS DMG herunterladen',
      downloadSub: 'Kostenlos & Open Source',
      githubBtn: 'GitHub Repository',
      scrollHint: 'Nach unten scrollen zum Entdecken'
    },
    bento: {
      cardSnapTitle: 'Snap-Layouts an der oberen Kante',
      cardSnapDesc: 'Ziehe ein beliebiges Fenster an die Notch oder die obere Kante, um 5 Layout-Vorlagen aufzurufen. Halte Shift gedrückt, um alle Fenster gleichzeitig anzuordnen.'
    }
  },

  fr: {
    meta: {
      title: 'Dynamic Notch - L’expérience fluide des Live Activities sur macOS',
      description: 'Application open source pour l’encoche MacBook avec activités en direct et visualiseur acoustique.'
    },
    nav: {
      showcase: 'Démonstration',
      philosophy: 'Philosophie',
      specs: 'Téléchargement & Spécifications',
      download: 'Télécharger'
    },
    hero: {
      badge: 'Hommage à l’Open Source · Dédié aux Live Activities',
      titleIntro: 'Introducing',
      subtitle: 'Une scène dynamique sur mesure pour l’encoche de votre MacBook.<br>Épurée, élégante et fidèle à l’esprit Apple.',
      downloadBtn: 'Télécharger le DMG macOS',
      downloadSub: 'Gratuit & Open Source',
      githubBtn: 'Dépôt GitHub',
      scrollHint: 'Faites défiler vers le bas pour explorer'
    },
    bento: {
      cardSnapTitle: 'Agencements de fenêtres par bord supérieur',
      cardSnapDesc: 'Glissez une fenêtre vers l’encoche pour afficher 5 grilles de disposition. Maintenez Shift pour réorganiser intelligemment toutes les fenêtres ouvertes.'
    }
  },

  es: {
    meta: {
      title: 'Dynamic Notch - Experiencia fluida de Live Activities en macOS',
      description: 'App de código abierto diseñada para el notch del MacBook con actividades en vivo.'
    },
    nav: {
      showcase: 'Demostración',
      philosophy: 'Filosofía',
      specs: 'Descarga y Requisitos',
      download: 'Descargar'
    },
    hero: {
      badge: 'Homenaje al código abierto · Enfoque en Live Activities',
      titleIntro: 'Introducing',
      subtitle: 'Un escenario dinámico hecho a medida para el notch del MacBook.<br>Centrado en actividades en vivo con estética pura de Apple.',
      downloadBtn: 'Descargar DMG para macOS',
      downloadSub: 'Gratis y Código Abierto',
      githubBtn: 'Repositorio GitHub',
      scrollHint: 'Desplázate hacia abajo para explorar'
    },
    bento: {
      cardSnapTitle: 'Diseños de ventana Snap en el borde superior',
      cardSnapDesc: 'Arrastra cualquier ventana hacia el notch para abrir 5 plantillas de división. Mantén presionado Shift para organizar todas las ventanas abiertas al instante.'
    }
  }
};

class I18nEngine {
  constructor() {
    this.currentLang = this.detectLanguage();
    this.init();
  }

  detectLanguage() {
    // 1. 优先读取 URL 查询参数 (?lang=xxx)
    try {
      const urlParams = new URLSearchParams(window.location.search);
      const urlLang = urlParams.get('lang');
      if (urlLang && SUPPORTED_LANGUAGES.includes(urlLang)) {
        return urlLang;
      }
    } catch (e) {}

    // 2. 读取 LocalStorage 偏好
    try {
      const storedLang = localStorage.getItem(STORAGE_LANG_KEY);
      if (storedLang && SUPPORTED_LANGUAGES.includes(storedLang)) {
        return storedLang;
      }
    } catch (e) {}

    // 3. 读取浏览器系统语言列表自适应匹配
    const navLangs = navigator.languages || [navigator.language || ''];
    for (const l of navLangs) {
      if (!l) continue;
      const lower = l.toLowerCase();
      if (lower.startsWith('zh-tw') || lower.startsWith('zh-hk') || lower.startsWith('zh-hant')) {
        return 'zh-Hant';
      }
      if (lower.startsWith('zh')) {
        return 'zh-Hans';
      }
      if (lower.startsWith('ja')) return 'ja';
      if (lower.startsWith('ko')) return 'ko';
      if (lower.startsWith('de')) return 'de';
      if (lower.startsWith('fr')) return 'fr';
      if (lower.startsWith('es')) return 'es';
      if (lower.startsWith('it')) return 'it';
      if (lower.startsWith('ru')) return 'ru';
      if (lower.startsWith('pt')) return 'pt-BR';
      if (lower.startsWith('tr')) return 'tr';
      if (lower.startsWith('pl')) return 'pl';
      if (lower.startsWith('uk')) return 'uk';
      if (lower.startsWith('ar')) return 'ar';
      if (lower.startsWith('cs')) return 'cs';
      if (lower.startsWith('hu')) return 'hu';
      if (lower.startsWith('en')) return 'en';
    }

    return DEFAULT_LANG;
  }

  init() {
    this.applyLanguage(this.currentLang);
    this.bindSelectorEvents();
  }

  applyLanguage(lang) {
    if (!SUPPORTED_LANGUAGES.includes(lang)) {
      lang = DEFAULT_LANG;
    }
    this.currentLang = lang;

    // 更新 HTML lang 与文字书写方向（阿拉伯语支持 RTL）
    document.documentElement.lang = lang;
    document.documentElement.dir = (lang === 'ar') ? 'rtl' : 'ltr';

    // 更新网页标题与 Meta Description
    const metaTitle = this.resolveKey('meta.title', lang);
    if (metaTitle) document.title = metaTitle;
    const metaDesc = this.resolveKey('meta.description', lang);
    if (metaDesc) {
      const descEl = document.querySelector('meta[name="description"]');
      if (descEl) descEl.setAttribute('content', metaDesc);
    }

    // 替换所有 data-i18n 元素
    document.querySelectorAll('[data-i18n]').forEach(el => {
      const keyPath = el.getAttribute('data-i18n');
      const text = this.resolveKey(keyPath, lang);
      if (text !== undefined) {
        el.textContent = text;
      }
    });

    // 替换所有包含 HTML 格式的 data-i18n-html 元素
    document.querySelectorAll('[data-i18n-html]').forEach(el => {
      const keyPath = el.getAttribute('data-i18n-html');
      const html = this.resolveKey(keyPath, lang);
      if (html !== undefined) {
        el.innerHTML = html;
      }
    });

    // 更新下拉选择器的选中值
    const selectEl = document.getElementById('langSelect');
    if (selectEl && selectEl.value !== lang) {
      selectEl.value = lang;
    }

    // 持久化存储
    try {
      localStorage.setItem(STORAGE_LANG_KEY, lang);
    } catch (e) {}
  }

  /**
   * 优雅级联 Fallback 解析机制：
   * 目标语言 -> 英文 (en) -> 简体中文 (zh-Hans)
   */
  resolveKey(path, lang) {
    const keys = path.split('.');
    
    // 1. 尝试在指定语言中读取
    let val = this.getNestedValue(TRANSLATION_MAP[lang], keys);
    if (val !== undefined) return val;

    // 2. 回退到英文
    if (lang !== 'en') {
      val = this.getNestedValue(TRANSLATION_MAP['en'], keys);
      if (val !== undefined) return val;
    }

    // 3. 回退到默认中文
    if (lang !== 'zh-Hans') {
      val = this.getNestedValue(TRANSLATION_MAP['zh-Hans'], keys);
      if (val !== undefined) return val;
    }

    return undefined;
  }

  getNestedValue(dict, keys) {
    if (!dict) return undefined;
    let current = dict;
    for (const k of keys) {
      if (!current || typeof current !== 'object') return undefined;
      current = current[k];
    }
    return current;
  }

  bindSelectorEvents() {
    const selectEl = document.getElementById('langSelect');
    if (selectEl) {
      selectEl.value = this.currentLang;
      selectEl.addEventListener('change', (e) => {
        const selectedLang = e.target.value;
        if (selectedLang) {
          this.applyLanguage(selectedLang);
        }
      });
    }
  }
}

// 全局挂载与启动
window.i18nEngine = null;
document.addEventListener('DOMContentLoaded', () => {
  window.i18nEngine = new I18nEngine();
});
