/**
 * 首页 Tab：还原原版 home_fragment_layout
 * 顶部：漫画/更新/小说 子 Tab + 排行/搜索胶囊；内容：三个子页
 */
import { Book, BookInfoParam, ExploreDetailParam } from '../../model/BookModels';
import { BookSource } from '../../model/BookSourceModels';
import { Db } from '../../service/Db';
import { BookSourceRepo } from '../../service/BookSourceRepo';
import { BookService, ExploreCategory } from '../../service/BookService';
import { StorageKeys } from '../../model/ReadConfigModels';
import { BookCover } from '../../components/BookCover';
import { ComicHomeSection, ComicRank, ComicItem, ComicParam, ComicMoreParam, ComicSearchResult, parseHomeData, parseComicList, parseSearchResult } from '../../model/ComicApiModels';
import { ComicApi } from '../../service/ComicApi';

const CACHE_KEY_HOME: string = 'home_data';
const CACHE_KEY_UPDATE: string = 'update_comics';
const UPDATE_PAGE_SIZE: number = 30;

class ComicSection {
  title: string = '';
  sourceUrl: string = '';
  books: Book[] = [];
}

@Component
export struct HomeTabPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;
  @State currentSubTab: number = 0;
  @State shelfBooks: Book[] = [];
  @State comicSections: ComicSection[] = [];
  @State bannerBooks: Book[] = [];
  @State comicLoading: boolean = true;
  @State apiSections: ComicHomeSection[] = [];
  @State apiBanners: ComicItem[] = [];
  @State usingApiData: boolean = false;
  @State apiFailed: boolean = false;
  @State apiError: string = '';
  @State updateComics: ComicItem[] = [];
  @State updateTotal: number = 0;
  @State updatePage: number = 0;
  @State updateLoadingMore: boolean = false;
  @State updateLoading: boolean = false;
  @State updateRequested: boolean = false;
  @State updateFailed: string = '';
  @State refreshing: boolean = false;
  /** 排行榜分区当前选中的榜单下标 */
  @State rankTabIndex: number = 0;
  @StorageProp(StorageKeys.BOOKSHELF_VERSION) @Watch('onShelfChanged') bookshelfVersion: number = 0;

  aboutToAppear(): void {
    this.refreshShelf();
    this.loadCachedHome();
    this.loadComicContent();
  }

  /**
   * 先渲染本地缓存（秒开），网络数据回来后原位替换
   */
  loadCachedHome(): void {
    Db.getInstance().getCache(CACHE_KEY_HOME).then((raw: string) => {
      if (raw === '' || this.usingApiData) {
        return;
      }
      const sections: ComicHomeSection[] = parseHomeData(raw);
      if (sections.length > 0) {
        this.applyHomeSections(sections);
        this.comicLoading = false;
      }
    }).catch(() => {
    });
  }

  applyHomeSections(sections: ComicHomeSection[]): void {
    this.usingApiData = true;
    this.apiFailed = false;
    this.apiError = '';
    this.apiSections = sections;
    const banners: ComicItem[] = [];
    for (let s = 0; s < sections.length && banners.length < 4; s++) {
      const comics: ComicItem[] = sections[s].comics;
      for (let c = 0; c < comics.length && banners.length < 4; c++) {
        if (comics[c].picUrl !== '') {
          banners.push(comics[c]);
        }
      }
    }
    this.apiBanners = banners;
  }

  loadComicContent(): void {
    if (!this.usingApiData) {
      this.comicLoading = true;
    }
    ComicApi.getInstance().getHomeDataRaw().then((raw: string) => {
      const sections: ComicHomeSection[] = parseHomeData(raw);
      if (sections.length > 0) {
        this.applyHomeSections(sections);
        this.comicLoading = false;
        this.refreshing = false;
        Db.getInstance().setCache(CACHE_KEY_HOME, raw).catch(() => {
        });
        return;
      }
      this.loadFromBookSources();
    }).catch((error: Error) => {
      this.refreshing = false;
      if (this.usingApiData) {
        return;
      }
      this.apiFailed = true;
      this.apiError = error.message;
      this.loadFromBookSources();
    });
  }

  onShelfChanged(): void {
    this.refreshShelf();
  }

  loadFromBookSources(): void {
    this.usingApiData = false;
    BookSourceRepo.getInstance().getExploreEnabled().then((sources: BookSource[]) => {
      if (sources.length === 0) {
        this.comicSections = [];
        this.bannerBooks = [];
        this.comicLoading = false;
        return;
      }
      const count: number = sources.length < 2 ? sources.length : 2;
      const slots: ComicSection[] = [];
      for (let i = 0; i < count; i++) {
        slots.push(new ComicSection());
      }
      let pending: number = count;
      for (let i = 0; i < count; i++) {
        const src: BookSource = sources[i];
        BookService.getInstance().parseExploreCategories(src).then((cats: ExploreCategory[]) => {
          if (cats.length === 0) {
            return Promise.resolve();
          }
          const first: ExploreCategory = cats[0];
          return BookService.getInstance().exploreByCategory(src, first.url, 1).then((books: Book[]) => {
            if (books.length > 0) {
              const sec: ComicSection = new ComicSection();
              sec.title = src.bookSourceName + ' · ' + first.title;
              sec.sourceUrl = src.bookSourceUrl;
              sec.books = books.length <= 9 ? books : books.slice(0, 9);
              slots[i] = sec;
            }
          });
        }).catch(() => {
          return Promise.resolve();
        }).then(() => {
          pending -= 1;
          if (pending === 0) {
            const sections: ComicSection[] = [];
            for (let s = 0; s < slots.length; s++) {
              if (slots[s].books.length > 0) {
                sections.push(slots[s]);
              }
            }
            this.comicSections = sections;
            const banners: Book[] = [];
            for (let s = 0; s < sections.length; s++) {
              const secBooks: Book[] = sections[s].books;
              for (let b = 0; b < secBooks.length; b++) {
                if (secBooks[b].coverUrl !== '' && banners.length < 4) {
                  banners.push(secBooks[b]);
                }
              }
            }
            this.bannerBooks = banners;
            this.comicLoading = false;
            this.refreshing = false;
          }
        });
      }
    }).catch(() => {
      this.comicSections = [];
      this.bannerBooks = [];
      this.comicLoading = false;
      this.refreshing = false;
    });
  }

  openExplore(section: ComicSection): void {
    const p: ExploreDetailParam = new ExploreDetailParam();
    p.sourceUrl = section.sourceUrl;
    this.pathStack.pushPathByName('exploreDetail', p);
  }

  openSourceManage(): void {
    this.pathStack.pushPathByName('sourceManage', null);
  }

  firstChar(name: string): string {
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '书';
  }

  openComicDetail(comic: ComicItem): void {
    const p: ComicParam = new ComicParam();
    p.comicId = comic.comicId;
    p.comicName = comic.comicName;
    p.picUrl = comic.picUrl;
    this.pathStack.pushPathByName('comicDetail', p);
  }

  /**
   * 原版 ComicMoreActivity 的标题→排序字段映射
   */
  moreSortField(title: string): string {
    if (title === '98%萌新都入坑了') {
      return 'updateTime';
    }
    if (title === '咪虎推荐·爽就完事了') {
      return 'todayPlayNum';
    }
    if (title === '精品·热漫看到爽！') {
      return 'playNum';
    }
    return 'collectNum';
  }

  /**
   * 分区「更多」：排行榜分区 → 排行榜页；其余 → 分区更多页
   */
  openSectionMore(section: ComicHomeSection): void {
    if (section.title === '排行榜') {
      this.pathStack.pushPathByName('comicRanking', null);
      return;
    }
    const p: ComicMoreParam = new ComicMoreParam();
    p.title = section.title;
    p.sortField = this.moreSortField(section.title);
    this.pathStack.pushPathByName('comicMore', p);
  }

  /**
   * 更新 Tab：先渲染缓存，再拉取最新
   */
  loadUpdateComics(): void {
    this.updateRequested = true;
    if (this.updateComics.length > 0) {
      this.fetchUpdateComics();
      return;
    }
    this.updateLoading = true;
    Db.getInstance().getCache(CACHE_KEY_UPDATE).then((raw: string) => {
      if (raw !== '') {
        const list: ComicItem[] = parseComicList(raw);
        if (list.length > 0) {
          this.updateComics = list;
          this.updatePage = 1;
          this.updateTotal = 0;
          this.updateLoading = false;
        }
      }
    }).catch(() => {
    }).then(() => {
      this.fetchUpdateComics();
    });
  }

  fetchUpdateComics(): void {
    if (this.updateComics.length === 0) {
      this.updateLoading = true;
    }
    this.updateFailed = '';
    ComicApi.getInstance().getLastComicsRaw(1, UPDATE_PAGE_SIZE).then((raw: string) => {
      const res: ComicSearchResult = parseSearchResult(raw);
      this.updateComics = res.comics;
      this.updateTotal = res.total;
      this.updatePage = 1;
      this.updateLoading = false;
      if (res.comics.length > 0) {
        Db.getInstance().setCache(CACHE_KEY_UPDATE, raw).catch(() => {
        });
      }
    }).catch((e: Error) => {
      if (this.updateComics.length === 0) {
        this.updateFailed = e.message;
      }
      this.updateLoading = false;
    });
  }

  /**
   * 更新列表分页加载：按 comicId 去重后追加下一页
   */
  loadMoreUpdateComics(): void {
    if (this.updateLoading || this.updateLoadingMore || this.updateFailed !== '' || this.updateComics.length === 0) {
      return;
    }
    if (this.updateTotal > 0 && this.updateComics.length >= this.updateTotal) {
      return;
    }
    this.updateLoadingMore = true;
    ComicApi.getInstance().getRecentComics(this.updatePage + 1, UPDATE_PAGE_SIZE).then((res: ComicSearchResult) => {
      const seen: Set<string> = new Set<string>();
      const merged: ComicItem[] = this.updateComics.slice();
      for (let i = 0; i < merged.length; i++) {
        seen.add(merged[i].comicId);
      }
      for (let i = 0; i < res.comics.length; i++) {
        if (!seen.has(res.comics[i].comicId)) {
          merged.push(res.comics[i]);
        }
      }
      this.updateComics = merged;
      this.updateTotal = res.total;
      this.updatePage += 1;
      this.updateLoadingMore = false;
    }).catch(() => {
      this.updateLoadingMore = false;
    });
  }

  refreshShelf(): void {
    Db.getInstance().getShelfBooks().then((list: Book[]) => {
      this.shelfBooks = list;
    }).catch(() => {
      this.shelfBooks = [];
    });
  }

  openSearch(): void {
    this.pathStack.pushPathByName('search', null);
  }

  openBookInfo(book: Book): void {
    const p: BookInfoParam = new BookInfoParam();
    p.book = book;
    this.pathStack.pushPathByName('bookInfo', p);
  }

  featuredBook(): Book | null {
    if (this.shelfBooks.length === 0) {
      return null;
    }
    return this.shelfBooks[0];
  }  @Builder
  topTabItem(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(index === this.currentSubTab ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentSubTab ? '#333333' : '#999999')
        .onClick(() => {
          this.currentSubTab = index;
          if (index === 1 && !this.updateRequested) {
            this.loadUpdateComics();
          }
        })
      if (index === this.currentSubTab) {
        Image($r('app.media.home_fragment_top_tab_icon'))
          .width(20)
          .height(4)
          .margin({ top: 4 })
      }
    }
    .padding({ left: 6, right: 6 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  rightIconPill() {
    Row({ space: 6 }) {
      Image($r('app.media.home_right_rank_icon'))
        .width(24)
        .height(24)
        .onClick(() => {
          this.pathStack.pushPathByName('comicRanking', null);
        })
      Divider()
        .vertical(true)
        .width(1)
        .height(8)
        .color('#FFFFFF')
      Image($r('app.media.home_right_search_icon'))
        .width(24)
        .height(24)
        .onClick(() => {
          this.openSearch();
        })
    }
    .padding(6)
    .backgroundColor('#800B0E01')
    .borderRadius(16)
  }

  @Builder
  noticeBar(tips: string) {
    Stack({ alignContent: Alignment.Start }) {
      Image($r('app.media.home_notice_bg'))
        .width('100%')
        .aspectRatio(366 / 32)
        .objectFit(ImageFit.Fill)
      Text(tips)
        .fontSize(12)
        .fontColor('#111111')
        .maxLines(1)
        .margin({ left: 56 })
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 16 })
  }

  @Builder
  sectionHeader(title: string, showMore: boolean) {
    Row() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
      Blank()
      if (showMore) {
        Row({ space: 2 }) {
          Text('更多')
            .fontSize(12)
            .fontColor('#A6A0BC')
          Image($r('app.media.home_comic_right_icon'))
            .width(12)
            .height(12)
        }
        .height(24)
        .padding({ left: 10, right: 10 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F4F1FF')
        .borderRadius(18)
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 8, left: 12, right: 12 })
  }

  @Builder
  comicSubPage() {
    Column() {
      if (this.comicLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载...')
            .fontSize(12)
            .fontColor('#999999')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.usingApiData) {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              if (this.apiBanners.length > 0) {
                this.apiBanner()
              }
              this.noticeBar('漫画内容每日更新，敬请期待')
              ForEach(this.apiSections, (section: ComicHomeSection) => {
                this.apiSectionView(section)
              }, (section: ComicHomeSection, index: number): string => section.title + '_' + index)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ bottom: 88 })
          }
          .width('100%')
          .scrollBar(BarState.Off)
        }
        .onRefreshing(() => {
          this.loadComicContent();
        })
        .layoutWeight(1)
        .width('100%')
      } else if (this.comicSections.length === 0) {
        Column({ space: 12 }) {
          Image($r('app.media.un_login_icon'))
            .width(120)
            .objectFit(ImageFit.Contain)
          if (this.apiFailed) {
            Text('原版内容加载失败')
              .fontSize(14)
              .fontColor('#333333')
            Text(this.apiError)
              .fontSize(12)
              .fontColor('#999999')
              .maxLines(2)
            Button('重试')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .backgroundColor('#6C5CE7')
              .borderRadius(18)
              .height(36)
              .padding({ left: 20, right: 20 })
              .margin({ top: 8 })
              .onClick(() => {
                this.loadComicContent();
              })
            Text('也可以先导入书源使用书源数据')
              .fontSize(12)
              .fontColor('#BBBBBB')
              .margin({ top: 8 })
              .onClick(() => {
                this.openSourceManage();
              })
          } else {
            Text('暂无书源内容')
              .fontSize(14)
              .fontColor('#999999')
            Text('导入书源后即可浏览漫画与小说')
              .fontSize(12)
              .fontColor('#BBBBBB')
            Button('去导入书源')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .backgroundColor('#6C5CE7')
              .borderRadius(18)
              .height(36)
              .padding({ left: 20, right: 20 })
              .margin({ top: 8 })
              .onClick(() => {
                this.openSourceManage();
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            if (this.bannerBooks.length > 0) {
              this.comicBanner()
            }
            this.noticeBar('书源内容每日更新，点击查看详情')
            ForEach(this.comicSections, (section: ComicSection) => {
              this.comicSectionView(section)
            }, (section: ComicSection): string => section.sourceUrl)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 88 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  apiBanner() {
    Column() {
      Swiper() {
        ForEach(this.apiBanners, (comic: ComicItem) => {
          Stack({ alignContent: Alignment.BottomStart }) {
            Image(comic.picUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .backgroundColor('#EFEEF4')
            Text(comic.comicName)
              .fontSize(13)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000')
              .borderRadius(12)
              .margin(8)
          }
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.openComicDetail(comic);
          })
        }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
      }
      .width('100%')
      .aspectRatio(390 / 294)
      .borderRadius(8)
      .clip(true)
      .indicator(true)
      .autoPlay(true)
      .interval(4000)
      .loop(true)
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 12 })
  }

  @Builder
  apiSectionView(section: ComicHomeSection) {
    Column() {
      Row() {
        if (section.iconUrl !== '') {
          Image(section.iconUrl)
            .width(20)
            .height(20)
            .margin({ right: 6 })
            .objectFit(ImageFit.Contain)
        }
        Text(section.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
          .maxLines(1)
          .layoutWeight(1)
        Row({ space: 2 }) {
          Text('更多')
            .fontSize(12)
            .fontColor('#999999')
          Image($r('app.media.home_right_icon'))
            .width(12)
            .height(12)
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#FFF2F2F2')
        .borderRadius(12)
        .onClick(() => {
          this.openSectionMore(section);
        })
      }
      .width('100%')
      .padding({ top: 16, bottom: 8 })
      if (section.ranks.length > 0) {
        this.apiRankSection(section)
      } else {
        Grid() {
          ForEach(section.comics, (comic: ComicItem) => {
            GridItem() {
              this.apiComicCover(comic)
            }
          }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(12)
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 排行榜分区：四榜单页签 + 带名次榜单列表（数据来自首页 rankList）
   */
  @Builder
  apiRankSection(section: ComicHomeSection) {
    Column() {
      Row({ space: 8 }) {
        ForEach(section.ranks, (rank: ComicRank, index: number) => {
          Text(rank.rankingName)
            .fontSize(13)
            .fontWeight(index === this.rankTabIndex ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.rankTabIndex ? Color.White : '#666666')
            .backgroundColor(index === this.rankTabIndex ? '#6C5CE7' : '#F4F1FF')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .maxLines(1)
            .onClick(() => {
              this.rankTabIndex = index;
            })
        }, (rank: ComicRank): string => rank.rankingCode + '_' + rank.rankingName)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      ForEach(section.ranks[this.rankTabIndex].comics, (comic: ComicItem, index: number) => {
        this.apiRankRow(index, comic)
      }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  apiRankRow(index: number, comic: ComicItem) {
    Row({ space: 10 }) {
      Text(String(index + 1))
        .fontSize(index < 3 ? 17 : 14)
        .fontWeight(FontWeight.Bold)
        .fontColor(index < 3 ? '#FF7043' : '#BBBBBB')
        .width(26)
        .textAlign(TextAlign.Center)
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width(52)
          .height(70)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(this.firstChar(comic.comicName))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(52)
        .height(70)
        .backgroundColor('#8D8D93')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 3 }) {
        Text(comic.comicName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
        Text(comic.author === '' ? '未知作者' : comic.author)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  @Builder
  apiComicCover(comic: ComicItem) {
    Column({ space: 6 }) {
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width('100%')
          .aspectRatio(0.75)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(this.firstChar(comic.comicName))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .aspectRatio(0.75)
        .backgroundColor('#8D8D93')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Text(comic.comicName)
        .fontSize(13)
        .fontColor('#333333')
        .maxLines(2)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  @Builder
  comicBanner() {
    Column() {
      Swiper() {
        ForEach(this.bannerBooks, (book: Book) => {
          Stack({ alignContent: Alignment.BottomStart }) {
            Image(book.coverUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
            Text(book.name)
              .fontSize(13)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000')
              .borderRadius(12)
              .margin(8)
          }
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.openBookInfo(book);
          })
        }, (book: Book): string => book.bookUrl)
      }
      .width('100%')
      .aspectRatio(390 / 294)
      .borderRadius(8)
      .clip(true)
      .indicator(true)
      .autoPlay(true)
      .interval(4000)
      .loop(true)
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 12 })
  }

  @Builder
  comicSectionView(section: ComicSection) {
    Column() {
      Row() {
        Text(section.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
          .maxLines(1)
          .layoutWeight(1)
        Row({ space: 2 }) {
          Text('更多')
            .fontSize(12)
            .fontColor('#999999')
          Image($r('app.media.home_right_icon'))
            .width(12)
            .height(12)
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#FFF2F2F2')
        .borderRadius(12)
        .onClick(() => {
          this.openExplore(section);
        })
      }
      .width('100%')
      .padding({ top: 16, bottom: 8 })
      Grid() {
        ForEach(section.books, (book: Book) => {
          GridItem() {
            this.comicCoverCard(book)
          }
        }, (book: Book): string => section.sourceUrl + book.bookUrl)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8)
      .rowsGap(12)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  comicCoverCard(book: Book) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (book.coverUrl !== '') {
          Image(book.coverUrl)
            .width('100%')
            .aspectRatio(0.75)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        } else {
          Column() {
            Text(this.firstChar(book.name))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width('100%')
          .aspectRatio(0.75)
          .backgroundColor('#8D8D93')
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .onClick(() => {
        this.openBookInfo(book);
      })
      Text(book.name)
        .fontSize(13)
        .fontColor('#333333')
        .maxLines(2)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openBookInfo(book);
    })
  }

  @Builder
  updateSubPage() {
    Column() {
      this.noticeBar('最近更新的漫画')
      if (this.updateLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#6C5CE7')
          Text('正在加载...')
            .fontSize(12)
            .fontColor('#999999')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.updateFailed !== '') {
        Column({ space: 10 }) {
          Text('更新列表加载失败')
            .fontSize(14)
            .fontColor('#333333')
          Text(this.updateFailed)
            .fontSize(12)
            .fontColor('#999999')
            .maxLines(2)
          Text('重试')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .padding({ left: 22, right: 22, top: 8, bottom: 8 })
            .backgroundColor('#6C5CE7')
            .borderRadius(17)
            .margin({ top: 6 })
            .onClick(() => {
              this.loadUpdateComics();
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.updateComics.length === 0) {
        Column({ space: 10 }) {
          Text('暂无更新内容')
            .fontSize(14)
            .fontColor('#999999')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.updateComics, (comic: ComicItem) => {
            ListItem() {
              this.updateComicRow(comic)
            }
          }, (comic: ComicItem): string => comic.comicId + '_' + comic.updateTime)
          ListItem() {
            this.updateFooter()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 88 })
        .scrollBar(BarState.Off)
        .onReachEnd(() => {
          this.loadMoreUpdateComics();
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  updateFooter() {
    Row({ space: 8 }) {
      if (this.updateLoadingMore) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color('#6C5CE7')
        Text('正在加载...')
          .fontSize(12)
          .fontColor('#999999')
      } else {
        Text(this.updateTotal > 0 && this.updateComics.length >= this.updateTotal ? '已全部加载' : '上拉加载更多')
          .fontSize(12)
          .fontColor('#999999')
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  updateComicRow(comic: ComicItem) {
    Row({ space: 12 }) {
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width(64)
          .height(84)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(this.firstChar(comic.comicName))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(64)
        .height(84)
        .backgroundColor('#8D8D93')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 5 }) {
        Text(comic.comicName)
          .fontSize(15)
          .fontColor('#333333')
          .maxLines(1)
        Text(comic.author === '' ? '未知作者' : comic.author)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
        Text(comic.lastEpisodeName === '' ? '更新至 ' + comic.episodeNum + ' 话' : '最新：' + comic.lastEpisodeName)
          .fontSize(12)
          .fontColor('#6C5CE7')
          .maxLines(1)
        Text(comic.updateTime === '' ? '' : comic.updateTime.substring(0, 16))
          .fontSize(11)
          .fontColor('#BBBBBB')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Image($r('app.media.home_right_icon'))
        .width(14)
        .height(14)
        .fillColor('#CCCCCC')
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  @Builder
  novelSubPage() {
    Column() {
      Scroll() {
        Column() {
          this.noticeBar('书海无涯，好书不断')
          if (this.shelfBooks.length > 0) {
            this.novelFeatured(this.shelfBooks[0])
          }
          this.sectionHeader('我的书架', false)
          if (this.shelfBooks.length === 0) {
            Column({ space: 8 }) {
              Text('书架还是空的')
                .fontSize(14)
                .fontColor('#999999')
              Text('点击右上角搜索图标找书')
                .fontSize(12)
                .fontColor('#BBBBBB')
            }
            .width('100%')
            .padding({ top: 40, bottom: 40 })
          } else {
            ForEach(this.shelfBooks, (book: Book) => {
              this.novelBookRow(book)
            }, (book: Book): string => book.bookUrl)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 88 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  novelFeatured(book: Book) {
    Column({ space: 8 }) {
      BookCover({
        coverUrl: book.coverUrl,
        bookName: book.name,
        coverWidth: '100%',
        coverHeight: 170,
        radius: 8,
        textSize: 48
      })
      Row() {
        Text(book.name)
          .fontSize(15)
          .fontColor('#111111')
          .maxLines(1)
          .layoutWeight(1)
        Text(book.author === '' ? book.originName : book.author)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .width('100%')
      if (book.intro !== '') {
        Text(book.intro)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 16 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openBookInfo(book);
    })
  }

  @Builder
  novelBookRow(book: Book) {
    Row({ space: 12 }) {
      BookCover({
        coverUrl: book.coverUrl,
        bookName: book.name,
        coverWidth: 84,
        coverHeight: 112,
        radius: 4,
        textSize: 24
      })
      Column({ space: 4 }) {
        Text(book.name)
          .fontSize(15)
          .fontColor('#333333')
          .maxLines(1)
        Text(book.intro === '' ? '暂无简介' : book.intro)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(2)
        Text(book.durChapterTitle === '' ? '未开始阅读' : book.durChapterTitle)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openBookInfo(book);
    })
  }

  build() {
    Column() {
      Row() {
        Row({ space: 20 }) {
          this.topTabItem('漫画', 0)
          this.topTabItem('更新', 1)
          this.topTabItem('小说', 2)
        }
        .alignItems(VerticalAlign.Center)
        Blank()
        this.rightIconPill()
      }
      .width('100%')
      .padding({ top: this.statusBarVp + 14, bottom: 10, left: 12, right: 12 })
      .backgroundColor('#FFFFFF')

      if (this.currentSubTab === 0) {
        this.comicSubPage()
      } else if (this.currentSubTab === 1) {
        this.updateSubPage()
      } else {
        this.novelSubPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
