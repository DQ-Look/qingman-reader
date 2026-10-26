/**
 * 搜索页：漫画 API 搜索（分页加载更多）+ 书源搜索，含本地搜索历史
 */
import { Book, BookInfoParam } from '../model/BookModels';
import { BookSource } from '../model/BookSourceModels';
import { BookSourceRepo } from '../service/BookSourceRepo';
import { searchAllSources, SourceSearchGroup } from '../service/SearchService';
import { StorageKeys } from '../model/ReadConfigModels';
import { BookCover } from '../components/BookCover';
import { ComicItem, ComicParam, ComicSearchResult } from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { Db } from '../service/Db';

const COMIC_PAGE_SIZE: number = 20;

@Component
struct SearchPage {
  @State keyword: string = '';
  @State groups: SourceSearchGroup[] = [];
  @State searching: boolean = false;
  @State finishedCount: number = 0;
  @State totalCount: number = 0;
  @State comicList: ComicItem[] = [];
  @State comicTotal: number = 0;
  @State comicPage: number = 0;
  @State comicLoadingMore: boolean = false;
  @State comicFailed: string = '';
  @State hasSearched: boolean = false;
  @State historyKeywords: string[] = [];
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;

  loadHistory(): void {
    Db.getInstance().getSearchHistory().then((list: string[]) => {
      this.historyKeywords = list;
    }).catch(() => {
      this.historyKeywords = [];
    });
  }

  searchComicPage(kw: string, page: number): void {
    this.comicLoadingMore = true;
    ComicApi.getInstance().searchComics(kw, page, COMIC_PAGE_SIZE).then((res: ComicSearchResult) => {
      if (page === 1) {
        this.comicList = res.comics;
      } else {
        const merged: ComicItem[] = this.comicList.slice();
        for (let i = 0; i < res.comics.length; i++) {
          merged.push(res.comics[i]);
        }
        this.comicList = merged;
      }
      this.comicTotal = res.total;
      this.comicPage = page;
      this.comicLoadingMore = false;
    }).catch((e: Error) => {
      if (page === 1) {
        this.comicFailed = e.message;
      }
      this.comicLoadingMore = false;
    });
  }

  loadMoreComics(): void {
    if (!this.hasSearched || this.keyword === '' || this.comicLoadingMore || this.comicFailed !== '') {
      return;
    }
    if (this.comicList.length >= this.comicTotal) {
      return;
    }
    this.searchComicPage(this.keyword, this.comicPage + 1);
  }

