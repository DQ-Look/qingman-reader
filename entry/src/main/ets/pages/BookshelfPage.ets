/**
 * 书架页：网格展示书架书籍，进度角标、长按操作、空态引导
 */
import { Book, BookInfoParam, ReadingPageParam } from '../model/BookModels';
import { Db } from '../service/Db';
import { StorageKeys } from '../model/ReadConfigModels';
import { BookCover } from '../components/BookCover';
import { ComicParam, ComicReaderParam, COMIC_BOOK_URL_PREFIX, ComicEpisode, parseEpisodeList, parseEpisodeImages, CACHE_PREFIX_EPS, CACHE_PREFIX_IMGS, imagesFresh, episodesFresh } from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';

/** 书架更新检查允许网络刷新的最小间隔 */
const UPDATE_CHECK_INTERVAL_MS: number = 10 * 60 * 1000;

@Component
export struct BookshelfPage {
  pathStack: NavPathStack = new NavPathStack();
  @State books: Book[] = [];
  @State loading: boolean = true;
  @State updateCounts: Map<string, number> = new Map<string, number>();
  private lastUpdateCheck: number = 0;
  @StorageProp(StorageKeys.BOOKSHELF_VERSION) @Watch('onVersionChange') bookshelfVersion: number = 0;
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';

  aboutToAppear(): void {
    this.refresh();
  }

  onVersionChange(): void {
    this.refresh();
  }

  refresh(): void {
    this.loading = true;
    Db.getInstance().getShelfBooks().then((list: Book[]) => {
      this.books = list;
      this.loading = false;
      this.checkUpdates(list);
    }).catch(() => {
      this.loading = false;
    });
  }

  updateCount(book: Book): number {
    return this.updateCounts.get(book.bookUrl) ?? 0;
  }

  setUpdateCount(bookUrl: string, count: number): void {
    const next: Map<string, number> = new Map<string, number>();
    this.updateCounts.forEach((v: number, k: string) => {
      next.set(k, v);
    });
    next.set(bookUrl, count);
    this.updateCounts = next;
  }

  /**
   * 已读漫画：最新目录章节数多于已读进度（durChapterIndex+1）视为有更新
   */
  updateDiff(book: Book, eps: ComicEpisode[]): number {
    if (book.durChapterTitle === '' || book.durChapterIndex < 0) {
      return 0;
    }
    const seen: number = book.durChapterIndex + 1;
    return eps.length > seen ? eps.length - seen : 0;
  }

  /**
   * 书架漫画更新检查：新鲜缓存直接比对；过期缓存在网络节流间隔内沿用，超出才刷新
   */
  checkUpdates(books: Book[]): void {
    const allowNet: boolean = Date.now() - this.lastUpdateCheck > UPDATE_CHECK_INTERVAL_MS;
    if (allowNet) {
      this.lastUpdateCheck = Date.now();
    }
    for (let i = 0; i < books.length; i++) {
      const book: Book = books[i];
      if (this.isComic(book)) {
        this.checkOneUpdate(book, allowNet);
      }
    }
  }

  checkOneUpdate(book: Book, allowNet: boolean): void {
    const comicId: string = book.bookUrl.substring(COMIC_BOOK_URL_PREFIX.length);
    const key: string = CACHE_PREFIX_EPS + comicId;
    const db: Db = Db.getInstance();
    db.getCache(key).then((raw: string): Promise<void> => {
      if (raw !== '') {
        const eps: ComicEpisode[] = parseEpisodeList(raw);
        if (eps.length > 0 && (episodesFresh(eps) || !allowNet)) {
          this.setUpdateCount(book.bookUrl, this.updateDiff(book, eps));
          return Promise.resolve();
        }
      }
      if (!allowNet) {
        this.setUpdateCount(book.bookUrl, raw !== '' ? this.updateDiff(book, parseEpisodeList(raw)) : 0);
        return Promise.resolve();
      }
      return ComicApi.getInstance().getEpisodeListRaw(comicId).then((fresh: string): void => {
        db.setCache(key, fresh).catch(() => {
        });
        this.setUpdateCount(book.bookUrl, this.updateDiff(book, parseEpisodeList(fresh)));
      });
    }).catch(() => {
    });
  }

