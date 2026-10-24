/**
 * 漫画阅读器：还原原版 comic_reader_layout 设计
 * - 图片纵向滚动（List + Scroller）
 * - 底部控制栏：上一话 / 章节内图片进度滑杆 / 下一话 + 图片位置指示 + 目录 + 自动阅读
 * - 右侧章节目录抽屉（原版 DrawerLayout END + rvChapter），当前章节高亮并自动定位
 * - 进入阅读器先显示控制栏 3 秒后自动隐藏（原版 entryChrome 行为）
 * 数据源：App API（comic/episode/images/{episodeId}）
 */
import {
  ComicEpisode, ComicEpisodeImage, ComicReaderParam, ComicParam, COMIC_BOOK_URL_PREFIX,
  parseEpisodeImages, parseEpisodeList, CACHE_PREFIX_EPS, CACHE_PREFIX_IMGS,
  imagesFresh, episodesFresh
} from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { Book } from '../model/BookModels';
import { StorageKeys } from '../model/ReadConfigModels';
import { Db } from '../service/Db';
import {
  BaseGestureHandlingProposal, GestureHandlingResolution, SmartGestureController
} from '@kit.ArkUI';

const ENTRY_CHROME_HINT_MS: number = 3000;
const AUTO_SCROLL_TICK_MS: number = 16;
const AUTO_SCROLL_BASE_PX: number = 2;
/** 默认页面宽高比（宽/高）：未解码前的占位比例，典型漫画单页 */
const DEFAULT_PAGE_W_RATIO: number = 0.69;

@Observed
class ReaderPageImage {
  url: string;
  key: string;
  /** 解码后的真实宽高比（宽/高），0 = 未解码 */
  ratio: number = 0;

  constructor(url: string, key: string) {
    this.url = url;
    this.key = key;
  }
}

/**
 * 单页图片：解码前按占位宽高比预留高度（无黑屏、恢复定位可用），
 * onComplete 后切换为真实宽高比，高度与图片完全贴合、无黑边
 */
@Component
struct ReaderImageItem {
  @ObjectLink img: ReaderPageImage;
  @Prop placeholderWRatio: number;
  onImageRatio: (ratio: number) => void = (ratio: number) => {
  };

  build() {
    Image(this.img.url)
      .width('100%')
      .objectFit(ImageFit.Contain)
      .aspectRatio(this.img.ratio > 0 ? this.img.ratio : this.placeholderWRatio)
      .backgroundColor('#2E2E33')
      .onComplete((event) => {
        if (event && event.width > 0 && event.height > 0 && this.img.ratio <= 0) {
          const r: number = event.width / event.height;
          this.img.ratio = r;
          this.onImageRatio(r);
        }
      })
  }
}

@Component
struct ComicReaderPage {
  param: ComicReaderParam = new ComicReaderParam();
  @State episodes: ComicEpisode[] = [];
  @State currentIndex: number = 0;
  @State images: ReaderPageImage[] = [];
  @State loading: boolean = true;
  @State failedMsg: string = '';
  @State chromeVisible: boolean = false;
  /** 当前可见图片索引（滑杆/指示器） */
  @State seekValue: number = 0;
  /** 未解码页面的占位宽高比（宽/高），随首图解码结果自适应（条漫/横幅） */
  @State placeholderWRatio: number = DEFAULT_PAGE_W_RATIO;
  /** 章节目录抽屉 */
  @State drawerOpen: boolean = false;
  /** 目录排序：true 正序，false 倒序 */
  @State drawerAscending: boolean = true;
  /** 自动阅读 */
  @State autoScrolling: boolean = false;
  @State autoSheetVisible: boolean = false;
  @State autoSpeed: number = 1.0;
  navPathStack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  drawerScroller: Scroller = new Scroller();
  private scrolledForEpisode: boolean = false;
  private entryHintShown: boolean = false;
  private autoTimer: number = -1;
  private restoreTimer: number = -1;
  /** 恢复定位目标页；>=0 表示恢复中，屏蔽更小的滚动索引 */
  private restoreTarget: number = -1;
  /** 续读起始页（首个章节恢复用） */
  private pendingStartPage: number = 0;
  private startPageUsed: boolean = false;
  private lastProgressSaveAt: number = 0;
  /** 状态栏/手势条避让高度（vp），由 EntryAbility 全局全屏后发布，随避让区变化刷新 */
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;
  @StorageProp(StorageKeys.SAFE_AREA_BOTTOM_VP) navBarVp: number = 24;
  /** 智慧手势（眼动/敲一敲/划一划翻页）控制器 */
  private smartGesture: SmartGestureController | undefined = undefined;
  /** 智慧手势监听：阅读器可交互时消费手势，沿用系统默认翻页动作 */
  private smartGestureMonitor =
    (proposal: BaseGestureHandlingProposal): GestureHandlingResolution => {
      if (this.loading || this.failedMsg !== '' || this.drawerOpen || this.images.length === 0) {
        return new GestureHandlingResolution(false);
      }
      return new GestureHandlingResolution(true);
    };

