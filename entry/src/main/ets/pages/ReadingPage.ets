/**
 * 阅读页：滚动模式阅读器
 * - 点按正文呼出/隐藏菜单（顶栏 + 底栏）
 * - 设置面板：字号 / 行距 / 段距 / 阅读主题 / 夜间
 * - 章节切换：上一章/下一章/目录（READ_TARGET 联动）
 * - 进度自动保存
 */
import { Book, Chapter, ReadingPageParam, TocPageParam } from '../model/BookModels';
import { Db } from '../service/Db';
import { BookService } from '../service/BookService';
import { StorageKeys, READER_THEMES, ReaderTheme } from '../model/ReadConfigModels';
import { PageHeader } from '../common/PageHeader';

const MAX_CACHE_CHAPTERS: number = 20;

@Component
struct ReadingPage {
  bookUrl: string = '';
  book: Book = new Book();
  chapters: Chapter[] = [];
  contentCache: Map<string, string> = new Map();
  cacheOrder: string[] = [];
  navPathStack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  @State paragraphs: string[] = [];
  @State chapterTitle: string = '';
  @State currentChapter: number = 0;
  @State loading: boolean = true;
  @State failedMsg: string = '';
  @State menuVisible: boolean = false;
  @State settingsVisible: boolean = false;
  @StorageProp(StorageKeys.READ_TARGET_VERSION) @Watch('onTargetChange') readTargetVersion: number = 0;
  @StorageProp(StorageKeys.READER_TEXT_SIZE) textSize: number = 19;
  @StorageProp(StorageKeys.READER_LINE_SPACING) lineSpacing: number = 8;
  @StorageProp(StorageKeys.READER_PARAGRAPH_SPACING) paragraphSpacing: number = 12;
  @StorageProp(StorageKeys.READER_THEME_INDEX) readerThemeIndex: number = 0;
  @StorageProp(StorageKeys.NIGHT_MODE) nightMode: boolean = false;
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  /** 手势条避让高度（vp）：全局全屏后内容铺满屏幕底部，底栏/文末按钮需上移 */
  @StorageProp(StorageKeys.SAFE_AREA_BOTTOM_VP) navBarVp: number = 24;
  /** 状态栏避让高度（vp）：hideTitleBar + expandSafeArea 后页面自标题栏起自行避让 */
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;

  readerBg(): string {
    const theme = READER_THEMES[this.readerThemeIndex];
    if (this.nightMode) {
      return theme.bgNight;
    }
    return theme.bgDay;
  }

  readerTextColor(): string {
    const theme = READER_THEMES[this.readerThemeIndex];
    if (this.nightMode) {
      return theme.textNight;
    }
    return theme.textDay;
  }

