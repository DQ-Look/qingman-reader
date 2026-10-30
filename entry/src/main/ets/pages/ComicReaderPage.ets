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
  BaseGestureHandlingProposal, GestureHandlingResolution, SmartGestureController, window
} from '@kit.ArkUI';

const ENTRY_CHROME_HINT_MS: number = 3000;
const AUTO_SCROLL_TICK_MS: number = 16;
const AUTO_SCROLL_BASE_PX: number = 2;
/** 默认页面宽高比（宽/高）：未解码前的占位比例，典型漫画单页 */
const DEFAULT_PAGE_W_RATIO: number = 0.69;
/** 单图加载失败自动恢复：滚动窗口时长与窗口内整章重拉次数上限 */
const IMAGE_RECOVER_WINDOW_MS: number = 60000;
const IMAGE_RECOVER_MAX: number = 3;
/** 无感接章：距已加载内容底部不足 N 页时预拼接下一话 */
const STITCH_AHEAD_PAGES: number = 4;

@Observed
class ReaderPageImage {
  url: string;
  key: string;
  /** 所属话在目录中的索引（无感接章跨话拼接用） */
  episodeIdx: number = 0;
  /** 解码后的真实宽高比（宽/高），0 = 未解码 */
  ratio: number = 0;

  constructor(url: string, key: string, episodeIdx: number) {
    this.url = url;
    this.key = key;
    this.episodeIdx = episodeIdx;
  }
}

/**
 * 阅读页列表数据源：配合 LazyForEach 按需构建/回收列表项，
 * 长链路无感接章（数十话连续拼接）时只保留视口附近的组件与解码位图，内存有界
 */
class ReaderPagesDataSource implements IDataSource {
  private pages: ReaderPageImage[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): ReaderPageImage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** 整表替换（进章/切章/键序变化时全量重建） */
  reloadAll(pages: ReaderPageImage[]): void {
    this.pages = pages;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 尾部追加已拼接的下一话，仅通知新增区间，视口内已建项不重建 */
  appendFrom(pages: ReaderPageImage[], startIndex: number): void {
    this.pages = pages;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener: DataChangeListener = this.listeners[i];
      for (let index = startIndex; index < pages.length; index++) {
        listener.onDataAdd(index);
      }
    }
  }