  progressText(book: Book): string {
    const diff: number = this.updateCount(book);
    let base: string = book.durChapterTitle !== '' ? '读到：' + book.durChapterTitle : '未开始阅读';
    if (book.durChapterPos > 0) {
      base += ' · 第' + (Math.floor(book.durChapterPos) + 1) + '页';
    }
    if (diff > 0) {
      return '更新' + (diff > 99 ? '99+' : diff) + '话 · ' + base;
    }
    return base;
  }

  isComic(book: Book): boolean {
    return book.bookUrl.startsWith(COMIC_BOOK_URL_PREFIX);
  }

  /**
   * 点击书架漫画：直接进阅读器续读（与小说行为一致）
   * 先从 DB 取最新进度，避免列表数据过期导致从头读起
   */
  openComic(book: Book): void {
    const db: Db = Db.getInstance();
    db.getBook(book.bookUrl).then((fresh: Book | null) => {
      this.openComicAt(fresh !== null ? fresh : book);
    }).catch(() => {
      this.openComicAt(book);
    });
  }

  openComicAt(book: Book): void {
    const comicId: string = book.bookUrl.substring(COMIC_BOOK_URL_PREFIX.length);
    const startIndex: number = book.durChapterIndex >= 0 ? book.durChapterIndex : 0;
    this.prefetchComic(comicId, startIndex);
    const p: ComicReaderParam = new ComicReaderParam();
    p.comicId = comicId;
    p.comicName = book.name;
    p.episodes = [];
    p.startIndex = startIndex;
    p.startPage = book.durChapterPos > 0 ? Math.floor(book.durChapterPos) : 0;
    this.pathStack.pushPathByName('comicReader', p);
  }

  /**
   * 点击瞬间预取目录与目标章节图片（新鲜缓存跳过；阅读器经在途去重复用同一请求）
   */
  prefetchComic(comicId: string, startIndex: number): void {
    const api: ComicApi = ComicApi.getInstance();
    const db: Db = Db.getInstance();
    db.getCache(CACHE_PREFIX_EPS + comicId).then((cached: string): Promise<void> => {
      if (cached !== '') {
        const eps: ComicEpisode[] = parseEpisodeList(cached);
        if (episodesFresh(eps)) {
          return this.prefetchEpisodeImages(eps, startIndex, api, db);
        }
      }
      return api.getEpisodeListRaw(comicId).then((raw: string): Promise<void> => {
        db.setCache(CACHE_PREFIX_EPS + comicId, raw).catch(() => {
        });
        const eps: ComicEpisode[] = parseEpisodeList(raw);
        return this.prefetchEpisodeImages(eps, startIndex, api, db);
      });
    }).catch(() => {
    });
  }

  prefetchEpisodeImages(eps: ComicEpisode[], startIndex: number, api: ComicApi, db: Db): Promise<void> {
    eps.sort((a: ComicEpisode, b: ComicEpisode): number => a.episodeNum - b.episodeNum);
    if (startIndex < 0 || startIndex >= eps.length) {
      return Promise.resolve();
    }
    const ep: ComicEpisode = eps[startIndex];
    if (ep.episodeId === '') {
      return Promise.resolve();
    }
    const key: string = CACHE_PREFIX_IMGS + ep.episodeId;
    return db.getCache(key).then((cachedImg: string): Promise<void> => {
      if (cachedImg !== '' && imagesFresh(parseEpisodeImages(cachedImg))) {
        return Promise.resolve();
      }
      return api.getEpisodeImagesRaw(ep.episodeId).then((raw2: string): void => {
        db.setCache(key, raw2).catch(() => {
        });
      });
    });
  }

  /**
   * 长按菜单「查看详情」：进详情页
   */
  openComicDetail(book: Book): void {
    const p: ComicParam = new ComicParam();
    p.comicId = book.bookUrl.substring(COMIC_BOOK_URL_PREFIX.length);
    p.comicName = book.name;
    p.picUrl = book.coverUrl;
    this.pathStack.pushPathByName('comicDetail', p);
  }