  init(param: ReadingPageParam): void {
    this.bookUrl = param.bookUrl;
    const db: Db = Db.getInstance();
    this.loading = true;
    this.failedMsg = '';
    db.getBook(this.bookUrl).then((book: Book | null) => {
      if (book === null) {
        this.failedMsg = '书籍不存在，请先加入书架';
        this.loading = false;
        return;
      }
      this.book = book;
      return db.getChapters(this.bookUrl).then((chapters: Chapter[]) => {
        if (chapters.length > 0) {
          return chapters;
        }
        return BookService.getInstance().loadToc(book).then((fresh: Chapter[]) => {
          return db.saveChapters(book.bookUrl, fresh).then(() => fresh);
        });
      }).then((chapters: Chapter[]) => {
        this.chapters = chapters;
        let target: number = book.durChapterIndex;
        if (param.chapterIndex >= 0 && param.chapterIndex < chapters.length) {
          target = param.chapterIndex;
        }
        if (target < 0 || target >= chapters.length) {
          target = 0;
        }
        this.loadChapter(target);
      });
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  onTargetChange(): void {
    const idx: number = AppStorage.get<number>(StorageKeys.READ_TARGET_INDEX) ?? -1;
    if (idx >= 0 && idx < this.chapters.length && idx !== this.currentChapter) {
      this.loadChapter(idx);
    }
  }

  cacheKey(index: number): string {
    return this.bookUrl + '#' + index;
  }

  putCache(index: number, content: string): void {
    const key: string = this.cacheKey(index);
    this.contentCache.set(key, content);
    this.cacheOrder.push(key);
    while (this.cacheOrder.length > MAX_CACHE_CHAPTERS) {
      const oldest: string = this.cacheOrder.shift() ?? '';
      if (oldest !== '') {
        this.contentCache.delete(oldest);
      }
    }
  }

  loadChapter(index: number): void {
    if (index < 0 || index >= this.chapters.length) {
      this.getUIContext().getPromptAction().showToast({ message: index < 0 ? '已经是第一章了' : '已经是最后一章了' });
      return;
    }
    this.currentChapter = index;
    this.chapterTitle = this.chapters[index].title;
    this.loading = true;
    this.failedMsg = '';
    const key: string = this.cacheKey(index);
    const cached: string | undefined = this.contentCache.get(key);
    if (cached !== undefined) {
      this.applyContent(cached);
      return;
    }
    BookService.getInstance().loadContent(this.book, this.chapters[index]).then((text: string) => {
      this.putCache(index, text);
      this.applyContent(text);
    }).catch((e: Error) => {
      this.failedMsg = e instanceof Error ? e.message : String(e);
      this.loading = false;
    });
  }

  applyContent(text: string): void {
    const parts: string[] = text.split('\n');
    const result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const line: string = parts[i].trim();
      if (line !== '') {
        result.push(line);
      }
    }
    this.paragraphs = result;
    this.loading = false;
    this.menuVisible = false;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    Db.getInstance().updateBookProgress(this.bookUrl, this.currentChapter, this.chapterTitle, 0);
  }

  prevChapter(): void {
    this.loadChapter(this.currentChapter - 1);
  }

  nextChapter(): void {
    this.loadChapter(this.currentChapter + 1);
  }

  openToc(): void {
    const p: TocPageParam = new TocPageParam();
    p.bookUrl = this.bookUrl;
    p.currentChapter = this.currentChapter;
    p.fromReading = true;
    this.navPathStack.pushPathByName('toc', p);
  }

  setTextSize(value: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READER_TEXT_SIZE, Math.round(value));
  }

  setLineSpacing(value: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READER_LINE_SPACING, Math.round(value));
  }

