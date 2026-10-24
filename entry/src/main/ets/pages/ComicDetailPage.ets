/**
 * 漫画详情页：信息 + 章节目录（正/倒序切换）
 * 数据源：App API（comic/info/{comicId} + comic/episode/list/{comicId}）
 */
import {
  ComicItem, ComicParam, ComicEpisode, ComicReaderParam, COMIC_BOOK_URL_PREFIX,
  parseComicInfo, parseEpisodeList
} from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { Book } from '../model/BookModels';
import { Db } from '../service/Db';
import { StorageKeys } from '../model/ReadConfigModels';

const CACHE_PREFIX_INFO: string = 'comic_info_';
const CACHE_PREFIX_EPS: string = 'comic_eps_';

@Component
struct ComicDetailPage {
  brief: ComicParam = new ComicParam();
  @State comic: ComicItem = new ComicItem();
  @State episodes: ComicEpisode[] = [];
  @State sortedEpisodes: ComicEpisode[] = [];
  @State epsLoading: boolean = true;
  @State epsFailed: boolean = false;
  @State ascending: boolean = true;
  @State synopsisExpanded: boolean = false;
  @State onShelf: boolean = false;
  @State savedEpisodeIndex: number = -1;
  navPathStack: NavPathStack = new NavPathStack();

  /**
   * 缓存秒开 + info/目录并行拉取最新（stale-while-revalidate）
   */
  loadData(): void {
    this.epsLoading = this.episodes.length === 0;
    this.epsFailed = false;
    const api: ComicApi = ComicApi.getInstance();
    const db: Db = Db.getInstance();
    const infoKey: string = CACHE_PREFIX_INFO + this.brief.comicId;
    const epsKey: string = CACHE_PREFIX_EPS + this.brief.comicId;
    // 1) 本地缓存先渲染
    db.getCache(infoKey).then((raw: string) => {
      if (raw !== '') {
        const info: ComicItem = parseComicInfo(raw);
        if (info.comicId !== '') {
          this.applyInfo(info);
        }
      }
    }).catch(() => {
    });
    db.getCache(epsKey).then((raw: string) => {
      if (raw !== '' && this.episodes.length === 0) {
        this.applyEpisodes(parseEpisodeList(raw));
        this.epsLoading = false;
      }
    }).catch(() => {
    });
    // 2) 网络并行刷新
    api.getComicInfoRaw(this.brief.comicId).then((raw: string) => {
      db.setCache(infoKey, raw).catch(() => {
      });
      const info: ComicItem = parseComicInfo(raw);
      if (info.comicId === '') {
        info.comicId = this.brief.comicId;
        info.comicName = this.brief.comicName;
        info.picUrl = this.brief.picUrl;
      }
      this.applyInfo(info);
    }).catch(() => {
    });
    api.getEpisodeListRaw(this.brief.comicId).then((raw: string) => {
      db.setCache(epsKey, raw).catch(() => {
      });
      this.applyEpisodes(parseEpisodeList(raw));
      this.epsLoading = false;
    }).catch(() => {
      if (this.episodes.length === 0) {
        this.epsFailed = true;
        this.epsLoading = false;
      }
    });
  }

  applyInfo(info: ComicItem): void {
    if (info.picUrl === '') {
      info.picUrl = this.brief.picUrl;
    }
    this.comic = info;
  }

  applyEpisodes(eps: ComicEpisode[]): void {
    eps.sort((a: ComicEpisode, b: ComicEpisode): number => a.episodeNum - b.episodeNum);
    this.episodes = eps;
    this.applySort();
  }

  checkShelf(): void {
    Db.getInstance().getBook(COMIC_BOOK_URL_PREFIX + this.brief.comicId).then((saved: Book | null) => {
      if (saved !== null) {
        this.onShelf = true;
        this.savedEpisodeIndex = saved.durChapterIndex;
      } else {
        this.onShelf = false;
        this.savedEpisodeIndex = -1;
      }
    }).catch(() => {
      this.onShelf = false;
      this.savedEpisodeIndex = -1;
    });
  }

