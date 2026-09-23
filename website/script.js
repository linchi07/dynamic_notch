/**
 * Dynamic Notch - Apple Style Live Activity & Smooth Scroll Sync
 */

// 状态常量定义 (8 大 Live Activity 与系统交互真实状态 + 兼容别名)
const STATE_EMPTY = 'empty';
const STATE_WINGS = 'wings';
const STATE_EXPANDED = 'expanded';
const STATE_SNEAK = 'sneak';
const STATE_VOLUME = 'volume';
const STATE_CHARGING = 'charging';
const STATE_SOCKET = 'socket';
const STATE_SNAP = 'snap';
const STATE_HUD = 'hud'; // 兼容快充与音量联合态

// 各状态专属动态光晕调色板 (Apple 发布会经典柔光弥散)
const STATE_GLOW_PALETTE = {
  [STATE_EMPTY]: 'radial-gradient(circle, rgba(168, 85, 247, 0.28) 0%, rgba(126, 34, 206, 0.1) 50%, transparent 75%)',
  [STATE_WINGS]: 'radial-gradient(circle, rgba(168, 85, 247, 0.45) 0%, rgba(126, 34, 206, 0.18) 50%, transparent 75%)',
  [STATE_EXPANDED]: 'radial-gradient(circle, rgba(216, 70, 239, 0.55) 0%, rgba(168, 85, 247, 0.3) 45%, transparent 75%)',
  [STATE_SNEAK]: 'radial-gradient(circle, rgba(56, 189, 248, 0.45) 0%, rgba(14, 165, 233, 0.2) 50%, transparent 75%)',
  [STATE_VOLUME]: 'radial-gradient(circle, rgba(255, 255, 255, 0.38) 0%, rgba(168, 85, 247, 0.18) 50%, transparent 75%)',
  [STATE_CHARGING]: 'radial-gradient(circle, rgba(52, 199, 89, 0.5) 0%, rgba(34, 197, 94, 0.22) 50%, transparent 75%)',
  [STATE_SOCKET]: 'radial-gradient(circle, rgba(56, 189, 248, 0.5) 0%, rgba(168, 85, 247, 0.25) 50%, transparent 75%)',
  [STATE_SNAP]: 'radial-gradient(circle, rgba(56, 189, 248, 0.45) 0%, rgba(147, 51, 234, 0.2) 50%, transparent 75%)',
  [STATE_HUD]: 'radial-gradient(circle, rgba(52, 199, 89, 0.5) 0%, rgba(34, 197, 94, 0.22) 50%, transparent 75%)'
};

class NotchController {
  constructor() {
    this.notchIsland = document.getElementById('dynamicNotchIsland');
    this.macbookMockup = document.getElementById('macbookMockup');
    this.glowHalo = document.getElementById('islandGlowHalo');
    this.currentState = STATE_EMPTY;
    this.isMusicPlaying = true;
    this.btnMainPlay = document.getElementById('btnMainPlay');
    this.iconPlayState = document.getElementById('iconPlayState');
    this.wingAudioSpectrum = document.getElementById('wingAudioSpectrum');
    this.volumeTimer = null;

    this.initControls();
  }

  initControls() {
    // 音乐播放/暂停按钮交互
    if (this.btnMainPlay) {
      this.btnMainPlay.addEventListener('click', (e) => {
        e.stopPropagation();
        this.togglePlayback();
      });
    }
  }

  // 状态切换核心 (带流体物理动画与专属子状态控制)
  switchState(newState) {
    if (!this.notchIsland || this.currentState === newState) return;

    // 移除已有状态类
    const stateClasses = [
      `state-${STATE_EMPTY}`,
      `state-${STATE_WINGS}`,
      `state-${STATE_EXPANDED}`,
      `state-${STATE_SNEAK}`,
      `state-${STATE_VOLUME}`,
      `state-${STATE_CHARGING}`,
      `state-${STATE_SOCKET}`,
      `state-${STATE_SNAP}`,
      `state-${STATE_HUD}`
    ];
    this.notchIsland.classList.remove(...stateClasses);
    this.macbookMockup?.classList.remove(...stateClasses);

    // 赋予新状态
    this.currentState = newState;
    this.notchIsland.classList.add(`state-${newState}`);
    this.macbookMockup?.classList.add(`state-${newState}`);
    this.notchIsland.dataset.state = newState;

    // 动态调整背景光晕色彩
    if (this.glowHalo && STATE_GLOW_PALETTE[newState]) {
      this.glowHalo.style.background = STATE_GLOW_PALETTE[newState];
    }

    // 音量 HUD 状态启动动态调节动画，其他状态停止
    if (newState === STATE_VOLUME || newState === STATE_HUD) {
      this.startVolumeAnimation();
    } else {
      this.stopVolumeAnimation();
    }
  }

