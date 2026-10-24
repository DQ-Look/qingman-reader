/**
 * RDB（SQLite）数据访问：book / chapter 表
 */
import { relationalStore } from '@kit.ArkData';
import { Book, Chapter } from '../model/BookModels';
import { AppContextHolder } from '../common/AppContextHolder';
import { BizError } from '../common/BizError';

const CREATE_BOOK_SQL: string = `CREATE TABLE IF NOT EXISTS book (
  bookUrl TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  author TEXT DEFAULT '',
  origin TEXT DEFAULT '',
  originName TEXT DEFAULT '',
  coverUrl TEXT DEFAULT '',
  intro TEXT DEFAULT '',
  kind TEXT DEFAULT '',
  latestChapterTitle TEXT DEFAULT '',
  tocUrl TEXT DEFAULT '',
  durChapterIndex INTEGER DEFAULT 0,
  durChapterTitle TEXT DEFAULT '',
  durChapterPos REAL DEFAULT 0,
  seenTocCount INTEGER DEFAULT -1,
  groupName TEXT DEFAULT '',
  customOrder INTEGER DEFAULT 0,
  lastRead INTEGER DEFAULT 0,
  variable TEXT DEFAULT ''
)`;

const CREATE_CHAPTER_SQL: string = `CREATE TABLE IF NOT EXISTS chapter (
  bookUrl TEXT NOT NULL,
  chapterIndex INTEGER NOT NULL,
  title TEXT DEFAULT '',
  url TEXT DEFAULT '',
  isVip INTEGER DEFAULT 0,
  isVolume INTEGER DEFAULT 0,
  tag TEXT DEFAULT '',
  PRIMARY KEY (bookUrl, chapterIndex)
)`;

const CREATE_SEARCH_HISTORY_SQL: string = `CREATE TABLE IF NOT EXISTS search_history (
  keyword TEXT PRIMARY KEY,
  searchTime INTEGER DEFAULT 0
)`;

const CREATE_KV_CACHE_SQL: string = `CREATE TABLE IF NOT EXISTS kv_cache (
  cacheKey TEXT PRIMARY KEY,
  cacheValue TEXT DEFAULT ''
)`;

const BOOK_COLUMNS: string = 'bookUrl, name, author, origin, originName, coverUrl, intro, kind, ' +
  'latestChapterTitle, tocUrl, durChapterIndex, durChapterTitle, durChapterPos, seenTocCount, ' +
  'groupName, customOrder, lastRead, variable';

function rsString(rs: relationalStore.ResultSet, col: string): string {
  const idx: number = rs.getColumnIndex(col);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return '';
  }
  return rs.getString(idx);
}

function rsNumber(rs: relationalStore.ResultSet, col: string): number {
  const idx: number = rs.getColumnIndex(col);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return 0;
  }
  return rs.getLong(idx);
}

function rsDouble(rs: relationalStore.ResultSet, col: string): number {
  const idx: number = rs.getColumnIndex(col);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return 0;
  }
  return rs.getDouble(idx);
}

function bookFromRow(rs: relationalStore.ResultSet): Book {
  const b: Book = new Book();
  b.bookUrl = rsString(rs, 'bookUrl');
  b.name = rsString(rs, 'name');
  b.author = rsString(rs, 'author');
  b.origin = rsString(rs, 'origin');
  b.originName = rsString(rs, 'originName');
  b.coverUrl = rsString(rs, 'coverUrl');
  b.intro = rsString(rs, 'intro');
  b.kind = rsString(rs, 'kind');
  b.latestChapterTitle = rsString(rs, 'latestChapterTitle');
  b.tocUrl = rsString(rs, 'tocUrl');
  b.durChapterIndex = rsNumber(rs, 'durChapterIndex');
  b.durChapterTitle = rsString(rs, 'durChapterTitle');
  b.durChapterPos = rsDouble(rs, 'durChapterPos');
  b.seenTocCount = rsNumber(rs, 'seenTocCount');
  b.groupName = rsString(rs, 'groupName');
  b.customOrder = rsNumber(rs, 'customOrder');
  b.lastRead = rsNumber(rs, 'lastRead');
  b.variable = rsString(rs, 'variable');
  return b;
}

