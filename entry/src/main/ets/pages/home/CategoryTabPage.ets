/**
 * 分类 Tab：还原原版 category_fragment_layout
 * 顶部 48dp：分类子 Tab + 排行/搜索胶囊
 * 漫画子页：官网 /category 同款筛选（进度/排序/地区/题材）+ 漫画网格无限加载
 * 小说子页：书源发现分类入口
 */
import { BookSource } from '../../model/BookSourceModels';
import { BookSourceRepo } from '../../service/BookSourceRepo';
import { BookService, ExploreCategory } from '../../service/BookService';
import { ExploreDetailParam } from '../../model/BookModels';
import { StorageKeys } from '../../model/ReadConfigModels';
import { Db } from '../../service/Db';
import { ComicApi } from '../../service/ComicApi';
import {
  ComicCategory, ComicItem, ComicParam, ComicSearchResult,
  parseCategoryList, parseSearchResult
} from '../../model/ComicApiModels';

const CACHE_KEY_CATEGORIES: string = 'comic_categories_v1';
const CACHE_KEY_CAT_COMICS: string = 'comic_cat_comics_default_v1';
const COMIC_PAGE_SIZE: number = 36;
const COMBINED_FETCH_SIZE: number = 100;
const REGION_NAMES: string[] = ['国漫', '日漫', '韩漫'];
const SORT_FIELDS: string[] = ['sevendayPlayNum', 'playNum', 'updateTime'];

class CategoryGroup {
  sourceName: string = '';
  sourceUrl: string = '';
  cats: ExploreCategory[] = [];
}