  setParagraphSpacing(value: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READER_PARAGRAPH_SPACING, Math.round(value));
  }

  setReaderTheme(index: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READER_THEME_INDEX, index);
  }

  @Builder
  paragraphText(paragraph: string) {
    Text(paragraph)
      .fontSize(this.textSize)
      .lineHeight(this.textSize + this.lineSpacing)
      .fontColor(this.readerTextColor())
      .margin({ bottom: this.paragraphSpacing })
      .width('100%')
  }

  @Builder
  readingSettingsPanel() {
    Column({ space: 20 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary)

      Row({ space: 12 }) {
        Text('字号')
          .fontSize(14)
          .fontColor(this.textSecondary)
          .width(40)
        Slider({ value: this.textSize, min: 12, max: 32, step: 1 })
          .layoutWeight(1)
          .selectedColor(this.colorPrimary)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              this.setTextSize(value);
            }
          })
        Text(this.textSize.toString())
          .fontSize(14)
          .width(32)
          .fontColor(this.textPrimary)
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('行距')
          .fontSize(14)
          .fontColor(this.textSecondary)
          .width(40)
        Slider({ value: this.lineSpacing, min: 0, max: 24, step: 1 })
          .layoutWeight(1)
          .selectedColor(this.colorPrimary)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              this.setLineSpacing(value);
            }
          })
        Text(this.lineSpacing.toString())
          .fontSize(14)
          .width(32)
          .fontColor(this.textPrimary)
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('段距')
          .fontSize(14)
          .fontColor(this.textSecondary)
          .width(40)
        Slider({ value: this.paragraphSpacing, min: 0, max: 32, step: 1 })
          .layoutWeight(1)
          .selectedColor(this.colorPrimary)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End) {
              this.setParagraphSpacing(value);
            }
          })
        Text(this.paragraphSpacing.toString())
          .fontSize(14)
          .width(32)
          .fontColor(this.textPrimary)
      }
      .width('100%')

      Text('阅读主题')
        .fontSize(14)
        .fontColor(this.textSecondary)
        .width('100%')

      Row({ space: 12 }) {
        ForEach(READER_THEMES, (theme: ReaderTheme, index: number) => {
          Stack() {
            if (index === this.readerThemeIndex) {
              Circle()
                .width(38)
                .height(38)
                .fill(Color.Transparent)
                .stroke(this.colorPrimary)
                .strokeWidth(2)
            }
            Circle()
              .width(30)
              .height(30)
              .fill(this.nightMode ? theme.bgNight : theme.bgDay)
          }
          .width(38)
          .height(38)
          .onClick(() => {
            this.setReaderTheme(index);
          })
        }, (theme: ReaderTheme) => theme.name)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .padding(24)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(this.colorPrimary)
              Text('正在加载章节…')
                .fontSize(14)
                .fontColor(this.readerTextColor())
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            if (this.failedMsg !== '') {
              Column({ space: 8 }) {
                Text('本章加载失败')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.readerTextColor())
                Text(this.failedMsg)
                  .fontSize(13)
                  .fontColor(this.readerTextColor())
                Button('重试')
                  .backgroundColor(this.colorPrimary)
                  .fontColor(Color.White)
                  .margin({ top: 8 })
                  .onClick(() => {
                    this.loadChapter(this.currentChapter);
                  })
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              Scroll(this.scroller) {
                Column() {
                  Text(this.chapterTitle)
                    .fontSize(this.textSize + 2)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.readerTextColor())
                    .margin({ top: 16, bottom: 20 })
                    .width('100%')
                  ForEach(this.paragraphs, (paragraph: string) => {
                    this.paragraphText(paragraph)
                  }, (paragraph: string, index: number) => this.bookUrl + '#' + this.currentChapter + '#' + index)
                  Row() {
                    Button('上一章')
                      .backgroundColor(Color.Transparent)
                      .fontColor(this.colorPrimary)
                      .onClick(() => {
                        this.prevChapter();
                      })
                    Button('下一章')
                      .backgroundColor(Color.Transparent)
                      .fontColor(this.colorPrimary)
                      .onClick(() => {
                        this.nextChapter();
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: 16, bottom: 40 + this.navBarVp })
                }
                .padding({ left: 20, right: 20 })
              }
              .scrollBar(BarState.Off)
              .layoutWeight(1)
              .width('100%')
              .onClick(() => {
                this.menuVisible = !this.menuVisible;
              })
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarVp + 56 })

        PageHeader({
          title: '',
          pathStack: this.navPathStack,
          textColor: this.readerTextColor()
        })
        .position({ x: 0, y: 0 })

        if (this.menuVisible) {
          Column() {
            Text(this.book.name + ' · ' + this.chapterTitle)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#F5FFFFFF')
          .justifyContent(FlexAlign.Center)
          .position({ x: 0, y: this.statusBarVp + 56 })
        }

        if (this.menuVisible) {
          Column() {
            Row({ space: 0 }) {
              Text((this.currentChapter + 1) + '/' + this.chapters.length)
                .fontSize(12)
                .fontColor(this.textSecondary)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.list_bullet'))
                .fontSize(22)
                .fontColor([this.textPrimary])
                .margin({ right: 20 })
                .onClick(() => {
                  this.menuVisible = false;
                  this.openToc();
                })
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(22)
                .fontColor([this.textPrimary])
                .onClick(() => {
                  this.settingsVisible = true;
                })
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            Divider()
              .color(this.textSecondary)
          }
          .width('100%')
          .backgroundColor('#F5FFFFFF')
          .position({ x: 0, y: '100%' })
          .translate({ y: -(48 + this.navBarVp) })
          .markAnchor({ y: -(48 + this.navBarVp) })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.readerBg())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.settingsVisible, this.readingSettingsPanel(), {
        height: 420,
        dragBar: true,
        showClose: true
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.readerBg())
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ReadingPageParam = ctx.pathInfo.param as ReadingPageParam;
      if (p instanceof ReadingPageParam) {
        this.init(p);
      }
    })
  }
}

@Builder
export function ReadingPageBuilder() {
  ReadingPage()
}