  openBook(book: Book): void {
    if (this.isComic(book)) {
      this.openComic(book);
      return;
    }
    const db: Db = Db.getInstance();
    db.getBook(book.bookUrl).then((fresh: Book | null) => {
      this.openNovelAt(fresh !== null ? fresh : book);
    }).catch(() => {
      this.openNovelAt(book);
    });
  }

  openNovelAt(book: Book): void {
    const p: ReadingPageParam = new ReadingPageParam();
    p.bookUrl = book.bookUrl;
    p.chapterIndex = book.durChapterIndex;
    this.pathStack.pushPathByName('reading', p);
  }

  showActions(book: Book): void {
    this.getUIContext().showActionSheet({
      title: book.name,
      message: book.author,
      sheets: [
        {
          title: '查看详情',
          action: () => {
            if (this.isComic(book)) {
              this.openComicDetail(book);
              return;
            }
            const p: BookInfoParam = new BookInfoParam();
            p.book = book;
            this.pathStack.pushPathByName('bookInfo', p);
          }
        },
        {
          title: '置顶',
          action: () => {
            Db.getInstance().updateBookCustomOrder(book.bookUrl, Date.now()).then(() => {
              this.refresh();
              this.getUIContext().getPromptAction().showToast({ message: '已置顶' });
            });
          }
        },
        {
          title: '移出书架',
          action: () => {
            this.getUIContext().showAlertDialog({
              title: '移出书架',
              message: '将《' + book.name + '》移出书架？阅读进度与目录将一并删除。',
              primaryButton: {
                value: '取消',
                action: () => {
                }
              },
              secondaryButton: {
                value: '移出',
                fontColor: this.colorAccent,
                action: () => {
                  Db.getInstance().deleteBook(book.bookUrl).then(() => {
                    AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
                      (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
                    this.getUIContext().getPromptAction().showToast({ message: '已移出书架' });
                  });
                }
              }
            });
          }
        }
      ]
    });
  }

  build() {
    Column() {
      Row() {
        Text('书架')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
        Blank()
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(24)
          .fontColor([this.textPrimary])
          .onClick(() => {
            this.pathStack.pushPathByName('search', '');
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.colorPrimary)
          Text('正在加载书架…')
            .fontSize(14)
            .fontColor(this.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.books.length === 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(56)
              .fontColor([this.textSecondary])
            Text('书架空空如也')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimary)
            Text('先去搜索添加一本，或在设置中导入书源')
              .fontSize(13)
              .fontColor(this.textSecondary)
            Button('去搜索')
              .backgroundColor(this.colorPrimary)
              .fontColor(Color.White)
              .margin({ top: 8 })
              .onClick(() => {
                this.pathStack.pushPathByName('search', '');
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.books, (book: Book) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Stack({ alignContent: Alignment.BottomStart }) {
                      BookCover({
                        coverUrl: book.coverUrl,
                        bookName: book.name,
                        coverWidth: 96,
                        coverHeight: 128
                      })
                      Text(book.originName)
                        .fontSize(9)
                        .fontColor(Color.White)
                        .maxLines(1)
                        .backgroundColor('#99000000')
                        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                        .borderRadius({ topLeft: 0, topRight: 4, bottomLeft: 4, bottomRight: 0 })
                    }
                    if (this.updateCount(book) > 0) {
                      Text('NEW')
                        .fontSize(8)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                        .backgroundColor(this.colorAccent)
                        .borderRadius(3)
                        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                        .margin(3)
                    }
                  }
                  Text(book.name)
                    .fontSize(13)
                    .fontColor(this.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(96)
                  Text(this.progressText(book))
                    .fontSize(10)
                    .fontColor(this.updateCount(book) > 0 ? this.colorAccent : this.textSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(96)
                }
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  this.openBook(book);
                })
                .gesture(LongPressGesture().onAction(() => {
                  this.showActions(book);
                }))
              }
            }, (book: Book) => book.bookUrl + '_' + this.updateCount(book))
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(18)
          .padding({ left: 16, right: 16, top: 8, bottom: 88 })
          .width('100%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