  searchSources(kw: string): void {
    BookSourceRepo.getInstance().getEnabled().then((sources: BookSource[]) => {
      const usable: BookSource[] = [];
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].hasSearch()) {
          usable.push(sources[i]);
        }
      }
      this.totalCount = usable.length;
      if (usable.length === 0) {
        this.searching = false;
        return;
      }
      return searchAllSources(kw, usable, (group: SourceSearchGroup) => {
        this.groups.push(group);
        this.finishedCount++;
      });
    }).then(() => {
      this.searching = false;
    }).catch(() => {
      this.searching = false;
    });
  }

  doSearch(key: string): void {
    const kw: string = key.trim();
    if (kw === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入搜索内容' });
      return;
    }
    this.keyword = kw;
    this.hasSearched = true;
    this.comicList = [];
    this.comicTotal = 0;
    this.comicPage = 0;
    this.comicFailed = '';
    this.groups = [];
    this.searching = true;
    this.finishedCount = 0;
    this.totalCount = 0;
    this.searchComicPage(kw, 1);
    Db.getInstance().saveSearchKeyword(kw).then(() => {
      this.loadHistory();
    }).catch(() => {
    });
    this.searchSources(kw);
  }

  clearHistory(): void {
    Db.getInstance().clearSearchHistory().then(() => {
      this.historyKeywords = [];
    }).catch(() => {
    });
  }

  statusText(group: SourceSearchGroup): string {
    if (group.status === 'ok') {
      return group.books.length + ' 本';
    }
    if (group.status === 'empty') {
      return '无结果';
    }
    if (group.status === 'unsupported') {
      return '规则不支持';
    }
    return '失败';
  }

  openBook(book: Book): void {
    const p: BookInfoParam = new BookInfoParam();
    p.book = book;
    this.navPathStack.pushPathByName('bookInfo', p);
  }

  openComicDetail(comic: ComicItem): void {
    const p: ComicParam = new ComicParam();
    p.comicId = comic.comicId;
    p.comicName = comic.comicName;
    p.picUrl = comic.picUrl;
    this.navPathStack.pushPathByName('comicDetail', p);
  }

  firstChar(name: string): string {
    if (name.length > 0) {
      return name.substring(0, 1);
    }
    return '漫';
  }

  @Builder
  historyPanel() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary)
        Blank()
        if (this.historyKeywords.length > 0) {
          Text('清空')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => {
              this.clearHistory();
            })
        }
      }
      .width('100%')
      if (this.historyKeywords.length === 0) {
        Text('暂无搜索历史')
          .fontSize(13)
          .fontColor(this.textSecondary)
          .margin({ top: 40 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.historyKeywords, (kw: string) => {
            Text(kw)
              .fontSize(13)
              .fontColor(this.textPrimary)
              .maxLines(1)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor('#F2F2F2')
              .borderRadius(16)
              .margin({ right: 8, bottom: 8, top: 2 })
              .onClick(() => {
                this.doSearch(kw);
              })
          }, (kw: string): string => kw)
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 16 })
  }

  @Builder
  comicGroupHeader() {
    Row({ space: 6 }) {
      Text('漫画')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary)
      Text(this.comicFailed === '' ? '共 ' + this.comicTotal + ' 个结果' : '加载失败')
        .fontSize(12)
        .fontColor(this.textSecondary)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 8 })
    .backgroundColor(this.bgColor)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  comicFailedItem() {
    Column({ space: 8 }) {
      Text('漫画搜索失败')
        .fontSize(14)
        .fontColor(this.textPrimary)
      Text(this.comicFailed)
        .fontSize(12)
        .fontColor(this.textSecondary)
        .maxLines(2)
      Text('重试')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 22, right: 22, top: 8, bottom: 8 })
        .backgroundColor('#6C5CE7')
        .borderRadius(17)
        .margin({ top: 4 })
        .onClick(() => {
          this.comicFailed = '';
          this.searchComicPage(this.keyword, 1);
        })
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  comicEmptyItem() {
    Column() {
      Text('未找到相关漫画')
        .fontSize(13)
        .fontColor(this.textSecondary)
        .padding({ top: 20, bottom: 20 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  comicMoreItem() {
    Row({ space: 8 }) {
      if (this.comicLoadingMore) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.colorPrimary)
        Text('正在加载...')
          .fontSize(12)
          .fontColor(this.textSecondary)
      } else {
        Text(this.comicList.length >= this.comicTotal ? '已全部加载' : '上拉加载更多')
          .fontSize(12)
          .fontColor(this.textSecondary)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  comicRow(comic: ComicItem) {
    Row({ space: 12 }) {
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width(56)
          .height(74)
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
      } else {
        Column() {
          Text(this.firstChar(comic.comicName))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(56)
        .height(74)
        .backgroundColor('#8D8D93')
        .borderRadius(4)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text(comic.comicName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(comic.author === '' ? '未知作者' : comic.author)
          .fontSize(12)
          .fontColor(this.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (comic.episodeNum > 0) {
          Text('更新至 ' + comic.episodeNum + ' 话' + (comic.lastEpisodeName === '' ? '' : ' · ' + comic.lastEpisodeName))
            .fontSize(11)
            .fontColor(this.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.textSecondary])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  @Builder
  groupHeader(group: SourceSearchGroup) {
    Row() {
      Text(group.source.bookSourceName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.statusText(group))
        .fontSize(12)
        .fontColor(this.textSecondary)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(this.bgColor)
  }

  @Builder
  bookRow(book: Book) {
    Row({ space: 12 }) {
      BookCover({
        coverUrl: book.coverUrl,
        bookName: book.name,
        coverWidth: 44,
        coverHeight: 60,
        textSize: 16,
        radius: 3
      })
      Column({ space: 4 }) {
        Text(book.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.author !== '' ? book.author : '未知作者')
          .fontSize(12)
          .fontColor(this.textSecondary)
          .maxLines(1)
        if (book.latestChapterTitle !== '') {
          Text(book.latestChapterTitle)
            .fontSize(11)
            .fontColor(this.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.textSecondary])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openBook(book);
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 2 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(26)
              .fontColor([this.textPrimary])
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            if (this.navPathStack.size() > 0) {
              this.navPathStack.pop();
            }
          })

          Search({ placeholder: '搜索漫画 / 书名 / 作者', value: this.keyword })
            .searchButton('搜索')
            .height(40)
            .backgroundColor(Color.White)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.keyword = value;
            })
            .onSubmit((value: string) => {
              this.doSearch(value);
            })
        }
        .width('100%')
        .padding({ top: this.statusBarVp + 6, left: 6, right: 12, bottom: 4 })
        .alignItems(VerticalAlign.Center)

        if (this.searching || (this.comicLoadingMore && this.comicList.length === 0)) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.colorPrimary)
            Text('正在搜索...')
              .fontSize(12)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 10, bottom: 10 })
        }

        if (!this.hasSearched) {
          Scroll() {
            Column() {
              this.historyPanel()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        } else if (this.comicFailed !== '' && this.comicList.length === 0 && !this.searching) {
          Scroll() {
            Column() {
              this.comicFailedItem()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        } else if (!this.searching && this.comicList.length === 0 && this.groups.length === 0) {
          Column() {
            Text('暂无搜索结果')
              .fontSize(14)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ListItemGroup({ space: 0, header: (): void => { this.comicGroupHeader() } }) {
              if (this.comicFailed !== '' && this.comicList.length === 0) {
                ListItem() {
                  this.comicFailedItem()
                }
              } else if (this.comicList.length === 0 && (this.searching || this.comicLoadingMore)) {
                ListItem() {
                  Column({ space: 10 }) {
                    LoadingProgress()
                      .width(28)
                      .height(28)
                      .color(this.colorPrimary)
                    Text('正在搜索漫画...')
                      .fontSize(13)
                      .fontColor(this.textSecondary)
                  }
                  .width('100%')
                  .padding({ top: 28, bottom: 28 })
                  .alignItems(HorizontalAlign.Center)
                }
              } else if (this.comicList.length === 0 && !this.searching && !this.comicLoadingMore) {
                ListItem() {
                  this.comicEmptyItem()
                }
              }
              ForEach(this.comicList, (comic: ComicItem) => {
                ListItem() {
                  this.comicRow(comic)
                }
              }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
              if (this.comicList.length > 0) {
                ListItem() {
                  this.comicMoreItem()
                }
              }
            }
            .divider({
              strokeWidth: 0.5,
              color: this.dividerColor,
              startMargin: 16,
              endMargin: 16
            })
            ForEach(this.groups, (group: SourceSearchGroup) => {
              ListItemGroup({ space: 0, header: (): void => { this.groupHeader(group) } }) {
                ForEach(group.books, (book: Book) => {
                  ListItem() {
                    this.bookRow(book)
                  }
                }, (book: Book): string => book.bookUrl)
              }
              .divider({
                strokeWidth: 0.5,
                color: this.dividerColor,
                startMargin: 16,
                endMargin: 16
              })
            }, (group: SourceSearchGroup) => group.source.bookSourceUrl + '#' + group.books.length)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .onReachEnd(() => {
            this.loadMoreComics();
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgColor)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      this.loadHistory();
      const param: string = ctx.pathInfo.param as string;
      if (typeof param === 'string' && param.trim() !== '') {
        this.doSearch(param);
      }
    })
  }
}

@Builder
export function SearchPageBuilder() {
  SearchPage()
}