  currentEpisode(): ComicEpisode {
    if (this.currentIndex >= 0 && this.currentIndex < this.episodes.length) {
      return this.episodes[this.currentIndex];
    }
    return new ComicEpisode();
  }

  /**
   * 书架直进时自取章节目录：新鲜缓存直接用（不发请求），过期/缺失才网络拉取
   */
  loadEpisodes(): void {
    this.loading = true;
    this.failedMsg = '';
    const key: string = CACHE_PREFIX_EPS + this.param.comicId;
    const db: Db = Db.getInstance();
    db.getCache(key).then((raw: string) => {
      if (raw !== '' && this.episodes.length === 0) {
        const eps: ComicEpisode[] = parseEpisodeList(raw);
        this.applyEpisodes(eps);
        this.loadEpisode();
        if (episodesFresh(eps)) {
          return;
        }
      }
      this.refreshEpisodeList(key, db);
    }).catch(() => {
      this.refreshEpisodeList(key, db);
    });
  }

  /**
   * 网络拉取章节目录（缓存未命中直出，命中则后台刷新保持阅读位置）
   */
  refreshEpisodeList(key: string, db: Db): void {
    ComicApi.getInstance().getEpisodeListRaw(this.param.comicId).then((raw: string) => {
      db.setCache(key, raw).catch(() => {
      });
      const eps: ComicEpisode[] = parseEpisodeList(raw);
      if (this.episodes.length === 0) {
        this.applyEpisodes(eps);
        this.loadEpisode();
      } else {
        this.refreshEpisodesInBackground(eps);
      }
    }).catch((e: Error) => {
      if (this.episodes.length === 0) {
        this.failedMsg = e.message;
        this.loading = false;
      }
    });
  }

  applyEpisodes(eps: ComicEpisode[]): void {
    eps.sort((a: ComicEpisode, b: ComicEpisode): number => a.episodeNum - b.episodeNum);
    this.episodes = eps;
    this.markTocSeen(eps.length);
    let idx: number = this.param.startIndex;
    if (idx < 0 || idx >= eps.length) {
      idx = 0;
    }
    this.currentIndex = idx;
  }

  /**
   * 后台目录刷新后，按当前章节 episodeId 保持阅读位置
   */
  refreshEpisodesInBackground(eps: ComicEpisode[]): void {
    const currentId: string = this.currentEpisode().episodeId;
    eps.sort((a: ComicEpisode, b: ComicEpisode): number => a.episodeNum - b.episodeNum);
    let idx: number = 0;
    for (let i = 0; i < eps.length; i++) {
      if (eps[i].episodeId === currentId) {
        idx = i;
        break;
      }
    }
    this.episodes = eps;
    this.currentIndex = idx;
    this.markTocSeen(eps.length);
  }

