/**
 * 书籍详情页：展示书籍信息，加入书架 / 开始阅读 / 查看目录
 */
import { Book, BookInfoParam, ReadingPageParam, TocPageParam } from '../model/BookModels';
import { Db } from '../service/Db';
import { BookService } from '../service/BookService';
import { StorageKeys } from '../model/ReadConfigModels';
import { BookCover } from '../components/BookCover';
import { PageHeader } from '../common/PageHeader';

@Component
struct BookInfoPage {
  brief: Book = new Book();
  @State book: Book = new Book();
  @State onShelf: boolean = false;
  @State loading: boolean = true;
  @State failedMsg: string = '';
  @State chapterCount: number = 0;
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  initData(): Promise<void> {
    const db: Db = Db.getInstance();
    return db.getBook(this.brief.bookUrl).then((saved: Book | null) => {
      if (saved !== null) {
        this.onShelf = true;
        this.book = saved;
        return db.getChapterCount(saved.bookUrl).then((count: number) => {
          this.chapterCount = count;
          return this.loadDetail();
        });
      }
      return this.loadDetail();
    });
  }

  loadDetail(): Promise<void> {
    this.loading = true;
    this.failedMsg = '';
    return BookService.getInstance().loadBookInfo(this.brief).then((full: Book) => {
      if (this.onShelf) {
        // 保留本地阅读进度，仅更新展示信息
        full.durChapterIndex = this.book.durChapterIndex;
        full.durChapterTitle = this.book.durChapterTitle;
        full.durChapterPos = this.book.durChapterPos;
      }
      this.book = full;
      this.loading = false;
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  addToShelf(): void {
    if (this.onShelf) {
      return;
    }
    Db.getInstance().saveBook(this.book).then(() => {
      this.onShelf = true;
      AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
        (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已加入书架' });
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '加入书架失败' });
    });
  }

  startReading(): void {
    const db: Db = Db.getInstance();
    db.getBook(this.book.bookUrl).then((saved: Book | null) => {
      const target: Book = saved !== null ? saved : this.book;
      if (saved === null) {
        return db.saveBook(target).then(() => {
          AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
            (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
        });
      }
      return Promise.resolve();
    }).then(() => {
      const p: ReadingPageParam = new ReadingPageParam();
      p.bookUrl = this.book.bookUrl;
      p.chapterIndex = this.onShelf ? this.book.durChapterIndex : 0;
      this.navPathStack.pushPathByName('reading', p);
    });
  }

  openToc(): void {
    const p: TocPageParam = new TocPageParam();
    p.bookUrl = this.book.bookUrl;
    p.currentChapter = this.book.durChapterIndex;
    p.fromReading = false;
    this.navPathStack.pushPathByName('toc', p);
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '书籍详情',
          pathStack: this.navPathStack,
          textColor: this.textPrimary
        })
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.colorPrimary)
            Text('正在加载详情…')
              .fontSize(14)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.failedMsg !== '') {
            Column({ space: 8 }) {
              Text('详情加载失败')
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
                  this.initData();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                Row({ space: 16 }) {
                  BookCover({
                    coverUrl: this.book.coverUrl,
                    bookName: this.book.name,
                    coverWidth: 100,
                    coverHeight: 140
                  })
                  Column({ space: 6 }) {
                    Text(this.book.name)
                      .fontSize(19)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.textPrimary)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.book.author !== '' ? this.book.author : '未知作者')
                      .fontSize(14)
                      .fontColor(this.textSecondary)
                    if (this.book.kind !== '') {
                      Text(this.book.kind.split(',').join(' · '))
                        .fontSize(12)
                        .fontColor(this.colorPrimary)
                        .maxLines(2)
                    }
                    Text('来源：' + this.book.originName)
                      .fontSize(12)
                      .fontColor(this.textSecondary)
                    if (this.book.latestChapterTitle !== '') {
                      Text('最新：' + this.book.latestChapterTitle)
                        .fontSize(12)
                        .fontColor(this.textSecondary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .padding(16)

                Row({ space: 12 }) {
                  Button(this.onShelf ? '已在书架' : '加入书架')
                    .backgroundColor(this.onShelf ? this.dividerColor : this.colorPrimary)
                    .fontColor(this.onShelf ? this.textSecondary : Color.White)
                    .layoutWeight(1)
                    .enabled(!this.onShelf)
                    .onClick(() => {
                      this.addToShelf();
                    })
                  Button('查看目录')
                    .backgroundColor(Color.Transparent)
                    .fontColor(this.colorPrimary)
                    .border({ width: 1, color: this.colorPrimary })
                    .layoutWeight(1)
                    .onClick(() => {
                      this.openToc();
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 12 })

                if (this.book.intro !== '') {
                  Column({ space: 8 }) {
                    Text('简介')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.textPrimary)
                    Text(this.book.intro)
                      .fontSize(13)
                      .lineHeight(22)
                      .fontColor(this.textSecondary)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 16, right: 16, top: 8, bottom: 24 })
                }

                Button('开始阅读')
                  .width('90%')
                  .height(44)
                  .backgroundColor(this.colorPrimary)
                  .fontColor(Color.White)
                  .fontSize(16)
                  .margin({ bottom: 32 })
                  .onClick(() => {
                    this.startReading();
                  })
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
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
      const p: BookInfoParam = ctx.pathInfo.param as BookInfoParam;
      if (p instanceof BookInfoParam) {
        this.brief = p.book;
        this.book = p.book;
        this.initData();
      }
    })
  }
}

@Builder
export function BookInfoPageBuilder() {
  BookInfoPage()
}