  // 点击标签时平滑滚动右侧对应卡片
  scrollToMatchingStory(state) {
    const targetCard = document.querySelector(`.feature-story-card[data-trigger-state="${state}"]`);
    if (targetCard) {
      targetCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  // 播放与暂停切换
  togglePlayback() {
    this.isMusicPlaying = !this.isMusicPlaying;

    if (this.isMusicPlaying) {
      this.iconPlayState.innerHTML = `
        <rect x="6" y="4" width="4" height="16" rx="1.5"></rect>
        <rect x="14" y="4" width="4" height="16" rx="1.5"></rect>
      `;
      if (this.wingAudioSpectrum) {
        this.wingAudioSpectrum.style.opacity = '1';
      }
    } else {
      this.iconPlayState.innerHTML = `
        <polygon points="7,4 20,12 7,20"></polygon>
      `;
      if (this.wingAudioSpectrum) {
        this.wingAudioSpectrum.style.opacity = '0.3';
      }
    }
  }

  // 启动音量 HUD 连续线性平滑调节动画 (Continuous Linear Smooth Animation)
  startVolumeAnimation() {
    this.stopVolumeAnimation();

    const hudFillMask = document.getElementById('hudFillMask');
    const hudPctLabel = document.getElementById('hudPctLabel');
    const hudPctLabelDark = document.getElementById('hudPctLabelDark');
    if (!hudFillMask || !hudPctLabel || !hudPctLabelDark) return;

    let currentVolume = 28.0;
    let targetVolume = 85.0;
    let direction = 1;
    let holdDuration = 0;
    let lastTime = performance.now();

    const updateVolumeUI = (val) => {
      hudFillMask.style.width = `${val.toFixed(1)}%`;
      const roundVal = Math.round(val);
      hudPctLabel.textContent = `${roundVal}%`;
      hudPctLabelDark.textContent = `${roundVal}%`;
    };

    updateVolumeUI(currentVolume);

    const animateLoop = (now) => {
      if (this.currentState !== STATE_VOLUME && this.currentState !== STATE_HUD) {
        this.stopVolumeAnimation();
        return;
      }

      const deltaTime = Math.min(50, now - lastTime) / 1000;
      lastTime = now;

      if (holdDuration > 0) {
        holdDuration -= deltaTime;
      } else {
        const speed = direction > 0 ? 36 : 30; // 每秒变化百分比，线性无级平滑
        currentVolume += direction * speed * deltaTime;

        if (direction > 0 && currentVolume >= targetVolume) {
          currentVolume = targetVolume;
          direction = -1;
          targetVolume = 30.0;
          holdDuration = 0.85; // 峰值停留
        } else if (direction < 0 && currentVolume <= targetVolume) {
          currentVolume = targetVolume;
          direction = 1;
          targetVolume = 85.0;
          holdDuration = 0.65; // 低值停留
        }

        updateVolumeUI(currentVolume);
      }

      this.volumeRafId = requestAnimationFrame(animateLoop);
    };

    this.volumeRafId = requestAnimationFrame(animateLoop);
  }

  // 停止音量调节动画
  stopVolumeAnimation() {
    if (this.volumeRafId) {
      cancelAnimationFrame(this.volumeRafId);
      this.volumeRafId = null;
    }
  }
}

/**
 * 实时滚动联动引擎 (Realtime Spatial Proximity Engine)
 * 1. 首页居中展示“巨大的半个屏幕特写”，伴随滚动平滑缩放滑向左侧固定演播台
 * 2. 右侧 7 大功能卡片实时驱动左侧刘海流体形态切换
 */
class ScrollSyncEngine {
  constructor(notchCtrl) {
    this.notchCtrl = notchCtrl;
    this.storyCards = Array.from(document.querySelectorAll('.feature-story-card'));
    this.heroSection = document.getElementById('hero');
    this.heroContent = document.querySelector('.hero-content');
    this.siteHeader = document.getElementById('siteHeader');
    this.syncStatusLabel = document.getElementById('syncStatusLabel');
    this.macbookMockup = document.getElementById('macbookMockup');
    this.stickyCol = document.querySelector('.stage-sticky-col');
    this.storyScrollCol = document.getElementById('storyScrollCol');
    this.heroRevealStage = document.getElementById('heroNotchRevealStage');
    this.showcase = document.getElementById('showcase');
    this.reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    this.isTicking = false;

    this.initListeners();
  }

  initListeners() {
    window.addEventListener('scroll', () => {
      if (!this.isTicking) {
        requestAnimationFrame(() => {
          this.handleScroll();
          this.isTicking = false;
        });
        this.isTicking = true;
      }
    }, { passive: true });

    window.addEventListener('resize', () => {
      this.handleScroll();
    }, { passive: true });

    // 初始执行一次校准
    this.handleScroll();
  }

  // 首屏轮廓随滚动缩入演示屏幕；目标位置始终从实际布局读取，避免断点和窗口缩放错位。
  updateSpatialMotion(scrollY) {
    if (!this.heroSection || !this.heroRevealStage || !this.macbookMockup) return;

    const heroHeight = this.heroSection.offsetHeight;
    const start = Math.min(heroHeight * 0.18, 170);
    const end = Math.max(start + 1, heroHeight - window.innerHeight * 0.12);
    const progress = Math.min(1, Math.max(0, (scrollY - start) / (end - start)));
    const smoothT = progress * progress * (3 - 2 * progress);
    const target = this.macbookMockup.getBoundingClientRect();
    const hero = this.heroSection.getBoundingClientRect();
    const stageWidth = this.heroRevealStage.offsetWidth;
    const stageHeight = this.heroRevealStage.offsetHeight;
    const stageLeft = hero.left + this.heroRevealStage.offsetLeft;
    const stageTop = hero.top + this.heroRevealStage.offsetTop;

    if (this.reduceMotion.matches) {
      this.heroRevealStage.style.transform = 'none';
      this.heroRevealStage.style.opacity = progress < 0.5 ? '1' : '0';
      this.macbookMockup.style.opacity = progress < 0.5 ? '0' : '1';
    } else {
      const dx = target.left - stageLeft;
      const dy = target.top - stageTop;
      const scaleX = target.width / stageWidth;
      const scaleY = target.height / stageHeight;
      this.heroRevealStage.style.transform = `translate3d(${(dx * smoothT).toFixed(1)}px, ${(dy * smoothT).toFixed(1)}px, 0) scale(${(1 + (scaleX - 1) * smoothT).toFixed(4)}, ${(1 + (scaleY - 1) * smoothT).toFixed(4)})`;
      this.heroRevealStage.style.opacity = `${Math.min(1, Math.max(0, (1 - progress) / 0.23)).toFixed(3)}`;
      this.macbookMockup.style.opacity = `${Math.min(1, Math.max(0, (progress - 0.67) / 0.33)).toFixed(3)}`;
    }

    if (this.heroContent) {
      this.heroContent.style.opacity = `${Math.max(0, 1 - progress * 1.6).toFixed(2)}`;
      this.heroContent.style.transform = this.reduceMotion.matches ? 'none' : `translateY(-${(progress * 40).toFixed(1)}px)`;
    }

    if (this.storyScrollCol) {
      this.storyScrollCol.style.opacity = `${Math.min(1, Math.max(0, (progress - 0.55) / 0.45)).toFixed(2)}`;
      this.storyScrollCol.style.transform = this.reduceMotion.matches ? 'none' : `translateY(${((1 - smoothT) * 45).toFixed(1)}px)`;
    }
  }

  handleScroll() {
    const scrollY = window.scrollY;

    // 1. 顶部导航栏毛玻璃模糊加深
    if (scrollY > 30) {
      this.siteHeader?.classList.add('scrolled');
    } else {
      this.siteHeader?.classList.remove('scrolled');
    }

    // 2. 执行从首屏居中巨幅半屏向左侧演播台平滑滑动的空间动效
    this.updateSpatialMotion(scrollY);

    // 3. 在首屏尚未完成位移时，维持原生空刘海
    if (this.showcase && this.showcase.getBoundingClientRect().top > window.innerHeight * 0.55) {
      this.notchCtrl.switchState(STATE_EMPTY);
      this.storyCards.forEach(c => {
        if (c.dataset.triggerState === STATE_EMPTY) {
          c.classList.add('active-card');
        } else {
          c.classList.remove('active-card');
        }
      });
      if (this.syncStatusLabel) {
        const isEn = document.documentElement.lang === 'en';
        this.syncStatusLabel.textContent = isEn ? 'Native Idle Notch' : '原生静默空刘海';
      }
      return;
    }

    // 4. 实时计算所有右侧卡片与视口中线的几何距离
    const viewportCenterY = window.innerHeight * 0.5;
    let closestCard = null;
    let minDistance = Infinity;

    for (const card of this.storyCards) {
      const rect = card.getBoundingClientRect();
      const cardCenterY = rect.top + rect.height * 0.5;
      const distance = Math.abs(cardCenterY - viewportCenterY);

      if (distance < minDistance) {
        minDistance = distance;
        closestCard = card;
      }
    }

    // 5. 驱动左侧刘海切换并高亮当前卡片
    if (closestCard) {
      const targetState = closestCard.dataset.triggerState;
      if (targetState) {
        this.notchCtrl.switchState(targetState);

        // 更新右侧卡片高亮指示
        this.storyCards.forEach(c => {
          if (c === closestCard) {
            c.classList.add('active-card');
          } else {
            c.classList.remove('active-card');
          }
        });

        // 状态文字反馈 (双语支持)
        if (this.syncStatusLabel) {
          const isEn = document.documentElement.lang === 'en';
          const categoryName = closestCard.querySelector('.story-category')?.textContent || '';
          this.syncStatusLabel.textContent = isEn ? `Synced: ${categoryName}` : `已联动: ${categoryName}`;
        }
      }
    }
  }
}

// 模拟桌面时钟走字
function initDesktopClock() {
  const clockEl = document.getElementById('desktopClock');
  if (!clockEl) return;

  function refreshTime() {
    const now = new Date();
    const h = String(now.getHours()).padStart(2, '0');
    const m = String(now.getMinutes()).padStart(2, '0');
    clockEl.textContent = `${h}:${m}`;
  }

  refreshTime();
  setInterval(refreshTime, 1000 * 30);
}

// 初始化
document.addEventListener('DOMContentLoaded', () => {
  const notchCtrl = new NotchController();
  new ScrollSyncEngine(notchCtrl);
  initDesktopClock();
});