  toggleShelf(): void {
    const url: string = COMIC_BOOK_URL_PREFIX + this.comic.comicId;
    const db: Db = Db.getInstance();
    if (this.onShelf) {
      db.deleteBook(url).then(() => {
        this.onShelf = false;
        this.savedEpisodeIndex = -1;
        AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
          (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
        this.getUIContext().getPromptAction().showToast({ message: '已移出书架' });
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
      });
      return;
    }
    const b: Book = new Book();
    b.bookUrl = url;
    b.name = this.comic.comicName;
    b.author = this.comic.author;
    b.origin = 'qingman';
    b.originName = '漫画';
    b.coverUrl = this.comic.picUrl;
    b.intro = this.comic.synopsis;
    let kind: string = '';
    for (let i = 0; i < this.comic.categories.length; i++) {
      if (i > 0) {
        kind += ' ';
      }
      kind += this.comic.categories[i];
    }
    b.kind = kind;
    b.latestChapterTitle = this.comic.lastEpisodeName;
    db.saveBook(b).then(() => {
      this.onShelf = true;
      AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
        (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已加入书架' });
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '加入书架失败' });
    });
  }

  applySort(): void {
    const copy: ComicEpisode[] = this.episodes.slice();
    if (!this.ascending) {
      copy.reverse();
    }
    this.sortedEpisodes = copy;
  }

  toggleSort(): void {
    this.ascending = !this.ascending;
    this.applySort();
  }

  episodeIndex(ep: ComicEpisode): number {
    for (let i = 0; i < this.episodes.length; i++) {
      if (this.episodes[i].episodeId === ep.episodeId) {
        return i;
      }
    }
    return 0;
  }

  openReader(ep: ComicEpisode): void {
    this.openReaderAt(this.episodeIndex(ep));
  }

  openReaderAt(index: number): void {
    const p: ComicReaderParam = new ComicReaderParam();
    p.comicId = this.comic.comicId;
    p.comicName = this.comic.comicName;
    p.episodes = this.episodes;
    p.startIndex = index;
    this.navPathStack.pushPathByName('comicReader', p);
  }

  startReading(): void {
    if (this.episodes.length === 0) {
      return;
    }
    let idx: number = 0;
    if (this.onShelf && this.savedEpisodeIndex >= 0 && this.savedEpisodeIndex < this.episodes.length) {
      idx = this.savedEpisodeIndex;
    }
    this.openReaderAt(idx);
  }

  readButtonLabel(): string {
    if (this.onShelf && this.savedEpisodeIndex > 0 && this.savedEpisodeIndex < this.episodes.length) {
      return '继续阅读 第' + (this.savedEpisodeIndex + 1) + '话';
    }
    return '开始阅读';
  }

  firstChar(name: string): string {
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '漫';
  }