@Component
export struct CategoryTabPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;
  @State currentSubTab: number = 0;
  // 小说子页
  @State groups: CategoryGroup[] = [];
  @State loadingCats: boolean = false;
  @StorageProp(StorageKeys.BOOKSHELF_VERSION) @Watch('onSourceChanged') bookshelfVersion: number = 0;
  // 漫画分类子页
  @State themes: ComicCategory[] = [];
  @State catLoading: boolean = true;
  @State selProgress: number = -1;
  @State selSort: number = 0;
  @State selRegion: number = -1;
  @State selThemeId: string = '';
  @State comics: ComicItem[] = [];
  @State comicsTotal: number = 0;
  @State comicsLoading: boolean = true;
  @State loadingMore: boolean = false;
  @State comicsFailed: string = '';
  @State refreshing: boolean = false;
  private regionIds: string[] = ['', '', ''];
  private comicsPage: number = 1;
  /** 组合筛选（题材+地区）下的服务端原始页码与耗尽标记 */
  private rawPage: number = 1;
  @State rawExhausted: boolean = false;

  aboutToAppear(): void {
    this.loadSources();
    this.loadCategories();
    this.initComics();
  }

  onSourceChanged(): void {
    this.loadSources();
  }

  // ==================== 小说子页（书源发现分类） ====================

  loadSources(): void {
    this.loadingCats = true;
    BookSourceRepo.getInstance().getExploreEnabled().then((list: BookSource[]) => {
      if (list.length === 0) {
        this.groups = [];
        this.loadingCats = false;
        return;
      }
      const loaded: CategoryGroup[] = [];
      let pending: number = list.length;
      for (let i = 0; i < list.length; i++) {
        const src: BookSource = list[i];
        const group: CategoryGroup = new CategoryGroup();
        group.sourceName = src.bookSourceName;
        group.sourceUrl = src.bookSourceUrl;
        loaded.push(group);
        BookService.getInstance().parseExploreCategories(src).then((cats: ExploreCategory[]) => {
          group.cats = cats;
        }).catch(() => {
          group.cats = [];
        }).then(() => {
          pending -= 1;
          if (pending === 0) {
            this.groups = loaded;
            this.loadingCats = false;
          }
        });
      }
    }).catch(() => {
      this.groups = [];
      this.loadingCats = false;
    });
  }

  openGroup(group: CategoryGroup): void {
    const p: ExploreDetailParam = new ExploreDetailParam();
    p.sourceUrl = group.sourceUrl;
    this.pathStack.pushPathByName('exploreDetail', p);
  }

  openSearch(): void {
    this.pathStack.pushPathByName('search', null);
  }

  // ==================== 漫画分类子页 ====================

  loadCategories(): void {
    this.catLoading = true;
    Db.getInstance().getCache(CACHE_KEY_CATEGORIES).then((raw: string) => {
      if (raw !== '') {
        this.applyCategories(raw);
      }
      return raw;
    }).catch(() => {
      return '';
    }).then((cached: string) => {
      ComicApi.getInstance().getComicCategoryListRaw().then((fresh: string) => {
        this.applyCategories(fresh);
        Db.getInstance().setCache(CACHE_KEY_CATEGORIES, fresh).catch(() => {
        });
      }).catch(() => {
        if (cached === '') {
          this.catLoading = false;
        }
      });
    });
  }

  applyCategories(raw: string): void {
    const list: ComicCategory[] = parseCategoryList(raw);
    const themeList: ComicCategory[] = [];
    for (let i = 0; i < list.length; i++) {
      const cat: ComicCategory = list[i];
      let regionIdx: number = -1;
      for (let j = 0; j < REGION_NAMES.length; j++) {
        if (REGION_NAMES[j] === cat.categoryName) {
          regionIdx = j;
          break;
        }
      }
      if (regionIdx >= 0) {
        this.regionIds[regionIdx] = cat.categoryId;
      } else {
        themeList.push(cat);
      }
    }
    this.themes = themeList;
    this.catLoading = false;
  }

  /**
   * 启动时：默认筛选条件下先渲染缓存，再后台拉最新
   */
  initComics(): void {
    Db.getInstance().getCache(CACHE_KEY_CAT_COMICS).then((raw: string) => {
      if (raw !== '' && this.comics.length === 0) {
        const cached: ComicSearchResult = parseSearchResult(raw);
        if (cached.comics.length > 0) {
          this.comics = cached.comics;
          this.comicsTotal = cached.total;
          this.comicsPage = 1;
          this.comicsLoading = false;
        }
      }
    }).catch(() => {
    });
    this.reloadComics(false);
  }

  isDefaultFilter(): boolean {
    return this.selProgress === -1 && this.selSort === 0 && this.selRegion === -1 && this.selThemeId === '';
  }

  isCombined(): boolean {
    return this.selThemeId !== '' && this.selRegion >= 0;
  }

  currentCategoryId(): string {
    if (this.selThemeId !== '') {
      return this.selThemeId;
    }
    if (this.selRegion >= 0) {
      return this.regionIds[this.selRegion];
    }
    return '';
  }

  reloadComics(clearFirst: boolean): void {
    this.comicsPage = 1;
    this.rawPage = 1;
    this.rawExhausted = false;
    this.comicsFailed = '';
    if (clearFirst) {
      this.comics = [];
      this.comicsTotal = 0;
      this.comicsLoading = true;
    }
    const combined: boolean = this.isCombined();
    const categoryId: string = this.currentCategoryId();
    ComicApi.getInstance().browseComicsRaw(1, combined ? COMBINED_FETCH_SIZE : COMIC_PAGE_SIZE,
      SORT_FIELDS[this.selSort], this.selProgress, categoryId).then((raw: string) => {
      const result: ComicSearchResult = parseSearchResult(raw);
      let list: ComicItem[] = result.comics;
      if (combined) {
        if (result.comics.length < COMBINED_FETCH_SIZE) {
          this.rawExhausted = true;
        }
        list = this.filterByRegion(list);
      }
      this.comics = list;
      this.comicsTotal = combined ? list.length : result.total;
      this.comicsLoading = false;
      this.refreshing = false;
      if (this.isDefaultFilter() && !combined) {
        Db.getInstance().setCache(CACHE_KEY_CAT_COMICS, raw).catch(() => {
        });
      }
    }).catch((e: Error) => {
      if (this.comics.length === 0) {
        this.comicsFailed = e.message;
        this.comicsLoading = false;
      }
      this.refreshing = false;
    });
  }

  loadMoreComics(): void {
    if (this.loadingMore || this.comics.length === 0) {
      return;
    }
    if (this.isCombined()) {
      if (this.rawExhausted) {
        return;
      }
      this.fetchCombinedMore();
      return;
    }
    if (this.comics.length >= this.comicsTotal) {
      return;
    }
    this.comicsPage += 1;
    this.loadingMore = true;
    const categoryId: string = this.currentCategoryId();
    ComicApi.getInstance().browseComics(this.comicsPage, COMIC_PAGE_SIZE,
      SORT_FIELDS[this.selSort], this.selProgress, categoryId).then((result: ComicSearchResult) => {
      this.comics = this.comics.concat(result.comics);
      this.loadingMore = false;
    }).catch(() => {
      this.comicsPage -= 1;
      this.loadingMore = false;
    });
  }

  /**
   * 组合筛选分页：继续拉下一批服务端原始数据（每批 100 条），本地按地区过滤追加；
   * 本批过滤后为空且原始数据未耗尽时自动续拉下一批
   */
  fetchCombinedMore(): void {
    this.loadingMore = true;
    this.rawPage += 1;
    const categoryId: string = this.currentCategoryId();
    ComicApi.getInstance().browseComicsRaw(this.rawPage, COMBINED_FETCH_SIZE,
      SORT_FIELDS[this.selSort], this.selProgress, categoryId).then((raw: string) => {
      const result: ComicSearchResult = parseSearchResult(raw);
      if (result.comics.length < COMBINED_FETCH_SIZE) {
        this.rawExhausted = true;
      }
      const filtered: ComicItem[] = this.filterByRegion(result.comics);
      if (filtered.length > 0) {
        const seen: Set<string> = new Set<string>();
        for (let i = 0; i < this.comics.length; i++) {
          seen.add(this.comics[i].comicId);
        }
        const merged: ComicItem[] = this.comics.slice();
        for (let i = 0; i < filtered.length; i++) {
          if (!seen.has(filtered[i].comicId)) {
            merged.push(filtered[i]);
          }
        }
        this.comics = merged;
        this.comicsTotal = merged.length;
        this.loadingMore = false;
      } else if (!this.rawExhausted) {
        this.fetchCombinedMore();
      } else {
        this.loadingMore = false;
      }
    }).catch(() => {
      this.rawPage -= 1;
      this.loadingMore = false;
    });
  }

  /**
   * 列表是否已无更多数据（普通筛选看 total，组合筛选看原始数据是否耗尽）
   */
  noMoreComics(): boolean {
    if (this.isCombined()) {
      return this.rawExhausted;
    }
    return this.comics.length >= this.comicsTotal;
  }

  /**
   * 题材 + 地区组合：按地区名在返回结果中客户端过滤（与官网行为一致）
   */
  filterByRegion(list: ComicItem[]): ComicItem[] {
    const regionName: string = REGION_NAMES[this.selRegion];
    const filtered: ComicItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const comic: ComicItem = list[i];
      if (comic.categories.indexOf(regionName) >= 0 || comic.categoryName.indexOf(regionName) >= 0) {
        filtered.push(comic);
      }
    }
    return filtered;
  }

  openComicDetail(comic: ComicItem): void {
    const p: ComicParam = new ComicParam();
    p.comicId = comic.comicId;
    p.comicName = comic.comicName;
    p.picUrl = comic.picUrl;
    this.pathStack.pushPathByName('comicDetail', p);
  }

  listTitle(): string {
    if (this.selThemeId !== '') {
      for (let i = 0; i < this.themes.length; i++) {
        if (this.themes[i].categoryId === this.selThemeId) {
          return this.themes[i].categoryName;
        }
      }
      return '题材';
    }
    if (this.selRegion >= 0) {
      return REGION_NAMES[this.selRegion];
    }
    return '全部漫画';
  }

  categorySubtitle(comic: ComicItem): string {
    const parts: string[] = [];
    if (comic.categoryName !== '') {
      parts.push(comic.categoryName);
    }
    for (let i = 0; i < comic.categories.length && parts.length < 2; i++) {
      const c: string = comic.categories[i];
      if (c !== '' && parts.indexOf(c) < 0) {
        parts.push(c);
      }
    }
    return parts.join(' · ');
  }

  firstChar(name: string): string {
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '漫';
  }

  // ==================== 通用 UI ====================

  @Builder
  catTabItem(title: string, index: number) {
    Text(title)
      .fontSize(16)
      .fontWeight(index === this.currentSubTab ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(index === this.currentSubTab ? '#333333' : '#999999')
      .padding({ left: 6, right: 6 })
      .onClick(() => {
        this.currentSubTab = index;
      })
  }

  @Builder
  rightIconPill() {
    Row({ space: 6 }) {
      Image($r('app.media.home_right_rank_icon'))
        .width(24)
        .height(24)
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

  // ==================== 漫画分类 UI ====================

  @Builder
  progressChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selProgress === value ? '#FFFFFF' : '#666666')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.selProgress === value ? '#6C5CE7' : '#F3F5F7')
      .borderRadius(14)
      .onClick(() => {
        if (this.selProgress !== value) {
          this.selProgress = value;
          this.reloadComics(true);
        }
      })
  }

  @Builder
  sortChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selSort === value ? '#FFFFFF' : '#666666')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.selSort === value ? '#6C5CE7' : '#F3F5F7')
      .borderRadius(14)
      .onClick(() => {
        if (this.selSort !== value) {
          this.selSort = value;
          this.reloadComics(true);
        }
      })
  }

  @Builder
  regionChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selRegion === value ? '#FFFFFF' : '#666666')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.selRegion === value ? '#6C5CE7' : '#F3F5F7')
      .borderRadius(14)
      .onClick(() => {
        if (this.selRegion !== value) {
          this.selRegion = value;
          this.reloadComics(true);
        }
      })
  }

  @Builder
  themeChip(label: string, id: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selThemeId === id ? '#FFFFFF' : '#666666')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.selThemeId === id ? '#6C5CE7' : '#F3F5F7')
      .borderRadius(14)
      .onClick(() => {
        if (this.selThemeId !== id) {
          this.selThemeId = id;
          this.reloadComics(true);
        }
      })
  }

  @Builder
  comicCell(comic: ComicItem) {
    Column({ space: 5 }) {
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
        .maxLines(1)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text(this.categorySubtitle(comic))
        .fontSize(11)
        .fontColor('#999999')
        .maxLines(1)
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
  comicFilterPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('进度')
          .fontSize(12)
          .fontColor('#999999')
          .width(30)
        this.progressChip('全部', -1)
        this.progressChip('连载中', 0)
        this.progressChip('已完结', 1)
      }
      .width('100%')
      Row({ space: 8 }) {
        Text('排序')
          .fontSize(12)
          .fontColor('#999999')
          .width(30)
        this.sortChip('热度', 0)
        this.sortChip('人气', 1)
        this.sortChip('最新', 2)
      }
      .width('100%')
      Row({ space: 8 }) {
        Text('地区')
          .fontSize(12)
          .fontColor('#999999')
          .width(30)
        this.regionChip('全部', -1)
        this.regionChip('国漫', 0)
        this.regionChip('日漫', 1)
        this.regionChip('韩漫', 2)
      }
      .width('100%')
      if (!this.catLoading) {
        Row({ space: 8 }) {
          Text('题材')
            .fontSize(12)
            .fontColor('#999999')
            .width(30)
          Scroll() {
            Row({ space: 8 }) {
              this.themeChip('全部', '')
              ForEach(this.themes, (cat: ComicCategory) => {
                this.themeChip(cat.categoryName, cat.categoryId)
              }, (cat: ComicCategory): string => cat.categoryId)
            }
          }
          .layoutWeight(1)
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  comicCategoryContent() {
    Column() {
      this.comicFilterPanel()
      if (this.comicsLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.comics.length === 0 && this.comicsFailed !== '') {
        Column({ space: 10 }) {
          Text('加载失败')
            .fontSize(14)
            .fontColor('#999999')
          Text('点击重试')
            .fontSize(13)
            .fontColor('#6C5CE7')
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(16)
            .border({ width: 1, color: '#6C5CE7' })
            .onClick(() => {
              this.reloadComics(true);
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.comics.length === 0) {
        Column() {
          Text('暂无符合条件的作品')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              Row() {
                Text(this.listTitle())
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111111')
                Text('  共 ' + this.comicsTotal + ' 部')
                  .fontSize(12)
                  .fontColor('#999999')
              }
              .width('100%')
              .padding({ top: 12, bottom: 8 })
              Grid() {
                ForEach(this.comics, (comic: ComicItem) => {
                  GridItem() {
                    this.comicCell(comic)
                  }
                }, (comic: ComicItem): string => comic.comicId)
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(10)
              .rowsGap(14)
              .width('100%')
              if (this.loadingMore) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#999999')
                  Text('正在加载...')
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .padding({ top: 14, bottom: 14 })
              } else if (this.noMoreComics()) {
                Text('没有更多了')
                  .fontSize(12)
                  .fontColor('#BBBBBB')
                  .padding({ top: 14, bottom: 14 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, bottom: 88 })
          }
          .width('100%')
          .onReachEnd(() => {
            this.loadMoreComics();
          })
          .scrollBar(BarState.Off)
        }
        .onRefreshing(() => {
          this.reloadComics(false);
        })
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 小说分类 UI ====================

  @Builder
  groupCard(group: CategoryGroup) {
    Column({ space: 8 }) {
      Row() {
        Text(group.sourceName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
          .layoutWeight(1)
        Image($r('app.media.home_right_icon'))
          .width(12)
          .height(12)
      }
      .width('100%')
      if (group.cats.length === 0) {
        Text('该书源未提供发现分类')
          .fontSize(12)
          .fontColor('#999999')
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(group.cats, (cat: ExploreCategory, index: number) => {
            Text(cat.title)
              .fontSize(13)
              .fontColor('#333333')
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .margin(4)
              .backgroundColor('#F3F5F7')
              .borderRadius(14)
              .onClick(() => {
                this.openGroup(group);
              })
          }, (cat: ExploreCategory, index: number): string => group.sourceUrl + cat.title + index)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .margin({ top: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .onClick(() => {
      this.openGroup(group);
    })
  }

  @Builder
  novelCategoryContent() {
    if (this.loadingCats) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color('#999999')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.groups.length === 0) {
      Column({ space: 8 }) {
        Text('暂无分类')
          .fontSize(14)
          .fontColor('#999999')
        Text('请先导入含发现规则的书源')
          .fontSize(12)
          .fontColor('#BBBBBB')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.groups, (group: CategoryGroup) => {
            this.groupCard(group)
          }, (group: CategoryGroup): string => group.sourceUrl)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 88 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  build() {
    Column() {
      Row() {
        Row({ space: 20 }) {
          this.catTabItem('漫画', 0)
          this.catTabItem('小说', 1)
          this.catTabItem('短剧', 2)
        }
        .alignItems(VerticalAlign.Center)
        Blank()
        this.rightIconPill()
      }
      .width('100%')
      .height(48 + this.statusBarVp)
      .padding({ top: this.statusBarVp, left: 12, right: 12 })
      .backgroundColor('#FFFFFF')

      if (this.currentSubTab === 0) {
        this.comicCategoryContent()
      } else if (this.currentSubTab === 1) {
        this.novelCategoryContent()
      } else {
        Column() {
          Text('短剧分类敬请期待')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}