export class Db {
  private static instance: Db | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initPromise: Promise<void> | null = null;

  static getInstance(): Db {
    if (Db.instance === null) {
      Db.instance = new Db();
    }
    return Db.instance;
  }

  async ready(): Promise<relationalStore.RdbStore> {
    if (this.initPromise === null) {
      this.initPromise = this.doInit();
    }
    await this.initPromise;
    if (this.store === null) {
      throw new BizError('db', '数据库初始化失败');
    }
    return this.store;
  }

  private async doInit(): Promise<void> {
    const context = AppContextHolder.get();
    const config: relationalStore.StoreConfig = {
      name: 'qingman.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_BOOK_SQL);
    await this.store.executeSql(CREATE_CHAPTER_SQL);
    await this.store.executeSql(CREATE_SEARCH_HISTORY_SQL);
    await this.store.executeSql(CREATE_KV_CACHE_SQL);
    // 老库迁移：补充 seenTocCount 列（已存在时忽略）
    try {
      await this.store.executeSql('ALTER TABLE book ADD COLUMN seenTocCount INTEGER DEFAULT -1');
    } catch (e) {
      // 列已存在，无需处理
    }
  }

  async getShelfBooks(): Promise<Book[]> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT ' + BOOK_COLUMNS + ' FROM book ORDER BY customOrder DESC, lastRead DESC');
    const books: Book[] = [];
    while (rs.goToNextRow()) {
      books.push(bookFromRow(rs));
    }
    rs.close();
    return books;
  }

