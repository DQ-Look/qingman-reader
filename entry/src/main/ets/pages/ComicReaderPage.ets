/**
 * 漫画阅读器：当前章节图片纵向滚动阅读，支持上一话/下一话切换
 * 数据源：mihumh.com 同源代理（images/{episodeId}）
 */
import {
  ComicEpisode, ComicEpisodeImage, ComicReaderParam, COMIC_BOOK_URL_PREFIX,
  parseEpisodeImages, parseEpisodeList, CACHE_PREFIX_EPS, CACHE_PREFIX_IMGS,
  imagesFresh, episodesFresh
} from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { Book } from '../model/BookModels';
import { StorageKeys } from '../model/ReadConfigModels';
import { Db } from '../service/Db';

@Component
struct ComicReaderPage {
  param: ComicReaderParam = new ComicReaderParam();
  @State episodes: ComicEpisode[] = [];
  @State currentIndex: number = 0;
  @State images: ComicEpisodeImage[] = [];
  @State loading: boolean = true;
  @State failedMsg: string = '';
  @State chromeVisible: boolean = false;
  navPathStack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  private scrolledForEpisode: boolean = false;

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
    this.images = imgs;
    this.loading = false;
    this.chromeVisible = false;
    if (!this.scrolledForEpisode) {
      this.scrolledForEpisode = true;
      this.scroller.scrollToIndex(0, false);
    }
    this.updateShelfProgress();
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
   * 若漫画已在书架，把当前章节进度回写（book 表 durChapterIndex/durChapterTitle）
   */
  updateShelfProgress(): void {
    const url: string = COMIC_BOOK_URL_PREFIX + this.param.comicId;
    const db: Db = Db.getInstance();
    db.getBook(url).then((saved: Book | null) => {
      if (saved === null) {
        return;
      }
      return db.updateBookProgress(url, this.currentIndex, this.currentEpisode().name, 0).then(() => {
        AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
          (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      });
    }).catch(() => {
    });
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
    this.currentIndex = next;
    this.loadEpisode();
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
    }
    .width('100%')
    .padding({ top: 42, bottom: 10, left: 14, right: 14 })
    .backgroundColor('#99000000')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  bottomBar() {
    Row() {
      Text('上一话')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .backgroundColor('#66000000')
        .borderRadius(17)
        .onClick(() => {
          this.switchEpisode(-1);
        })
      Blank()
      Text((this.currentIndex + 1) + ' / ' + this.episodes.length)
        .fontSize(13)
        .fontColor('#FFFFFF')
      Blank()
      Text('下一话')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .backgroundColor('#665959FF')
        .borderRadius(17)
        .onClick(() => {
          this.switchEpisode(1);
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 28 })
    .backgroundColor('#99000000')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Stack() {
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
          .onClick(() => {
            this.chromeVisible = !this.chromeVisible;
          })
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
          .onClick(() => {
            this.chromeVisible = !this.chromeVisible;
          })
        } else {
          List({ scroller: this.scroller, space: 0 }) {
            ForEach(this.images, (img: ComicEpisodeImage) => {
              ListItem() {
                Image(img.imageUrl)
                  .width('100%')
                  .objectFit(ImageFit.Contain)
                  .backgroundColor('#2E2E33')
              }
            }, (img: ComicEpisodeImage): string => img.imageId + '_' + img.imageIndex)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#222222')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onClick(() => {
            this.chromeVisible = !this.chromeVisible;
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#222222')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor('#222222')
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ComicReaderParam = ctx.pathInfo.param as ComicReaderParam;
      if (p instanceof ComicReaderParam) {
        this.param = p;
        this.episodes = p.episodes;
        this.currentIndex = p.startIndex;
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
