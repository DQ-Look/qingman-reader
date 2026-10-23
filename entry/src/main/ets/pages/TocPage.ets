/**
 * 目录数据源：支持正序/倒序切换
 */
import { Book, Chapter, TocPageParam, ReadingPageParam } from '../model/BookModels';
import { Db } from '../service/Db';
import { BookService } from '../service/BookService';
import { StorageKeys } from '../model/ReadConfigModels';

export class ChapterDataSource implements IDataSource {
  private items: Chapter[] = [];
  private display: Chapter[] = [];
  private reversed: boolean = false;
  private listener: DataChangeListener | null = null;

  constructor() {
  }

  private rebuild(): void {
    const list: Chapter[] = [];
    if (this.reversed) {
      for (let i = this.items.length - 1; i >= 0; i--) {
        list.push(this.items[i]);
      }
    } else {
      for (let i = 0; i < this.items.length; i++) {
        list.push(this.items[i]);
      }
    }
    this.display = list;
    if (this.listener !== null) {
      this.listener.onDataReloaded();
    }
  }

  setItems(items: Chapter[]): void {
    this.items = items;
    this.rebuild();
  }

  setReversed(reversed: boolean): void {
    if (this.reversed === reversed) {
      return;
    }
    this.reversed = reversed;
    this.rebuild();
  }

  totalCount(): number {
    return this.display.length;
  }

  getData(index: number): Chapter {
    return this.display[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listener = listener;
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listener = null;
  }
}

/**
 * 目录页：章节列表，支持倒序、定位当前章
 */
@Component
struct TocPage {
  bookUrl: string = '';
  currentChapter: number = 0;
  fromReading: boolean = false;
  @State chapters: Chapter[] = [];
  @State loading: boolean = true;
  @State failedMsg: string = '';
  @State reversed: boolean = false;
  @State book: Book = new Book();
  dataSource: ChapterDataSource = new ChapterDataSource();
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  loadChapters(): void {
    this.loading = true;
    this.failedMsg = '';
    const db: Db = Db.getInstance();
    db.getBook(this.bookUrl).then((book: Book | null) => {
      if (book !== null) {
        this.book = book;
      }
      return db.getChapters(this.bookUrl);
    }).then((chapters: Chapter[]) => {
      if (chapters.length > 0) {
        return chapters;
      }
      return BookService.getInstance().loadToc(this.book).then((fresh: Chapter[]) => {
        return db.saveChapters(this.book.bookUrl, fresh).then(() => fresh);
      });
    }).then((chapters: Chapter[]) => {
      this.chapters = chapters;
      this.dataSource.setItems(chapters);
      this.loading = false;
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  selectChapter(index: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READ_TARGET_INDEX, index);
    AppStorage.setOrCreate<number>(StorageKeys.READ_TARGET_VERSION,
      (AppStorage.get<number>(StorageKeys.READ_TARGET_VERSION) ?? 0) + 1);
    if (this.fromReading) {
      this.navPathStack.pop();
    } else {
      const p: ReadingPageParam = new ReadingPageParam();
      p.bookUrl = this.bookUrl;
      p.chapterIndex = index;
      this.navPathStack.pushPathByName('reading', p);
    }
  }

  build() {
    NavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.colorPrimary)
            Text('正在加载目录…')
              .fontSize(14)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.failedMsg !== '') {
            Column({ space: 8 }) {
              Text('目录加载失败')
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
                  this.loadChapters();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Row() {
              Text('共 ' + this.chapters.length + ' 章')
                .fontSize(13)
                .fontColor(this.textSecondary)
                .layoutWeight(1)
              Button(this.reversed ? '倒序' : '正序')
                .fontSize(12)
                .height(30)
                .backgroundColor(Color.Transparent)
                .fontColor(this.colorPrimary)
                .onClick(() => {
                  this.reversed = !this.reversed;
                  this.dataSource.setReversed(this.reversed);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 8 })

            List() {
              LazyForEach(this.dataSource, (chapter: Chapter) => {
                ListItem() {
                  Row() {
                    Text(chapter.title)
                      .fontSize(14)
                      .fontColor(chapter.chapterIndex === this.currentChapter ? this.colorAccent : this.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (chapter.isVip) {
                      Text('VIP')
                        .fontSize(10)
                        .fontColor(this.colorAccent)
                        .border({ width: 0.5, color: this.colorAccent })
                        .borderRadius(2)
                        .padding({ left: 3, right: 3 })
                    }
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .onClick(() => {
                    this.selectChapter(chapter.chapterIndex);
                  })
                }
              }, (chapter: Chapter) => chapter.bookUrl + '#' + chapter.chapterIndex)
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
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
    }
    .title('目录')
    .backgroundColor(this.bgColor)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: TocPageParam = ctx.pathInfo.param as TocPageParam;
      if (p instanceof TocPageParam) {
        this.bookUrl = p.bookUrl;
        this.currentChapter = p.currentChapter;
        this.fromReading = p.fromReading;
        this.loadChapters();
      }
    })
  }
}

@Builder
export function TocPageBuilder() {
  TocPage()
}