  async getBook(bookUrl: string): Promise<Book | null> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT ' + BOOK_COLUMNS + ' FROM book WHERE bookUrl = ?', [bookUrl]);
    let result: Book | null = null;
    if (rs.goToNextRow()) {
      result = bookFromRow(rs);
    }
    rs.close();
    return result;
  }

  async saveBook(book: Book): Promise<void> {
    const store = await this.ready();
    await store.executeSql(
      'INSERT OR REPLACE INTO book (' + BOOK_COLUMNS + ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [book.bookUrl, book.name, book.author, book.origin, book.originName, book.coverUrl,
        book.intro, book.kind, book.latestChapterTitle, book.tocUrl, book.durChapterIndex,
        book.durChapterTitle, book.durChapterPos, book.seenTocCount, book.groupName,
        book.customOrder, book.lastRead, book.variable]);
  }

  async updateSeenTocCount(bookUrl: string, seenTocCount: number): Promise<void> {
    const store = await this.ready();
    await store.executeSql('UPDATE book SET seenTocCount = ? WHERE bookUrl = ?',
      [seenTocCount, bookUrl]);
  }

  async updateBookProgress(bookUrl: string, durChapterIndex: number,
    durChapterTitle: string, durChapterPos: number): Promise<void> {
    const store = await this.ready();
    await store.executeSql(
      'UPDATE book SET durChapterIndex = ?, durChapterTitle = ?, durChapterPos = ?, lastRead = ? WHERE bookUrl = ?',
      [durChapterIndex, durChapterTitle, durChapterPos, Date.now(), bookUrl]);
  }

  async touchBookReadTime(bookUrl: string): Promise<void> {
    const store = await this.ready();
    await store.executeSql('UPDATE book SET lastRead = ? WHERE bookUrl = ?', [Date.now(), bookUrl]);
  }

  async updateBookCustomOrder(bookUrl: string, customOrder: number): Promise<void> {
    const store = await this.ready();
    await store.executeSql('UPDATE book SET customOrder = ? WHERE bookUrl = ?', [customOrder, bookUrl]);
  }

  async deleteBook(bookUrl: string): Promise<void> {
    const store = await this.ready();
    await store.executeSql('DELETE FROM book WHERE bookUrl = ?', [bookUrl]);
    await store.executeSql('DELETE FROM chapter WHERE bookUrl = ?', [bookUrl]);
  }

  async saveChapters(bookUrl: string, chapters: Chapter[]): Promise<void> {
    const store = await this.ready();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM chapter WHERE bookUrl = ?', [bookUrl]);
      for (let i = 0; i < chapters.length; i++) {
        const ch: Chapter = chapters[i];
        await store.executeSql(
          'INSERT OR REPLACE INTO chapter (bookUrl, chapterIndex, title, url, isVip, isVolume, tag) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [bookUrl, ch.chapterIndex, ch.title, ch.url, ch.isVip ? 1 : 0, ch.isVolume ? 1 : 0, ch.tag]);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new BizError('db', e instanceof Error ? e.message : String(e));
    }
  }

  async getChapters(bookUrl: string): Promise<Chapter[]> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT bookUrl, chapterIndex, title, url, isVip, isVolume, tag FROM chapter WHERE bookUrl = ? ORDER BY chapterIndex',
      [bookUrl]);
    const chapters: Chapter[] = [];
    while (rs.goToNextRow()) {
      const ch: Chapter = new Chapter();
      ch.bookUrl = rsString(rs, 'bookUrl');
      ch.chapterIndex = rsNumber(rs, 'chapterIndex');
      ch.title = rsString(rs, 'title');
      ch.url = rsString(rs, 'url');
      ch.isVip = rsNumber(rs, 'isVip') === 1;
      ch.isVolume = rsNumber(rs, 'isVolume') === 1;
      ch.tag = rsString(rs, 'tag');
      chapters.push(ch);
    }
    rs.close();
    return chapters;
  }

  async getChapter(bookUrl: string, chapterIndex: number): Promise<Chapter | null> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT bookUrl, chapterIndex, title, url, isVip, isVolume, tag FROM chapter WHERE bookUrl = ? AND chapterIndex = ?',
      [bookUrl, chapterIndex]);
    let result: Chapter | null = null;
    if (rs.goToNextRow()) {
      const ch: Chapter = new Chapter();
      ch.bookUrl = rsString(rs, 'bookUrl');
      ch.chapterIndex = rsNumber(rs, 'chapterIndex');
      ch.title = rsString(rs, 'title');
      ch.url = rsString(rs, 'url');
      ch.isVip = rsNumber(rs, 'isVip') === 1;
      ch.isVolume = rsNumber(rs, 'isVolume') === 1;
      ch.tag = rsString(rs, 'tag');
      result = ch;
    }
    rs.close();
    return result;
  }

  async getChapterCount(bookUrl: string): Promise<number> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM chapter WHERE bookUrl = ?', [bookUrl]);
    let count: number = 0;
    if (rs.goToNextRow()) {
      count = rsNumber(rs, 'cnt');
    }
    rs.close();
    return count;
  }

  async saveSearchKeyword(keyword: string): Promise<void> {
    const kw: string = keyword.trim();
    if (kw === '') {
      return;
    }
    const store = await this.ready();
    await store.executeSql(
      'INSERT OR REPLACE INTO search_history (keyword, searchTime) VALUES (?, ?)', [kw, Date.now()]);
  }

  async getSearchHistory(): Promise<string[]> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT keyword FROM search_history ORDER BY searchTime DESC LIMIT 20', []);
    const keywords: string[] = [];
    while (rs.goToNextRow()) {
      const kw: string = rsString(rs, 'keyword');
      if (kw !== '') {
        keywords.push(kw);
      }
    }
    rs.close();
    return keywords;
  }

  async clearSearchHistory(): Promise<void> {
    const store = await this.ready();
    await store.executeSql('DELETE FROM search_history', []);
  }

  async getCache(key: string): Promise<string> {
    const store = await this.ready();
    const rs: relationalStore.ResultSet = await store.querySql(
      'SELECT cacheValue FROM kv_cache WHERE cacheKey = ?', [key]);
    let value: string = '';
    if (rs.goToNextRow()) {
      value = rsString(rs, 'cacheValue');
    }
    rs.close();
    return value;
  }

  async setCache(key: string, value: string): Promise<void> {
    const store = await this.ready();
    await store.executeSql(
      'INSERT OR REPLACE INTO kv_cache (cacheKey, cacheValue) VALUES (?, ?)', [key, value]);
  }
}
