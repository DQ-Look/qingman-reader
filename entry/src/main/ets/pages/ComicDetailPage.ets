/**
 * 漫画详情页：对齐原版 Mihu ComicDetailsActivity 结构
 * 信息区（封面/状态/标签/版本tips/简介） → 猜你喜欢（appLikeDataList）
 * → 选集（横向章节 + 全章节弹窗） → 评论（comment/page）
 * 数据源：App API（comic/info + comic/episode/list + appLikeDataList + comment/page）
 */
import {
  ComicItem, ComicParam, ComicEpisode, ComicReaderParam, COMIC_BOOK_URL_PREFIX,
  ComicComment, parseComicInfo, parseEpisodeList
} from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { Book } from '../model/BookModels';
import { Db } from '../service/Db';
import { StorageKeys } from '../model/ReadConfigModels';
import { PageHeader } from '../common/PageHeader';

const CACHE_PREFIX_INFO: string = 'comic_info_';
const CACHE_PREFIX_EPS: string = 'comic_eps_';
const STAR_MASK: string = '**************';

/**
 * 章节懒加载数据源（List + LazyForEach）：
 * 368+ 话的漫画若用 ForEach 全量构建会阻塞主线程导致 appfreeze
 */
class EpisodeDataSource implements IDataSource {
  private items: ComicEpisode[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ComicEpisode {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  setList(items: ComicEpisode[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

@Component
struct ComicDetailPage {
  brief: ComicParam = new ComicParam();
  @State comic: ComicItem = new ComicItem();
  @State episodes: ComicEpisode[] = [];
  @State epsLoading: boolean = true;
  @State epsFailed: boolean = false;
  @State synopsisExpanded: boolean = false;
  @State onShelf: boolean = false;
  @State savedEpisodeIndex: number = -1;
  @State savedPage: number = 0;
  @State likeComics: ComicItem[] = [];
  @State likeLoading: boolean = false;
  @State comments: ComicComment[] = [];
  @State commentTotal: number = 0;
  @State commentLoading: boolean = true;
  @State showEpisodeDialog: boolean = false;
  @State dialogAsc: boolean = true;
  stripSource: EpisodeDataSource = new EpisodeDataSource();
  dialogSource: EpisodeDataSource = new EpisodeDataSource();
  dialogScroller: Scroller = new Scroller();
  /** 全章节弹窗快速定位滑杆：显示序列索引 / 拖动激活态 / 列表区尺寸（气泡定位用） */
  @State dialogSliderIndex: number = 0;
  @State dialogSliderActive: boolean = false;
  dialogSliderAreaWidth: number = 0;
  dialogSliderAreaHeight: number = 0;
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

  /**
   * 猜你喜欢（comic/appLikeDataList，「换一批」重复调用）
   */
  loadLikeList(): void {
    if (this.brief.comicId === '') {
      return;
    }
    this.likeLoading = true;
    ComicApi.getInstance().getLikeDataList(this.brief.comicId).then((list: ComicItem[]) => {
      this.likeComics = list;
      this.likeLoading = false;
    }).catch(() => {
      this.likeLoading = false;
    });
  }

  /**
   * 评论第一页（comment/page，按点赞数降序，与原版 d1() 一致）
   */
  loadComments(): void {
    if (this.brief.comicId === '') {
      return;
    }
    this.commentLoading = true;
    ComicApi.getInstance().getCommentPage(this.brief.comicId, 1, 10).then((result) => {
      this.comments = result.comments;
      this.commentTotal = result.total;
      this.commentLoading = false;
    }).catch(() => {
      this.commentLoading = false;
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
    this.stripSource.setList(eps);
    this.markTocSeen(eps.length);
  }

  /**
   * 查看目录即确认更新：回写已确认目录数，仅在变化时刷新书架，清除/更新角标
   */
  markTocSeen(count: number): void {
    const url: string = COMIC_BOOK_URL_PREFIX + this.brief.comicId;
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

  checkShelf(): void {
    Db.getInstance().getBook(COMIC_BOOK_URL_PREFIX + this.brief.comicId).then((saved: Book | null) => {
      if (saved !== null) {
        this.onShelf = true;
        this.savedEpisodeIndex = saved.durChapterIndex;
        this.savedPage = saved.durChapterPos > 0 ? Math.floor(saved.durChapterPos) : 0;
      } else {
        this.onShelf = false;
        this.savedEpisodeIndex = -1;
        this.savedPage = 0;
      }
    }).catch(() => {
      this.onShelf = false;
      this.savedEpisodeIndex = -1;
      this.savedPage = 0;
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

  episodeIndex(ep: ComicEpisode): number {
    for (let i = 0; i < this.episodes.length; i++) {
      if (this.episodes[i].episodeId === ep.episodeId) {
        return i;
      }
    }
    return 0;
  }

  openReader(ep: ComicEpisode): void {
    this.openReaderAt(this.episodeIndex(ep), 0);
  }

  openReaderAt(index: number, page: number): void {
    const p: ComicReaderParam = new ComicReaderParam();
    p.comicId = this.comic.comicId;
    p.comicName = this.comic.comicName;
    p.episodes = this.episodes;
    p.startIndex = index;
    p.startPage = page;
    this.showEpisodeDialog = false;
    this.navPathStack.pushPathByName('comicReader', p);
  }

  startReading(): void {
    if (this.episodes.length === 0) {
      return;
    }
    let idx: number = 0;
    let page: number = 0;
    if (this.onShelf && this.savedEpisodeIndex >= 0 && this.savedEpisodeIndex < this.episodes.length) {
      idx = this.savedEpisodeIndex;
      page = this.savedPage;
    }
    this.openReaderAt(idx, page);
  }

  openLike(it: ComicItem): void {
    const p: ComicParam = new ComicParam();
    p.comicId = it.comicId;
    p.comicName = it.comicName;
    p.picUrl = it.picUrl;
    this.navPathStack.pushPathByName('comicDetail', p);
  }

  /** 原版 q1() 脱敏：len<=3 全 *，否则前半 + *** + 后段 */
  maskName(name: string): string {
    const len: number = name.length;
    if (len === 0) {
      return '';
    }
    if (len <= 3) {
      return STAR_MASK.substring(0, len);
    }
    const half: number = Math.floor((len - 3) / 2);
    return name.substring(0, half) + '***' + name.substring(half + 3);
  }

  tipsText(): string {
    return '版本信息：本作品由用户' + this.maskName(this.comic.createName) +
      '整理并上传，如有任何侵权行为，请联系我们及时下架';
  }

  statusText(): string {
    if (this.comic.state === 1) {
      return '共 ' + this.comic.episodeNum + ' 话';
    }
    return '更新至 ' + this.comic.episodeNum + ' 话';
  }

  numText(): string {
    if (this.comic.state === 1) {
      return '共 ' + this.episodes.length + ' 话';
    }
    return '已更 ' + this.episodes.length + ' 话';
  }

  dialogTitle(): string {
    if (this.comic.state === 1) {
      return '已完结·共 ' + this.episodes.length + ' 话';
    }
    return '连载中·已更新 ' + this.episodes.length + ' 话';
  }

  /** 打开全章节弹窗（正序，与原版 Y 默认一致），定位到记忆阅读位置 */
  openEpisodeDialog(): void {
    if (this.episodes.length === 0) {
      return;
    }
    this.dialogAsc = true;
    this.dialogSliderIndex = 0;
    this.dialogSource.setList(this.episodes.slice());
    this.showEpisodeDialog = true;
    this.scrollDialogToCurrent(80);
    this.scrollDialogToCurrent(400);
  }

  /**
   * 弹窗滚动到书架记忆的续读话（ LazyForEach 行未建完时首滚可能偏移，二次校正）
   * 无阅读记录（未上架/未读过）时停在 第1话
   */
  scrollDialogToCurrent(delay: number): void {
    setTimeout(() => {
      if (!this.showEpisodeDialog) {
        return;
      }
      if (!this.onShelf || this.savedEpisodeIndex < 0 || this.savedEpisodeIndex >= this.episodes.length) {
        return;
      }
      const target: number = this.dialogAsc
        ? this.savedEpisodeIndex
        : this.episodes.length - 1 - this.savedEpisodeIndex;
      this.dialogSliderIndex = target;
      this.dialogScroller.scrollToIndex(target, false);
    }, delay);
  }

  /** 弹窗右缘快速定位滑杆：拖动 → 滚动列表到对应显示序列索引 */
  onDialogSliderChange(value: number, mode: SliderChangeMode): void {
    const total: number = this.dialogSource.totalCount();
    const idx: number = Math.min(Math.max(Math.round(value), 0), Math.max(total - 1, 0));
    this.dialogSliderIndex = idx;
    this.dialogSliderActive = mode !== SliderChangeMode.End;
    this.dialogScroller.scrollToIndex(idx, false);
  }

  dialogSliderBubbleText(): string {
    const total: number = this.dialogSource.totalCount();
    if (this.dialogSliderIndex >= 0 && this.dialogSliderIndex < total) {
      const ep: ComicEpisode = this.dialogSource.getData(this.dialogSliderIndex);
      return '第' + ep.episodeNum + '话';
    }
    return '';
  }

  /** 气泡跟随滑块：OutSet 上下各留 10vp 边距，按比例折算并夹紧 */
  dialogBubbleY(): number {
    const max: number = Math.max(this.dialogSource.totalCount() - 1, 0);
    const fraction: number = max > 0 ? this.dialogSliderIndex / max : 0;
    const h: number = this.dialogSliderAreaHeight;
    const y: number = 12 + fraction * Math.max(h - 24, 0) - 14;
    return Math.min(Math.max(y, 0), Math.max(h - 30, 0));
  }

  /** 弹窗内正/倒序切换（label 显示的是点击后的目标排序，与原版一致） */
  toggleDialogSort(): void {
    this.dialogAsc = !this.dialogAsc;
    const copy: ComicEpisode[] = this.episodes.slice();
    if (!this.dialogAsc) {
      copy.reverse();
    }
    this.dialogSource.setList(copy);
    this.scrollDialogToCurrent(80);
    this.scrollDialogToCurrent(400);
  }

  selectedEpisodeId(): string {
    if (this.onShelf && this.savedEpisodeIndex >= 0 && this.savedEpisodeIndex < this.episodes.length) {
      return this.episodes[this.savedEpisodeIndex].episodeId;
    }
    return '';
  }

  episodeDate(t: string): string {
    return t.length >= 10 ? t.substring(0, 10) : t;
  }

  episodeName(ep: ComicEpisode): string {
    return ep.name === '' ? '第' + ep.episodeNum + '话' : ep.name;
  }

  formatCommentTime(t: string): string {
    if (t.length < 10) {
      return t;
    }
    const ms: number = Date.parse(t.replace(' ', 'T'));
    if (Number.isNaN(ms)) {
      return t.substring(0, 10);
    }
    const days: number = Math.floor((Date.now() - ms) / 86400000);
    if (days <= 0) {
      return '今天';
    }
    if (days === 1) {
      return '昨天';
    }
    if (days < 30) {
      return days + '天前';
    }
    return t.substring(0, 10);
  }

  /** 猜你喜欢按 3 列分行渲染 */
  likeRows(): ComicItem[][] {
    const rows: ComicItem[][] = [];
    for (let i = 0; i < this.likeComics.length; i += 3) {
      const row: ComicItem[] = [];
      for (let j = i; j < i + 3 && j < this.likeComics.length; j++) {
        row.push(this.likeComics[j]);
      }
      rows.push(row);
    }
    return rows;
  }

  firstChar(name: string): string {
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '漫';
  }

  @Builder
  infoCard() {
    Column({ space: 8 }) {
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
          Row({ space: 6 }) {
            Text(this.comic.state === 1 ? '已完结' : '连载中')
              .fontSize(10)
              .fontColor(this.comic.state === 1 ? '#999999' : '#6C5CE7')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.comic.state === 1 ? '#F5F5F5' : '#F0EDFF')
              .borderRadius(4)
            Text(this.statusText())
              .fontSize(12)
              .fontColor('#999999')
              .maxLines(1)
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.comic.categories, (cat: string) => {
              Text(cat)
                .fontSize(11)
                .fontColor('#6C5CE7')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .margin({ right: 6, bottom: 4 })
                .backgroundColor('#F0EDFF')
                .borderRadius(10)
            }, (cat: string): string => cat)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      if (this.comic.createName !== '') {
        Text(this.tipsText())
          .fontSize(11)
          .fontColor('#BBBBBB')
          .lineHeight(16)
          .width('100%')
      }
      if (this.comic.synopsis !== '') {
        Text(this.comic.synopsis)
          .fontSize(13)
          .fontColor('#666666')
          .lineHeight(20)
          .maxLines(this.synopsisExpanded ? 100 : 4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
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
  likeCard() {
    Column({ space: 10 }) {
      Row() {
        Text('猜你喜欢')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
        Blank()
        Text('换一批')
          .fontSize(12)
          .fontColor('#6C5CE7')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.loadLikeList();
          })
      }
      .width('100%')
      if (this.likeLoading && this.likeComics.length === 0) {
        Row({ space: 8 }) {
          Column() {
          }
          .layoutWeight(1)
          .aspectRatio(0.72)
          .backgroundColor('#EFEEF4')
          .borderRadius(6)
          Column() {
          }
          .layoutWeight(1)
          .aspectRatio(0.72)
          .backgroundColor('#EFEEF4')
          .borderRadius(6)
          Column() {
          }
          .layoutWeight(1)
          .aspectRatio(0.72)
          .backgroundColor('#EFEEF4')
          .borderRadius(6)
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          ForEach(this.likeRows(), (row: ComicItem[]) => {
            Row({ space: 8 }) {
              ForEach(row, (it: ComicItem) => {
                Column({ space: 6 }) {
                  if (it.picUrl !== '') {
                    Image(it.picUrl)
                      .width('100%')
                      .aspectRatio(0.72)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                      .backgroundColor('#EFEEF4')
                  } else {
                    Column() {
                      Text(this.firstChar(it.comicName))
                        .fontSize(24)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                    }
                    .width('100%')
                    .aspectRatio(0.72)
                    .backgroundColor('#8D8D93')
                    .borderRadius(6)
                    .justifyContent(FlexAlign.Center)
                  }
                  Text(it.comicName)
                    .fontSize(13)
                    .fontColor('#333333')
                    .maxLines(1)
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.openLike(it);
                })
              }, (it: ComicItem): string => it.comicId)
            }
            .width('100%')
          }, (row: ComicItem[]): string => row.length + '_' + (row.length > 0 ? row[0].comicId : ''))
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  @Builder
  episodeCard(ep: ComicEpisode) {
    Column({ space: 4 }) {
      Image(ep.coverUrl)
        .width(120)
        .height(72)
        .objectFit(ImageFit.Cover)
        .borderRadius(5)
        .backgroundColor('#EFEEF4')
      Text(this.episodeName(ep))
        .fontSize(12)
        .fontColor(ep.episodeId === this.selectedEpisodeId() ? '#0986FF' : '#333333')
        .maxLines(1)
        .width(120)
      Text(this.episodeDate(ep.updateTime))
        .fontSize(10)
        .fontColor(ep.episodeId === this.selectedEpisodeId() ? '#0986FF' : '#999999')
        .maxLines(1)
        .width(120)
    }
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openReader(ep);
    })
  }

  @Builder
  episodeSection() {
    Column({ space: 10 }) {
      Row() {
        Text(this.numText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
          .onClick(() => {
            this.openEpisodeDialog();
          })
        Blank()
        Text('更多 >')
          .fontSize(12)
          .fontColor('#999999')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.openEpisodeDialog();
          })
      }
      .width('100%')
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
        .padding({ top: 12, bottom: 12 })
        .justifyContent(FlexAlign.Center)
      } else if (this.episodes.length === 0 && this.epsFailed) {
        Text('目录加载失败，点击重试')
          .fontSize(13)
          .fontColor('#6C5CE7')
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.loadData();
          })
      } else if (this.episodes.length > 0) {
        List({ space: 10 }) {
          LazyForEach(this.stripSource, (ep: ComicEpisode) => {
            ListItem() {
              this.episodeCard(ep)
            }
          }, (ep: ComicEpisode): string => ep.episodeId)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(114)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  @Builder
  commentItem(c: ComicComment) {
    Row({ space: 10 }) {
      if (c.userAvatar !== '') {
        Image(c.userAvatar)
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(this.firstChar(c.userName))
            .fontSize(16)
            .fontColor('#6C5CE7')
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor('#F0EDFF')
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(c.userName === '' ? '匿名用户' : c.userName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(1)
            .layoutWeight(1)
          Text(String(c.likeCount))
            .fontSize(11)
            .fontColor('#999999')
        }
        .width('100%')
        Text(c.content)
          .fontSize(13)
          .fontColor('#333333')
          .lineHeight(19)
          .width('100%')
        Text(this.formatCommentTime(c.createTime) + ' ·')
          .fontSize(11)
          .fontColor('#999999')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  commentSection() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text('评论')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#222222')
        if (this.commentTotal > 0) {
          Text(String(this.commentTotal))
            .fontSize(13)
            .fontColor('#6C5CE7')
        }
      }
      .width('100%')
      if (this.comments.length > 0) {
        ForEach(this.comments, (c: ComicComment) => {
          this.commentItem(c)
        }, (c: ComicComment): string => c.commentId)
      } else if (!this.commentLoading) {
        Text('还没有评论哦~')
          .fontSize(13)
          .fontColor('#999999')
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  @Builder
  bottomBar() {
    Column() {
      Divider()
        .color('#F0F0F0')
      Row({ space: 10 }) {
        Button(this.onShelf ? '已收藏' : '收藏')
          .fontSize(14)
          .fontColor(this.onShelf ? '#999999' : '#6C5CE7')
          .backgroundColor(this.onShelf ? '#F5F5F5' : '#F0EDFF')
          .borderRadius(22)
          .height(44)
          .width(96)
          .onClick(() => {
            this.toggleShelf();
          })
        Button(this.onShelf ? '继续阅读' : '开始阅读')
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
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
  }

  @Builder
  dialogEpisodeRow(ep: ComicEpisode) {
    Row({ space: 10 }) {
      Image(ep.coverUrl)
        .width(100)
        .height(60)
        .objectFit(ImageFit.Cover)
        .borderRadius(5)
        .backgroundColor('#EFEEF4')
      Column({ space: 2 }) {
        Text(this.episodeName(ep))
          .fontSize(14)
          .fontColor(ep.episodeId === this.selectedEpisodeId() ? '#0986FF' : '#333333')
          .maxLines(1)
        Text(this.episodeDate(ep.updateTime))
          .fontSize(11)
          .fontColor(ep.episodeId === this.selectedEpisodeId() ? '#0986FF' : '#999999')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (ep.episodeId === this.selectedEpisodeId()) {
        Text('在看')
          .fontSize(10)
          .fontColor('#0986FF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#E5F3FF')
          .borderRadius(8)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openReader(ep);
    })
  }

  @Builder
  episodeDialog() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#80000000')
      .onClick(() => {
        this.showEpisodeDialog = false;
      })
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Text(this.dialogTitle())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#222222')
            .maxLines(1)
            .layoutWeight(1)
          Text(this.dialogAsc ? '倒序' : '正序')
            .fontSize(13)
            .fontColor('#6C5CE7')
            .onClick(() => {
              this.toggleDialogSort();
            })
          Text('×')
            .fontSize(18)
            .fontColor('#999999')
            .onClick(() => {
              this.showEpisodeDialog = false;
            })
        }
        .width('100%')
        Divider()
          .color('#F0F0F0')
        Stack({ alignContent: Alignment.End }) {
          List({ scroller: this.dialogScroller }) {
            LazyForEach(this.dialogSource, (ep: ComicEpisode) => {
              ListItem() {
                this.dialogEpisodeRow(ep)
              }
            }, (ep: ComicEpisode): string => ep.episodeId)
          }
          .height('100%')
          .width('100%')
          .scrollBar(BarState.Auto)
          .onAreaChange((_o: Area, n: Area) => {
            this.dialogSliderAreaWidth = Number(n.width);
            this.dialogSliderAreaHeight = Number(n.height);
          })
          Slider({
            value: this.dialogSliderIndex,
            min: 0,
            max: Math.max(this.dialogSource.totalCount() - 1, 0),
            step: 1,
            direction: Axis.Vertical,
            style: SliderStyle.OutSet
          })
          .width(28)
          .height('100%')
          .blockColor('#6C5CE7')
          .trackColor('#E6E6E6')
          .selectedColor('#6C5CE7')
          .onChange((value: number, mode: SliderChangeMode) => {
            this.onDialogSliderChange(value, mode);
          })
          if (this.dialogSliderActive) {
            Text(this.dialogSliderBubbleText())
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .backgroundColor('#6C5CE7')
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .position({
                x: Math.max(this.dialogSliderAreaWidth - 104, 8),
                y: this.dialogBubbleY()
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('72%')
      .padding({ left: 16, right: 16, top: 14, bottom: 16 })
      .backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          PageHeader({
            title: this.comic.comicName === '' ? '漫画详情' : this.comic.comicName,
            pathStack: this.navPathStack
          })
          Scroll() {
            Column({ space: 10 }) {
              this.infoCard()
              this.episodeSection()
              if (this.likeComics.length > 0 || this.likeLoading) {
                this.likeCard()
              }
              this.commentSection()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 12, bottom: 16 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          this.bottomBar()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        if (this.showEpisodeDialog) {
          this.episodeDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F5F5F5')
    .onShown(() => {
      // 从阅读器返回时刷新记忆位置（续读话/在看标记随阅读进度更新）
      this.checkShelf();
    })
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
        this.loadLikeList();
        this.loadComments();
      }
    })
  }
}

@Builder
export function ComicDetailPageBuilder() {
  ComicDetailPage()
}
