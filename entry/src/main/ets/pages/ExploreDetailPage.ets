/**
 * 发现详情页：书源分类 + 分类书籍列表 + 翻页
 */
import { Book, ExploreDetailParam, BookInfoParam } from '../model/BookModels';
import { BookSource } from '../model/BookSourceModels';
import { BookSourceRepo } from '../service/BookSourceRepo';
import { BookService, ExploreCategory } from '../service/BookService';
import { StorageKeys } from '../model/ReadConfigModels';
import { BookCover } from '../components/BookCover';

@Component
struct ExploreDetailPage {
  sourceUrl: string = '';
  source: BookSource = new BookSource();
  @State categories: ExploreCategory[] = [];
  @State selectedCategory: number = 0;
  @State books: Book[] = [];
  @State page: number = 1;
  @State loading: boolean = true;
  @State failedMsg: string = '';
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  /** 手势条避让高度（vp）：全局全屏后内容铺满屏幕底部，底部翻页栏需上移 */
  @StorageProp(StorageKeys.SAFE_AREA_BOTTOM_VP) navBarVp: number = 24;
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  init(): void {
    this.loading = true;
    this.failedMsg = '';
    BookSourceRepo.getInstance().getByUrl(this.sourceUrl).then((source: BookSource | null) => {
      if (source === null) {
        this.failedMsg = '书源不存在或已被删除';
        this.loading = false;
        return;
      }
      this.source = source;
      return BookService.getInstance().parseExploreCategories(source).then((cats: ExploreCategory[]) => {
        this.categories = cats;
        this.loadPage(1);
      });
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  loadPage(page: number): void {
    if (this.categories.length === 0) {
      return;
    }
    this.page = page;
    this.loading = true;
    this.failedMsg = '';
    const category: ExploreCategory = this.categories[this.selectedCategory];
    BookService.getInstance().exploreByCategory(this.source, category.url, page).then((books: Book[]) => {
      this.books = books;
      this.loading = false;
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  selectCategory(index: number): void {
    if (index === this.selectedCategory) {
      return;
    }
    this.selectedCategory = index;
    this.loadPage(1);
  }

  openBook(book: Book): void {
    const p: BookInfoParam = new BookInfoParam();
    p.book = book;
    this.navPathStack.pushPathByName('bookInfo', p);
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.categories, (category: ExploreCategory, index: number) => {
              Text(category.title)
                .fontSize(13)
                .fontColor(index === this.selectedCategory ? Color.White : this.textPrimary)
                .backgroundColor(index === this.selectedCategory ? this.colorPrimary : this.dividerColor)
                .borderRadius(14)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .maxLines(1)
                .onClick(() => {
                  this.selectCategory(index);
                })
            }, (category: ExploreCategory) => category.title + '#' + category.url)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.colorPrimary)
            Text('正在加载…')
              .fontSize(14)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.failedMsg !== '') {
            Column({ space: 8 }) {
              Text('加载失败')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.textPrimary)
              Text(this.failedMsg)
                .fontSize(13)
                .fontColor(this.textSecondary)
              Button('重试')
                .backgroundColor(this.colorPrimary)
                .fontColor(Color.White)
                .margin({ top: 8 })
                .onClick(() => {
                  this.loadPage(this.page);
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.books.length === 0) {
              Column() {
                Text('本页没有内容')
                  .fontSize(14)
                  .fontColor(this.textSecondary)
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              List() {
                ForEach(this.books, (book: Book) => {
                  ListItem() {
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
                        if (book.kind !== '') {
                          Text(book.kind.split(',').join(' · '))
                            .fontSize(11)
                            .fontColor(this.colorPrimary)
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
                }, (book: Book) => book.bookUrl)
              }
              .layoutWeight(1)
              .width('100%')
              .divider({
                strokeWidth: 0.5,
                color: this.dividerColor,
                startMargin: 16,
                endMargin: 16
              })
              .scrollBar(BarState.Off)
            }

            Row({ space: 16 }) {
              Button('上一页')
                .fontSize(13)
                .height(34)
                .backgroundColor(Color.Transparent)
                .fontColor(this.page > 1 ? this.colorPrimary : this.textSecondary)
                .border({
                  width: 1,
                  color: this.page > 1 ? this.colorPrimary : this.dividerColor
                })
                .enabled(this.page > 1)
                .onClick(() => {
                  this.loadPage(this.page - 1);
                })
              Text('第 ' + this.page + ' 页')
                .fontSize(13)
                .fontColor(this.textSecondary)
              Button('下一页')
                .fontSize(13)
                .height(34)
                .backgroundColor(Color.Transparent)
                .fontColor(this.colorPrimary)
                .border({ width: 1, color: this.colorPrimary })
                .onClick(() => {
                  this.loadPage(this.page + 1);
                })
            }
            .width('100%')
            .height(52 + this.navBarVp)
            .padding({ bottom: this.navBarVp })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
    }
    .title(this.source.bookSourceName)
    .backgroundColor(this.bgColor)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ExploreDetailParam = ctx.pathInfo.param as ExploreDetailParam;
      if (p instanceof ExploreDetailParam) {
        this.sourceUrl = p.sourceUrl;
        this.init();
      }
    })
  }
}

@Builder
export function ExploreDetailPageBuilder() {
  ExploreDetailPage()
}