  /**
   * 查看目录即确认更新：回写已确认目录数，仅在变化时刷新书架，清除/更新角标
   */
  markTocSeen(count: number): void {
    const url: string = COMIC_BOOK_URL_PREFIX + this.param.comicId;
    const db: Db = Db.getInstance();
    db.getBook(url).then((saved: Book | null) => {
      if (saved === null || saved.seenTocCount >= count) {
        return;
      }
      return db.updateSeenTocCount(url, count).then(() => {
        AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
          (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      });
    }).catch(() => {
    });
  }

  /**
   * 章节图片：新鲜缓存直接渲染（不轮换 URL 不触发整章重载），过期/缺失才网络刷新
   */
  loadEpisode(): void {
    const ep: ComicEpisode = this.currentEpisode();
    if (ep.episodeId === '') {
      this.loading = false;
      this.failedMsg = '章节不存在';
      return;
    }
    this.failedMsg = '';
    this.images = [];
    this.seekValue = 0;
    this.scrolledForEpisode = false;
    this.loading = true;
    const key: string = CACHE_PREFIX_IMGS + ep.episodeId;
    const db: Db = Db.getInstance();
    db.getCache(key).then((raw: string) => {
      if (raw !== '' && this.images.length === 0) {
        const imgs: ComicEpisodeImage[] = parseEpisodeImages(raw);
        if (imgs.length > 0) {
          this.applyImages(imgs);
          if (imagesFresh(imgs)) {
            this.prefetchNext();
            return;
          }
        }
      }
      this.refreshEpisodeImages(key, db);
    }).catch(() => {
      this.refreshEpisodeImages(key, db);
    });
  }

  /**
   * 网络刷新当前章节图片并预取下一话
   */
  refreshEpisodeImages(key: string, db: Db): void {
    ComicApi.getInstance().getEpisodeImagesRaw(this.currentEpisode().episodeId).then((raw: string) => {
      db.setCache(key, raw).catch(() => {
      });
      this.applyImages(parseEpisodeImages(raw));
      this.prefetchNext();
    }).catch((e: Error) => {
      if (this.images.length === 0) {
        this.failedMsg = e.message;
        this.loading = false;
      }
    });
  }

  applyImages(imgs: ComicEpisodeImage[]): void {
    this.images = this.toReaderPages(imgs);
    this.loading = false;
    this.seekValue = 0;
    if (imgs.length === 0) {
      // 避免静默渲染空 List 导致黑屏
      this.failedMsg = '本章节暂无图片';
      return;
    }
    // 原版行为：首次进入显示控制栏 3 秒后自动隐藏
    if (!this.entryHintShown) {
      this.entryHintShown = true;
      this.chromeVisible = true;
      setTimeout(() => {
        this.chromeVisible = false;
      }, ENTRY_CHROME_HINT_MS);
    }
    if (!this.scrolledForEpisode) {
      this.scrolledForEpisode = true;
      // 首个章节恢复到续读页，后续切章回到章首
      let target: number = 0;
      if (!this.startPageUsed) {
        this.startPageUsed = true;
        target = this.pendingStartPage;
        if (target < 0 || target >= imgs.length) {
          target = 0;
        }
      }
      this.seekValue = target;
      if (target > 0) {
        this.restoreTarget = target;
        this.restoreScroll(target);
      } else {
        this.scroller.scrollToIndex(0, false);
      }
    }
    this.updateShelfProgress();
  }

  toReaderPages(imgs: ComicEpisodeImage[]): ReaderPageImage[] {
    const pages: ReaderPageImage[] = [];
    for (let i = 0; i < imgs.length; i++) {
      const img: ComicEpisodeImage = imgs[i];
      pages.push(new ReaderPageImage(img.imageUrl, img.imageId + '_' + img.imageIndex));
    }
    return pages;
  }

  /**
   * 首图解码后自适应占位比例：偏差超过 15% 才更新（条漫/横幅页），
   * 避免占位高度频繁抖动
   */
  updatePlaceholderRatio(r: number): void {
    if (Math.abs(r - this.placeholderWRatio) / this.placeholderWRatio > 0.15) {
      this.placeholderWRatio = r;
    }
  }

  /**
   * 恢复到续读页：图片解码前列表高度为 0，scrollToIndex 可能落空，
   * 周期重试直到目标页成为首可见项或超时
   */
  restoreScroll(target: number): void {
    this.clearRestoreTimer();
    let attempts: number = 0;
    this.restoreTimer = setInterval(() => {
      attempts += 1;
      this.scroller.scrollToIndex(target, false);
      if (this.seekValue >= target || attempts >= 20) {
        this.clearRestoreTimer();
        this.restoreTarget = -1;
      }
    }, 100);
  }

  clearRestoreTimer(): void {
    if (this.restoreTimer >= 0) {
      clearInterval(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  /**
   * 预取下一话图片列表（填充缓存，切话秒开）
   */
  prefetchNext(): void {
    const next: number = this.currentIndex + 1;
    if (next < 0 || next >= this.episodes.length) {
      return;
    }
    const nextEp: ComicEpisode = this.episodes[next];
    if (nextEp.episodeId === '') {
      return;
    }
    const key: string = CACHE_PREFIX_IMGS + nextEp.episodeId;
    const db: Db = Db.getInstance();
    db.getCache(key).then((raw: string) => {
      if (raw !== '') {
        return;
      }
      return ComicApi.getInstance().getEpisodeImagesRaw(nextEp.episodeId).then((fresh: string) => {
        db.setCache(key, fresh).catch(() => {
        });
      });
    }).catch(() => {
    });
  }

  /**
   * 若漫画已在书架，把当前章节+页进度回写（durChapterIndex/durChapterTitle/durChapterPos）；
   * 进度无变化时跳过，避免滚动中反复触发书架刷新
   */
  updateShelfProgress(): void {
    const url: string = COMIC_BOOK_URL_PREFIX + this.param.comicId;
    const db: Db = Db.getInstance();
    db.getBook(url).then((saved: Book | null) => {
      if (saved === null) {
        return;
      }
      const title: string = this.currentEpisode().name;
      if (saved.durChapterIndex === this.currentIndex && saved.durChapterTitle === title &&
        saved.durChapterPos === this.seekValue) {
        return;
      }
      return db.updateBookProgress(url, this.currentIndex, title, this.seekValue).then(() => {
        AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
          (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      });
    }).catch(() => {
    });
  }

  /**
   * 滚动中节流回写页进度（最快 1.5 秒一次）
   */
  saveProgressThrottled(): void {
    const now: number = Date.now();
    if (now - this.lastProgressSaveAt < 1500) {
      return;
    }
    this.lastProgressSaveAt = now;
    this.updateShelfProgress();
  }

  switchEpisode(delta: number): void {
    const next: number = this.currentIndex + delta;
    if (next < 0) {
      this.getUIContext().getPromptAction().showToast({ message: '已经是第一话' });
      return;
    }
    if (next >= this.episodes.length) {
      this.getUIContext().getPromptAction().showToast({ message: '已经是最后一话' });
      return;
    }
    this.selectEpisode(next);
  }

  selectEpisode(index: number): void {
    this.currentIndex = index;
    this.loadEpisode();
  }

  openDrawer(): void {
    this.drawerOpen = true;
    // 等抽屉挂载后定位到当前章节（倒序时列表位置镜像）
    setTimeout(() => {
      const target: number = this.drawerAscending
        ? this.currentIndex
        : this.episodes.length - 1 - this.currentIndex;
      this.drawerScroller.scrollToIndex(target, false);
    }, 80);
  }

  /** 目录展示序列：正序原样，倒序反转 */
  drawerEpisodes(): ComicEpisode[] {
    const copy: ComicEpisode[] = this.episodes.slice();
    if (!this.drawerAscending) {
      copy.reverse();
    }
    return copy;
  }

  toggleDrawerSort(): void {
    this.drawerAscending = !this.drawerAscending;
    // 等列表重建后重新定位到当前章节
    setTimeout(() => {
      const target: number = this.drawerAscending
        ? this.currentIndex
        : this.episodes.length - 1 - this.currentIndex;
      this.drawerScroller.scrollToIndex(target, false);
    }, 80);
  }

  /** 按 episodeId 反查正序索引 */
  episodeIndexOf(ep: ComicEpisode): number {
    for (let i = 0; i < this.episodes.length; i++) {
      if (this.episodes[i].episodeId === ep.episodeId) {
        return i;
      }
    }
    return 0;
  }

  closeDrawer(): void {
    this.drawerOpen = false;
  }

  toggleAutoScroll(): void {
    if (this.autoScrolling) {
      this.stopAutoScroll();
    } else {
      this.startAutoScroll();
    }
  }

  startAutoScroll(): void {
    if (this.autoScrolling || this.images.length === 0) {
      return;
    }
    this.autoScrolling = true;
    this.chromeVisible = false;
    this.autoTimer = setInterval(() => {
      this.scroller.scrollBy(0, AUTO_SCROLL_BASE_PX * this.autoSpeed);
      if (this.seekValue >= this.images.length - 1) {
        this.stopAutoScroll();
        this.getUIContext().getPromptAction().showToast({ message: '已到本章末尾' });
      }
    }, AUTO_SCROLL_TICK_MS);
  }

  stopAutoScroll(): void {
    if (this.autoTimer >= 0) {
      clearInterval(this.autoTimer);
      this.autoTimer = -1;
    }
    this.autoScrolling = false;
  }

  aboutToAppear(): void {
    // 接入系统智慧手势（眼动翻页/敲一敲/划一划），需系统侧开启对应手势开关
    const controller: SmartGestureController = this.getUIContext().getSmartGestureController();
    this.smartGesture = controller;
    controller.enableSmartTapAndSlideGestures(true);
    controller.registerMonitor(this.smartGestureMonitor);
  }

  aboutToDisappear(): void {
    this.smartGesture?.unregisterMonitor(this.smartGestureMonitor);
    this.smartGesture?.enableSmartTapAndSlideGestures(false);
    this.smartGesture = undefined;
    this.stopAutoScroll();
    this.clearRestoreTimer();
    // 退出时兜底保存当前页进度（覆盖节流窗口内的最后位置）
    this.updateShelfProgress();
  }

  sliderMax(): number {
    return this.images.length > 0 ? this.images.length - 1 : 1;
  }

  progressText(): string {
    return (this.seekValue + 1) + ' / ' + this.images.length;
  }

  episodeLabel(ep: ComicEpisode): string {
    if (ep.name !== '') {
      return ep.name;
    }
    return '第' + ep.episodeNum + '话';
  }

  /** 顶栏「详情」：跳转漫画详情页（可查看信息/管理书架收藏） */
  openDetail(): void {
    const p: ComicParam = new ComicParam();
    p.comicId = this.param.comicId;
    p.comicName = this.param.comicName;
    p.picUrl = '';
    this.navPathStack.pushPathByName('comicDetail', p);
  }

  @Builder
  topBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor(['#FFFFFF'])
        .onClick(() => {
          this.navPathStack.pop();
        })
      Column({ space: 1 }) {
        Text(this.param.comicName)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        Text(this.currentEpisode().name)
          .fontSize(11)
          .fontColor('#CCFFFFFF')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.autoScrolling) {
        Text(this.autoSpeed.toFixed(1) + 'x')
          .fontSize(11)
          .fontColor('#FFFFFF')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#665959FF')
          .borderRadius(12)
          .onClick(() => {
            this.stopAutoScroll();
          })
      }
      Text('详情')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.openDetail();
        })
    }
    .width('100%')
    .padding({ top: this.statusBarVp + 6, bottom: 10, left: 14, right: 14 })
    .backgroundColor('#99000000')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 底部控制栏（还原原版 clBottomContent）：
   * 上一话 | 图片进度滑杆 | 下一话 + 目录/自动阅读/位置指示
   */
  @Builder
  bottomBar() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text('上一话')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#66000000')
          .borderRadius(16)
          .onClick(() => {
            this.switchEpisode(-1);
          })
        Slider({
          value: this.seekValue,
          min: 0,
          max: this.sliderMax(),
          step: 1,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .height(28)
          .blockColor('#FFFFFF')
          .trackColor('#33FFFFFF')
          .selectedColor('#6C5CE7')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.scroller.scrollToIndex(value, true);
            }
          })
        Text('下一话')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#665959FF')
          .borderRadius(16)
          .onClick(() => {
            this.switchEpisode(1);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 18 }) {
        Text('目录')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.openDrawer();
          })
        Text('自动阅读')
          .fontSize(13)
          .fontColor(this.autoScrolling ? '#A08CFF' : '#FFFFFF')
          .onClick(() => {
            this.autoSheetVisible = true;
          })
        Blank()
        Text(this.progressText())
          .fontSize(12)
          .fontColor('#CCFFFFFF')
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: Math.max(this.navBarVp + 6, 28) })
    .backgroundColor('#99000000')
  }

  /**
   * 右侧章节目录抽屉（还原原版 DrawerLayout END + rvChapter）
   */
  @Builder
  chapterDrawer() {
    Column() {
      Row({ space: 8 }) {
        Text('目录')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#222222')
        Text('共 ' + this.episodes.length + ' 话')
          .fontSize(12)
          .fontColor('#999999')
        Blank()
        Text(this.drawerAscending ? '正序 ↓' : '倒序 ↑')
          .fontSize(12)
          .fontColor('#6C5CE7')
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#F0EDFF')
          .borderRadius(12)
          .onClick(() => {
            this.toggleDrawerSort();
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor(['#666666'])
          .onClick(() => {
            this.closeDrawer();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 12 })

      List({ scroller: this.drawerScroller, space: 0 }) {
        ForEach(this.drawerEpisodes(), (ep: ComicEpisode) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(this.episodeLabel(ep))
                .fontSize(14)
                .fontColor(this.episodeIndexOf(ep) === this.currentIndex ? '#6C5CE7' : '#333333')
                .fontWeight(this.episodeIndexOf(ep) === this.currentIndex ? FontWeight.Medium : FontWeight.Normal)
                .maxLines(1)
                .layoutWeight(1)
              if (this.episodeIndexOf(ep) === this.currentIndex) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(14)
                  .fontColor(['#6C5CE7'])
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.closeDrawer();
              const index: number = this.episodeIndexOf(ep);
              if (index !== this.currentIndex) {
                this.selectEpisode(index);
              }
            })
          }
        }, (ep: ComicEpisode): string => ep.episodeId + '_' + this.drawerAscending)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({
        strokeWidth: 0.5,
        color: '#F0F0F0',
        startMargin: 16,
        endMargin: 16
      })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('76%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .transition(TransitionEffect.translate({ x: 320 }).animation({ duration: 250, curve: Curve.Friction }))
  }

  /**
   * 自动阅读面板（还原原版 DialogC0839t：速度 %.1fx + 开启/停止自动滑动）
   */
  @Builder
  autoScrollPanel() {
    Column({ space: 18 }) {
      Text('自动阅读')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#222222')
        .width('100%')
      Row() {
        Text('滑动速度')
          .fontSize(14)
          .fontColor('#666666')
        Blank()
        Text(this.autoSpeed.toFixed(1) + 'x')
          .fontSize(14)
          .fontColor('#6C5CE7')
      }
      .width('100%')
      Slider({
        value: this.autoSpeed,
        min: 0.5,
        max: 3,
        step: 0.5,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor('#6C5CE7')
        .trackColor('#E5E5E5')
        .selectedColor('#6C5CE7')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.autoSpeed = value;
          }
        })
      Button(this.autoScrolling ? '停止自动滑动' : '开启自动滑动')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.autoScrolling ? '#888888' : '#6C5CE7')
        .onClick(() => {
          this.toggleAutoScroll();
          this.autoSheetVisible = false;
        })
    }
    .padding(24)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.End }) {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color('#FFFFFF')
            Text('正在加载...')
              .fontSize(13)
              .fontColor('#CCCCCC')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.failedMsg !== '') {
          Column({ space: 10 }) {
            Text('加载失败')
              .fontSize(15)
              .fontColor('#EEEEEE')
            Text(this.failedMsg)
              .fontSize(12)
              .fontColor('#999999')
              .maxLines(3)
            Text('重试')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .padding({ left: 22, right: 22, top: 8, bottom: 8 })
              .backgroundColor('#6C5CE7')
              .borderRadius(17)
              .margin({ top: 6 })
              .onClick(() => {
                this.loadEpisode();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller, space: 0 }) {
            ForEach(this.images, (img: ReaderPageImage) => {
              ListItem() {
                ReaderImageItem({
                  img: img,
                  placeholderWRatio: this.placeholderWRatio,
                  onImageRatio: (r: number) => {
                    this.updatePlaceholderRatio(r);
                  }
                })
              }
            }, (img: ReaderPageImage): string => img.key)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#222222')
          .smartGestureShortcut({ action: GestureShortcut.PRIMARY, enabled: true, selectable: false })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onTouch((event: TouchEvent) => {
            // 用户手动触摸时取消恢复定位重试，避免 scrollToIndex 与用户滚动冲突
            if (this.restoreTarget >= 0 && event.type === TouchType.Down) {
              this.clearRestoreTimer();
              this.restoreTarget = -1;
            }
          })
          .onClick(() => {
            this.chromeVisible = !this.chromeVisible;
          })
          .onScrollIndex((first: number, last: number) => {
            // 恢复定位期间屏蔽更小的中间态索引，避免滑杆先跳 0 再跳目标页
            if (this.restoreTarget >= 0 && first < this.restoreTarget) {
              return;
            }
            this.seekValue = first;
            this.saveProgressThrottled();
          })
          .onDidScroll((xOffset: number, yOffset: number) => {
            if (this.chromeVisible && (yOffset > 1 || yOffset < -1)) {
              this.chromeVisible = false;
            }
          })
        }
        if (this.chromeVisible || this.loading || this.failedMsg !== '') {
          Column() {
            this.topBar()
          }
          .width('100%')
          .position({ x: 0, y: 0 })
        }
        if (this.chromeVisible && !this.loading && this.failedMsg === '') {
          Column() {
            this.bottomBar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .markAnchor({ x: 0, y: '100%' })
        }
        // 章节目录抽屉：遮罩 + 右侧面板
        if (this.drawerOpen) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .transition(TransitionEffect.opacity(0).animation({ duration: 250 }))
            .onClick(() => {
              this.closeDrawer();
            })
          this.chapterDrawer()
        }
        // 自动阅读中悬浮速度按钮（顶栏隐藏时也可停止）
        if (this.autoScrolling && !this.chromeVisible) {
          Text(this.autoSpeed.toFixed(1) + 'x')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor('#995959FF')
            .borderRadius(14)
            .margin(16)
            .onClick(() => {
              this.stopAutoScroll();
            })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#222222')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.autoSheetVisible, this.autoScrollPanel(), {
        height: 280,
        dragBar: true,
        showClose: true
      })
    }
    .hideTitleBar(true)
    .backgroundColor('#222222')
    .onBackPressed(() => {
      if (this.drawerOpen) {
        this.closeDrawer();
        return true;
      }
      return false;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ComicReaderParam = ctx.pathInfo.param as ComicReaderParam;
      if (p instanceof ComicReaderParam) {
        this.param = p;
        this.episodes = p.episodes;
        this.currentIndex = p.startIndex;
        this.pendingStartPage = p.startPage;
        if (this.episodes.length > 0) {
          this.loadEpisode();
        } else {
          this.loadEpisodes();
        }
      }
    })
  }
}

@Builder
export function ComicReaderPageBuilder() {
  ComicReaderPage()
}