  @Builder
  infoHeader() {
    Row({ space: 12 }) {
      if (this.comic.picUrl !== '') {
        Image(this.comic.picUrl)
          .width(104)
          .height(138)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(this.firstChar(this.comic.comicName))
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(104)
        .height(138)
        .backgroundColor('#8D8D93')
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 6 }) {
        Text(this.comic.comicName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
          .maxLines(2)
        Text(this.comic.author === '' ? '未知作者' : this.comic.author)
          .fontSize(13)
          .fontColor('#666666')
          .maxLines(1)
        Row({ space: 6 }) {
          ForEach(this.comic.categories, (cat: string) => {
            Text(cat)
              .fontSize(11)
              .fontColor('#6C5CE7')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#F0EDFF')
              .borderRadius(10)
          }, (cat: string): string => cat)
        }
        Text('人气 ' + this.comic.playNum + ' · 收藏 ' + this.comic.collectNum)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
        Text('更新至 ' + this.comic.episodeNum + ' 话')
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  @Builder
  synopsisCard() {
    Column({ space: 8 }) {
      Text('简介')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
      Text(this.comic.synopsis === '' ? '暂无简介' : this.comic.synopsis)
        .fontSize(13)
        .fontColor('#666666')
        .lineHeight(20)
        .maxLines(this.synopsisExpanded ? 100 : 4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.comic.synopsis !== '') {
        Text(this.synopsisExpanded ? '收起' : '展开')
          .fontSize(12)
          .fontColor('#6C5CE7')
          .onClick(() => {
            this.synopsisExpanded = !this.synopsisExpanded;
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  @Builder
  episodeRow(ep: ComicEpisode) {
    Row({ space: 10 }) {
      Text(String(ep.episodeNum))
        .fontSize(12)
        .fontColor('#999999')
        .width(28)
        .textAlign(TextAlign.Center)
      Text(ep.name === '' ? '第' + ep.episodeNum + '话' : ep.name)
        .fontSize(14)
        .fontColor('#333333')
        .maxLines(1)
        .layoutWeight(1)
      Text(ep.updateTime === '' ? '' : ep.updateTime.substring(0, 10))
        .fontSize(11)
        .fontColor('#BBBBBB')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.openReader(ep);
    })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.infoHeader()
          this.synopsisCard()
          Row({ space: 10 }) {
            Button(this.readButtonLabel())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .backgroundColor('#6C5CE7')
              .borderRadius(22)
              .height(44)
              .layoutWeight(1)
              .enabled(this.episodes.length > 0)
              .onClick(() => {
                this.startReading();
              })
            Button(this.onShelf ? '已在书架' : '加入书架')
              .fontSize(14)
              .fontColor(this.onShelf ? '#999999' : '#6C5CE7')
              .backgroundColor('#F0EDFF')
              .borderRadius(22)
              .height(44)
              .layoutWeight(1)
              .onClick(() => {
                this.toggleShelf();
              })
          }
          .width('100%')
          .margin({ top: 4 })
          Row() {
            Text('章节列表（' + this.episodes.length + '）')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
            Blank()
            Text(this.ascending ? '正序 ↓' : '倒序 ↑')
              .fontSize(12)
              .fontColor('#6C5CE7')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .backgroundColor('#F0EDFF')
              .borderRadius(12)
              .onClick(() => {
                this.toggleSort();
              })
          }
          .width('100%')
          .padding({ top: 16, bottom: 8 })
          if (this.episodes.length === 0 && this.epsLoading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color('#999999')
              Text('目录加载中...')
                .fontSize(13)
                .fontColor('#999999')
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .justifyContent(FlexAlign.Center)
          } else if (this.episodes.length === 0 && this.epsFailed) {
            Text('目录加载失败，点击重试')
              .fontSize(13)
              .fontColor('#6C5CE7')
              .width('100%')
              .padding({ top: 24, bottom: 24 })
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.loadData();
              })
          } else {
            Column() {
              ForEach(this.sortedEpisodes, (ep: ComicEpisode) => {
                this.episodeRow(ep)
              }, (ep: ComicEpisode): string => ep.episodeId)
            }
            .width('100%')
            .borderRadius(12)
            .clip(true)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 12, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor('#F5F5F5')
    }
    .title(this.comic.comicName === '' ? '漫画详情' : this.comic.comicName)
    .backgroundColor('#F5F5F5')
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ComicParam = ctx.pathInfo.param as ComicParam;
      if (p instanceof ComicParam && p.comicId !== '') {
        this.brief = p;
        // 入参骨架立即渲染，不等网络
        const skeleton: ComicItem = new ComicItem();
        skeleton.comicId = p.comicId;
        skeleton.comicName = p.comicName;
        skeleton.picUrl = p.picUrl;
        this.comic = skeleton;
        this.checkShelf();
        this.loadData();
      }
    })
  }
}

@Builder
export function ComicDetailPageBuilder() {
  ComicDetailPage()
}