  /** 长度相同且首尾为同一对象视为原地刷新（URL 原地更新，无需重建列表项） */
  sameInPlace(pages: ReaderPageImage[]): boolean {
    if (this.pages.length === 0 || this.pages.length !== pages.length) {
      return false;
    }
    return this.pages[0] === pages[0] && this.pages[this.pages.length - 1] === pages[pages.length - 1];
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
  /** 列表宽度（px）：页高按整像素计算，相邻页边界落在像素网格上 */
  @Prop itemWidthPx: number;
  onImageRatio: (ratio: number) => void = (ratio: number) => {
  };
  onImageError: () => void = () => {
  };

  /** 页高取整像素（vp）：拼接处既无缝隙（黑线）也无叠压（压字） */
  pageHeightVp(): number {
    const ratio: number = this.img.ratio > 0 ? this.img.ratio : this.placeholderWRatio;
    if (ratio <= 0 || this.itemWidthPx <= 0) {
      return 0;
    }
    return px2vp(Math.max(1, Math.round(this.itemWidthPx / ratio)));
  }

  build() {
    if (this.itemWidthPx > 0) {
      Image(this.img.url)
        .width('100%')
        .height(this.pageHeightVp())
        // 解码后用 Fill 把位图铺满组件：消除 Contain 等比留白与像素取整缝隙（图片间黑线）
        .objectFit(this.img.ratio > 0 ? ImageFit.Fill : ImageFit.Contain)
        // 底色只在占位阶段显示；解码后透明，避免条漫拼接处出现色带
        .backgroundColor(this.img.ratio > 0 ? Color.Transparent : '#2E2E33')
        .onComplete((event) => {
          if (event && event.width > 0 && event.height > 0 && this.img.ratio <= 0) {
            const r: number = event.width / event.height;
            this.img.ratio = r;
            this.onImageRatio(r);
          }
        })
        .onError(() => {
          this.onImageError();
        })
    } else {
      Image(this.img.url)
        .width('100%')
        .objectFit(this.img.ratio > 0 ? ImageFit.Fill : ImageFit.Contain)
        .aspectRatio(this.img.ratio > 0 ? this.img.ratio : this.placeholderWRatio)
        .backgroundColor(this.img.ratio > 0 ? Color.Transparent : '#2E2E33')
        .onComplete((event) => {
          if (event && event.width > 0 && event.height > 0 && this.img.ratio <= 0) {
            const r: number = event.width / event.height;
            this.img.ratio = r;
            this.onImageRatio(r);
          }
        })
        .onError(() => {
          this.onImageError();
        })
    }
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
  /** 列表内容宽度（px）：页高按整像素对齐，拼接处无缝隙也无重叠 */
  @State readerWidthPx: number = 0;
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
  /** 阅读页列表数据源（LazyForEach 用），与 @State images 同步维护 */
  pagesDs: ReaderPagesDataSource = new ReaderPagesDataSource();
  drawerScroller: Scroller = new Scroller();
  /** 目录抽屉快速定位滑杆：显示序列索引 / 拖动激活态 / 列表区尺寸（气泡定位用） */
  @State drawerSliderIndex: number = 0;
  @State drawerSliderActive: boolean = false;
  drawerSliderAreaWidth: number = 0;
  drawerSliderAreaHeight: number = 0;
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
  /** 单图加载失败自动恢复：窗口起点、已恢复次数、恢复请求在途标记 */
  private recoverWindowAt: number = 0;
  private recoverCount: number = 0;
  private recoveringImages: boolean = false;
  /** 无感接章：当前首可见页全局索引 / 下一话拼接请求在途标记 */
  private firstVisible: number = 0;
  private stitchingNext: boolean = false;
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
    this.pagesDs.reloadAll(this.images);
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
          this.prefetchNext(this.currentIndex);
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
    // 请求期间可能已切章：按发起时的章节校验响应，避免错误写缓存/渲染错章
    const epId: string = this.currentEpisode().episodeId;
    ComicApi.getInstance().getEpisodeImagesRaw(epId).then((raw: string) => {
      if (this.currentEpisode().episodeId !== epId) {
        return;
      }
      db.setCache(key, raw).catch(() => {
      });
      this.applyImages(parseEpisodeImages(raw));
      this.prefetchNext(this.currentIndex);
    }).catch((e: Error) => {
      if (this.currentEpisode().episodeId !== epId) {
        return;
      }
      if (this.images.length === 0) {
        this.failedMsg = e.message;
        this.loading = false;
      }
    });
  }

  /**
   * 单图加载失败（URL 过期/网络抖动）自动恢复：
   * 整章重拉最新图片列表并原地合并 URL，无需退出重进即可自愈黑屏
   */
  recoverImages(): void {
    if (this.recoveringImages || this.loading || this.failedMsg !== '' || this.images.length === 0) {
      return;
    }
    const ep: ComicEpisode = this.currentEpisode();
    if (ep.episodeId === '') {
      return;
    }
    const now: number = Date.now();
    if (now - this.recoverWindowAt > IMAGE_RECOVER_WINDOW_MS) {
      this.recoverWindowAt = now;
      this.recoverCount = 0;
    }
    if (this.recoverCount >= IMAGE_RECOVER_MAX) {
      return;
    }
    this.recoverCount += 1;
    this.recoveringImages = true;
    const epId: string = ep.episodeId;
    const key: string = CACHE_PREFIX_IMGS + epId;
    ComicApi.getInstance().getEpisodeImagesRaw(epId).then((raw: string) => {
      if (this.currentEpisode().episodeId !== epId) {
        return;
      }
      Db.getInstance().setCache(key, raw).catch(() => {
      });
      this.applyImages(parseEpisodeImages(raw));
    }).catch(() => {
    }).finally(() => {
      this.recoveringImages = false;
    });
  }

  applyImages(imgs: ComicEpisodeImage[]): void {
    // 同章刷新时复用已有页对象并原地更新 URL：
    // ForEach 键不变会保留旧子组件，整体换新对象会导致新 URL 不生效（旧 URL 过期 → 整章黑屏）
    const isUpdate: boolean = this.images.length > 0;
    const prevCur: ReaderPageImage[] = [];
    const prevNext: ReaderPageImage[] = [];
    for (let i = 0; i < this.images.length; i++) {
      if (this.images[i].episodeIdx === this.currentIndex) {
        prevCur.push(this.images[i]);
      } else {
        prevNext.push(this.images[i]);
      }
    }
    const curPages: ReaderPageImage[] = this.toReaderPages(imgs, prevCur, this.currentIndex);
    // 无感接章：重拉/恢复当前话时，保留已拼接到下方的后续话
    this.images = curPages.concat(prevNext);
    // 原地刷新（同键同序、URL 原地更新）无需重建列表项；结构变化才整表刷新
    if (!this.pagesDs.sameInPlace(this.images)) {
      this.pagesDs.reloadAll(this.images);
    }
    this.loading = false;
    if (!isUpdate) {
      this.seekValue = 0;
    }
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

  toReaderPages(imgs: ComicEpisodeImage[], prev: ReaderPageImage[], episodeIdx: number): ReaderPageImage[] {
    const prevMap: Map<string, ReaderPageImage> = new Map();
    for (let i = 0; i < prev.length; i++) {
      prevMap.set(prev[i].key, prev[i]);
    }
    const pages: ReaderPageImage[] = [];
    for (let i = 0; i < imgs.length; i++) {
      const img: ComicEpisodeImage = imgs[i];
      const key: string = this.pageKey(episodeIdx, img);
      const reused: ReaderPageImage | undefined = prevMap.get(key);
      if (reused !== undefined) {
        // 原地改 URL：@ObjectLink 感知变化，Image 换源重载，已解码比例保留不抖动
        if (reused.url !== img.imageUrl) {
          reused.url = img.imageUrl;
        }
        pages.push(reused);
      } else {
        pages.push(new ReaderPageImage(img.imageUrl, key, episodeIdx));
      }
    }
    return pages;
  }

  /** 列表项键：带话索引前缀，跨话拼接时保持唯一 */
  pageKey(episodeIdx: number, img: ComicEpisodeImage): string {
    return episodeIdx + '_' + img.imageId + '_' + img.imageIndex;
  }

  /** 已拼接内容的最后一话索引（无内容返回 -1） */
  lastLoadedEpisodeIdx(): number {
    let last: number = -1;
    for (let i = 0; i < this.images.length; i++) {
      if (this.images[i].episodeIdx > last) {
        last = this.images[i].episodeIdx;
      }
    }
    return last;
  }

  /** 某话在已拼接列表中的起始全局索引 */
  offsetOfEpisode(idx: number): number {
    for (let i = 0; i < this.images.length; i++) {
      if (this.images[i].episodeIdx === idx) {
        return i;
      }
    }
    return 0;
  }

  /** 某话已加载页数 */
  episodePageCount(idx: number): number {
    let count: number = 0;
    for (let i = 0; i < this.images.length; i++) {
      if (this.images[i].episodeIdx === idx) {
        count += 1;
      }
    }
    return count;
  }

  isEpisodeLoaded(idx: number): boolean {
    return this.episodePageCount(idx) > 0;
  }

  /**
   * 无感接章：距已加载内容底部不足 STITCH_AHEAD_PAGES 页时，
   * 把下一话图片拼接到列表尾（缓存优先，缺失才拉网），滚动不停顿
   */
  maybeStitchNext(): void {
    if (this.stitchingNext || this.loading || this.failedMsg !== '' || this.images.length === 0) {
      return;
    }
    const nextIdx: number = this.lastLoadedEpisodeIdx() + 1;
    if (nextIdx <= 0 || nextIdx >= this.episodes.length) {
      return;
    }
    const ep: ComicEpisode = this.episodes[nextIdx];
    if (ep.episodeId === '') {
      return;
    }
    this.stitchingNext = true;
    const key: string = CACHE_PREFIX_IMGS + ep.episodeId;
    Db.getInstance().getCache(key).then((raw: string) => {
      if (raw !== '') {
        this.finishStitch(nextIdx, raw);
        return;
      }
      ComicApi.getInstance().getEpisodeImagesRaw(ep.episodeId).then((fresh: string) => {
        Db.getInstance().setCache(key, fresh).catch(() => {
        });
        this.finishStitch(nextIdx, fresh);
      }).catch(() => {
        this.stitchingNext = false;
      });
    }).catch(() => {
      this.stitchingNext = false;
    });
  }

  finishStitch(nextIdx: number, raw: string): void {
    this.stitchingNext = false;
    if (raw === '' || nextIdx !== this.lastLoadedEpisodeIdx() + 1) {
      return;
    }
    const imgs: ComicEpisodeImage[] = parseEpisodeImages(raw);
    if (imgs.length === 0) {
      return;
    }
    this.appendEpisode(nextIdx, imgs);
  }

  appendEpisode(idx: number, imgs: ComicEpisodeImage[]): void {
    const pages: ReaderPageImage[] = [];
    for (let i = 0; i < imgs.length; i++) {
      pages.push(new ReaderPageImage(imgs[i].imageUrl, this.pageKey(idx, imgs[i]), idx));
    }
    const start: number = this.images.length;
    this.images = this.images.concat(pages);
    this.pagesDs.appendFrom(this.images, start);
    this.prefetchNext(idx);
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
  prefetchNext(baseIdx: number): void {
    const next: number = baseIdx + 1;
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
    // 无感接章：目标话已拼接在列表内（上方基话或下方拼接话）时直接滚过去，不整章重载
    if (this.isEpisodeLoaded(next)) {
      this.scroller.scrollToIndex(this.offsetOfEpisode(next), true);
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
    // 等抽屉挂载后定位到当前章节；行未建完时首滚可能偏移，二次校正
    this.scrollDrawerToCurrent(80);
    this.scrollDrawerToCurrent(400);
  }

  scrollDrawerToCurrent(delay: number): void {
    setTimeout(() => {
      if (!this.drawerOpen) {
        return;
      }
      const target: number = this.drawerAscending
        ? this.currentIndex
        : this.episodes.length - 1 - this.currentIndex;
      this.drawerSliderIndex = target;
      this.drawerScroller.scrollToIndex(target, false);
    }, delay);
  }

  /** 目录展示序列：正序原样，倒序反转 */
  drawerEpisodes(): ComicEpisode[] {
    const copy: ComicEpisode[] = this.episodes.slice();
    if (!this.drawerAscending) {
      copy.reverse();
    }
    return copy;
  }

  /** 抽屉右缘快速定位滑杆：拖动 → 滚动列表到对应显示序列索引 */
  onDrawerSliderChange(value: number, mode: SliderChangeMode): void {
    const n: number = this.episodes.length;
    const idx: number = Math.min(Math.max(Math.round(value), 0), Math.max(n - 1, 0));
    this.drawerSliderIndex = idx;
    this.drawerSliderActive = mode !== SliderChangeMode.End;
    this.drawerScroller.scrollToIndex(idx, false);
  }

  /** 显示序列索引 → 章节（正序原样，倒序镜像），避免拖动时整表拷贝 */
  drawerEpisodeAt(displayIndex: number): ComicEpisode {
    const n: number = this.episodes.length;
    const i: number = this.drawerAscending ? displayIndex : n - 1 - displayIndex;
    if (i >= 0 && i < n) {
      return this.episodes[i];
    }
    return new ComicEpisode();
  }

  drawerSliderBubbleText(): string {
    const ep: ComicEpisode = this.drawerEpisodeAt(this.drawerSliderIndex);
    return '第' + ep.episodeNum + '话';
  }

  /** 气泡跟随滑块：上下各留边距，按比例折算并夹紧 */
  drawerBubbleY(): number {
    const max: number = Math.max(this.episodes.length - 1, 0);
    const fraction: number = max > 0 ? this.drawerSliderIndex / max : 0;
    const h: number = this.drawerSliderAreaHeight;
    const y: number = 14 + fraction * Math.max(h - 28, 0) - 14;
    return Math.min(Math.max(y, 0), Math.max(h - 30, 0));
  }

  /** 滑块手柄高度（vp） */
  private drawerThumbH(): number {
    return 44;
  }

  /** 滑块手柄中心 Y（相对轨道区） */
  private drawerThumbY(): number {
    const max: number = Math.max(this.episodes.length - 1, 0);
    const fraction: number = max > 0 ? this.drawerSliderIndex / max : 0;
    const h: number = this.drawerSliderAreaHeight;
    const thumbH: number = this.drawerThumbH();
    return fraction * Math.max(h - thumbH, 0);
  }

  /** 触摸轨道区 → 折算显示序列索引并滚动定位 */
  private drawerSliderFromTouch(y: number): void {
    const max: number = Math.max(this.episodes.length - 1, 0);
    const h: number = this.drawerSliderAreaHeight;
    const thumbH: number = this.drawerThumbH();
    const usable: number = Math.max(h - thumbH, 0);
    const frac: number = usable > 0 ? (y - thumbH / 2) / usable : 0;
    const idx: number = Math.min(Math.max(Math.round(frac * max), 0), max);
    this.drawerSliderIndex = idx;
    this.drawerSliderActive = true;
    this.drawerScroller.scrollToIndex(idx, false);
  }

  /** 可拖动的滑块（滚动条手柄）：细轨道 + 圆角手柄，拖动即滚动章节列表 */
  @Builder
  drawerSlider() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(3)
        .backgroundColor('#EDEDF2')
        .alignSelf(ItemAlign.Center)
      Column()
        .width(22)
        .height(this.drawerThumbH())
        .borderRadius(11)
        .backgroundColor(this.drawerSliderActive ? '#6C5CE7' : '#C9BEF0')
        .position({ x: 3, y: this.drawerThumbY() })
    }
    .width(28)
    .height('100%')
    .alignSelf(ItemAlign.End)
    .position({ x: this.drawerSliderAreaWidth - 28, y: 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.drawerSliderFromTouch(event.touches[0].y);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.drawerSliderActive = false;
      }
    })
  }

  toggleDrawerSort(): void {
    this.drawerAscending = !this.drawerAscending;
    // 等列表重建后重新定位到当前章节；二次校正见 openDrawer
    this.scrollDrawerToCurrent(80);
    this.scrollDrawerToCurrent(400);
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
      // 无感接章下自动阅读持续滚过已拼接的话，直到最后一话末页才停止
      if (this.seekValue >= this.episodePageCount(this.currentIndex) - 1 &&
        this.lastLoadedEpisodeIdx() >= this.episodes.length - 1) {
        this.stopAutoScroll();
        this.getUIContext().getPromptAction().showToast({ message: '已是最后一话' });
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
    this.setStatusBarVisible(false);
  }

  aboutToDisappear(): void {
    this.setStatusBarVisible(true);
    this.smartGesture?.unregisterMonitor(this.smartGestureMonitor);
    this.smartGesture?.enableSmartTapAndSlideGestures(false);
    this.smartGesture = undefined;
    this.stopAutoScroll();
    this.clearRestoreTimer();
    // 退出时兜底保存当前页进度（覆盖节流窗口内的最后位置）
    this.updateShelfProgress();
  }

  sliderMax(): number {
    const count: number = this.episodePageCount(this.currentIndex);
    return count > 0 ? count - 1 : 1;
  }

  /** 进入阅读器隐藏状态栏（通知图标等），退出恢复 */
  private setStatusBarVisible(visible: boolean): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        win.setSpecificSystemBarEnabled('status', visible).catch(() => {
        });
      }).catch(() => {
      });
    } catch (err) {
    }
  }

  progressText(): string {
    const count: number = this.episodePageCount(this.currentIndex);
    if (count <= 0) {
      return '';
    }
    return (this.seekValue + 1) + ' / ' + count;
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
    .padding({ top: Math.max(this.statusBarVp, 20) + 6, bottom: 10, left: 14, right: 14 })
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
            this.seekValue = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              const target: number = this.offsetOfEpisode(this.currentIndex) + value;
              // 近距离用动画平滑过渡；大幅跳页直接定位，
              // 避免动画滚动渲染整章路径导致长时间卡顿
              this.scroller.scrollToIndex(target, Math.abs(target - this.firstVisible) <= 3);
              this.saveProgressThrottled();
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
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
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
   * 右侧章节目录抽屉（单根 Stack：遮罩 + 右侧面板，与全章节弹窗同构）
   */
  @Builder
  chapterDrawer() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeDrawer();
        })
      Column() {
        Row({ space: 8 }) {
          Text('目录')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#222222')
          Text('共 ' + this.episodes.length + ' 话')
            .fontSize(12)
            .fontColor('#999999')
            .layoutWeight(1)
          Text(this.drawerAscending ? '正序 ↓' : '倒序 ↑')
            .fontSize(12)
            .fontColor('#6C5CE7')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#F0EDFF')
            .borderRadius(12)
            .onClick(() => {
              this.toggleDrawerSort();
            })
          Text('×')
            .fontSize(18)
            .fontColor('#666666')
            .onClick(() => {
              this.closeDrawer();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 12 })

        Stack({ alignContent: Alignment.End }) {
          List({ scroller: this.drawerScroller, space: 0 }) {
            ForEach(this.drawerEpisodes(), (ep: ComicEpisode) => {
              ListItem() {
                Row({ space: 10 }) {
                  Text(ep.episodeNum.toString())
                    .fontSize(12)
                    .fontColor(this.episodeIndexOf(ep) === this.currentIndex ? '#FFFFFF' : '#999999')
                    .fontWeight(FontWeight.Medium)
                    .width(22)
                    .height(22)
                    .borderRadius(11)
                    .textAlign(TextAlign.Center)
                    .backgroundColor(this.episodeIndexOf(ep) === this.currentIndex ? '#6C5CE7' : '#F2F2F5')
                  Text(this.episodeLabel(ep))
                    .fontSize(14)
                    .fontColor(this.episodeIndexOf(ep) === this.currentIndex ? '#6C5CE7' : '#333333')
                    .fontWeight(this.episodeIndexOf(ep) === this.currentIndex ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .layoutWeight(1)
                  if (this.episodeIndexOf(ep) === this.currentIndex) {
                    Text('在看')
                      .fontSize(10)
                      .fontColor('#6C5CE7')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('#E3DDFF')
                      .borderRadius(8)
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 11, bottom: 11 })
                .onClick(() => {
                  this.closeDrawer();
                  const index: number = this.episodeIndexOf(ep);
                  if (index !== this.currentIndex) {
                    this.selectEpisode(index);
                  }
                })
              }
              .margin({ left: 14, right: 14, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor(this.episodeIndexOf(ep) === this.currentIndex ? '#F0EDFF' : '#FFFFFF')
            }, (ep: ComicEpisode): string => ep.episodeId + '_' + this.drawerAscending)
          }
          .height('100%')
          .width('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onAreaChange((_o: Area, n: Area) => {
            this.drawerSliderAreaWidth = Number(n.width);
            this.drawerSliderAreaHeight = Number(n.height);
          })
          this.drawerSlider()
          if (this.drawerSliderActive) {
            Text(this.drawerSliderBubbleText())
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .backgroundColor('#6C5CE7')
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .position({
                x: Math.max(this.drawerSliderAreaWidth - 110, 8),
                y: this.drawerBubbleY()
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('76%')
      .height('100%')
      .padding({ top: Math.max(this.statusBarVp, 20), bottom: this.navBarVp })
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
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
            LazyForEach(this.pagesDs, (img: ReaderPageImage) => {
              ListItem() {
                ReaderImageItem({
                  img: img,
                  placeholderWRatio: this.placeholderWRatio,
                  itemWidthPx: this.readerWidthPx,
                  onImageRatio: (r: number) => {
                    this.updatePlaceholderRatio(r);
                  },
                  onImageError: () => {
                    this.recoverImages();
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
            this.firstVisible = first;
            if (first >= 0 && first < this.images.length) {
              const epIdx: number = this.images[first].episodeIdx;
              // 无感接章：滚入已拼接的下一话时章节跟随切换（顶栏/目录/进度）
              if (epIdx !== this.currentIndex) {
                this.currentIndex = epIdx;
              }
              this.seekValue = first - this.offsetOfEpisode(epIdx);
              this.saveProgressThrottled();
            }
            // 距已加载内容底部不足 N 页：预拼接下一话
            if (this.images.length > 0 && last >= this.images.length - STITCH_AHEAD_PAGES) {
              this.maybeStitchNext();
            }
          })
          .onReachEnd(() => {
            // 滚到底部时末页可能未成为首可见项（末图较短被截断），直接计为最后一页
            if (this.images.length > 0) {
              const lastIdx: number = this.images.length - 1;
              const epIdx: number = this.images[lastIdx].episodeIdx;
              if (epIdx !== this.currentIndex) {
                this.currentIndex = epIdx;
              }
              const target: number = lastIdx - this.offsetOfEpisode(epIdx);
              if (this.seekValue < target) {
                this.seekValue = target;
                this.saveProgressThrottled();
              }
            }
            this.maybeStitchNext();
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
        // 章节目录抽屉（单根 Stack：遮罩 + 右侧面板）
        if (this.drawerOpen) {
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
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 列表内容宽度（px）：页高按整像素对齐用，首帧即确定
        const w: Length = newArea.width;
        if (typeof w === 'number' && w > 0) {
          this.readerWidthPx = Math.round(w * vp2px(1));
        }
      })
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
