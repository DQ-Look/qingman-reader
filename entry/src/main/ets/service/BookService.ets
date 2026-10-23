/**
 * 书籍业务服务：搜索/详情/目录/正文/发现
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookSource, SearchRule } from '../model/BookSourceModels';
import { Book, Chapter } from '../model/BookModels';
import { AnalyzeRule } from '../analyze/AnalyzeRule';
import { analyzeUrl, UrlOptions, AnalyzedUrl } from './AnalyzeUrl';
import { httpText, HttpRequestSpec, methodFromString } from './HttpClient';
import { cleanTextResult, htmlToReadableText, looksLikeHtml, resolveUrl } from '../analyze/RuleUtils';
import { BizError, EmptyResultError, UnsupportedRuleError } from '../common/BizError';
import { BookSourceRepo } from './BookSourceRepo';

const DOMAIN: number = 0x0000;
const TAG: string = 'Qingman.BookService';

function toSpec(options: UrlOptions): HttpRequestSpec {
  const spec: HttpRequestSpec = new HttpRequestSpec();
  spec.method = methodFromString(options.method);
  spec.headers = options.headers;
  spec.body = options.body;
  spec.charset = options.charset;
  return spec;
}

export class ExploreCategory {
  title: string = '';
  url: string = '';
}

export class BookService {
  private static instance: BookService | null = null;

  static getInstance(): BookService {
    if (BookService.instance === null) {
      BookService.instance = new BookService();
    }
    return BookService.instance;
  }

  private async fetchText(urlWithOption: string): Promise<string> {
    const analyzed: AnalyzedUrl = analyzeUrl(urlWithOption, '', 1);
    const resp = await httpText(analyzed.url, toSpec(analyzed.options));
    return resp.body;
  }

  /**
   * 提取书籍列表字段（搜索与发现共用）
   */
  private extractBooks(body: string, rule: SearchRule, source: BookSource): Book[] {
    const page: AnalyzeRule = new AnalyzeRule(body);
    const elements: string[] = page.getElements(rule.bookList);
    const books: Book[] = [];
    for (let i = 0; i < elements.length; i++) {
      const el: string = elements[i];
      try {
        const er: AnalyzeRule = new AnalyzeRule(el);
        const name: string = cleanTextResult(er.getString(rule.name));
        let bookUrl: string = er.getString(rule.bookUrl).trim();
        if (name === '' || bookUrl === '') {
          continue;
        }
        bookUrl = resolveUrl(source.bookSourceUrl, bookUrl);
        if (bookUrl === '') {
          continue;
        }
        const b: Book = new Book();
        b.name = name;
        b.bookUrl = bookUrl;
        b.origin = source.bookSourceUrl;
        b.originName = source.bookSourceName;
        b.author = cleanTextResult(er.getString(rule.author));
        b.coverUrl = resolveUrl(source.bookSourceUrl, er.getString(rule.coverUrl).trim());
        b.intro = cleanTextResult(er.getString(rule.intro));
        b.latestChapterTitle = cleanTextResult(er.getString(rule.lastChapter));
        b.kind = cleanTextResult(er.getString(rule.kind));
        books.push(b);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'extract book item failed: %{public}s', String(e));
      }
    }
    return books;
  }

  /**
   * 单源搜索
   */
  async searchBySource(source: BookSource, key: string, page: number): Promise<Book[]> {
    const searchUrl: string = source.searchUrl.trim();
    if (searchUrl === '') {
      throw new EmptyResultError('书源未配置搜索地址');
    }
    const analyzed: AnalyzedUrl = analyzeUrl(searchUrl, key, page);
    const resp = await httpText(analyzed.url, toSpec(analyzed.options));
    const books: Book[] = this.extractBooks(resp.body, source.ruleSearch, source);
    if (books.length === 0) {
      throw new EmptyResultError('搜索结果为空');
    }
    return books;
  }

  /**
   * 书籍详情：应用 ruleBookInfo 补全书籍信息
   */
  async loadBookInfo(brief: Book): Promise<Book> {
    const repo: BookSourceRepo = BookSourceRepo.getInstance();
    const source: BookSource | null = await repo.getByUrl(brief.origin);
    if (source === null) {
      throw new BizError('parse', '书源不存在或已被删除');
    }
    const book: Book = new Book();
    book.name = brief.name;
    book.author = brief.author;
    book.bookUrl = brief.bookUrl;
    book.origin = brief.origin;
    book.originName = brief.originName;
    book.coverUrl = brief.coverUrl;
    book.intro = brief.intro;
    book.kind = brief.kind;
    book.latestChapterTitle = brief.latestChapterTitle;
    book.tocUrl = brief.tocUrl;
    book.durChapterIndex = brief.durChapterIndex;
    book.durChapterTitle = brief.durChapterTitle;
    book.durChapterPos = brief.durChapterPos;
    book.groupName = brief.groupName;
    book.customOrder = brief.customOrder;
    book.lastRead = brief.lastRead;
    book.variable = brief.variable;

    const hasInfoRule: boolean = source.ruleBookInfo.name !== '' || source.ruleBookInfo.author !== ''
      || source.ruleBookInfo.intro !== '' || source.ruleBookInfo.tocUrl !== ''
      || source.ruleBookInfo.coverUrl !== '' || source.ruleBookInfo.lastChapter !== '';
    if (!hasInfoRule) {
      if (book.tocUrl === '') {
        book.tocUrl = book.bookUrl;
      }
      return book;
    }
    const body: string = await this.fetchText(book.bookUrl);
    const rule: AnalyzeRule = new AnalyzeRule(body);
    const name: string = cleanTextResult(rule.getString(source.ruleBookInfo.name));
    if (name !== '') {
      book.name = name;
    }
    const author: string = cleanTextResult(rule.getString(source.ruleBookInfo.author));
    if (author !== '') {
      book.author = author;
    }
    const kind: string = cleanTextResult(rule.getString(source.ruleBookInfo.kind));
    if (kind !== '') {
      book.kind = kind;
    }
    const intro: string = cleanTextResult(rule.getString(source.ruleBookInfo.intro));
    if (intro !== '') {
      book.intro = intro;
    }
    const cover: string = rule.getString(source.ruleBookInfo.coverUrl).trim();
    if (cover !== '') {
      book.coverUrl = resolveUrl(source.bookSourceUrl, cover);
    }
    const lastChapter: string = cleanTextResult(rule.getString(source.ruleBookInfo.lastChapter));
    if (lastChapter !== '') {
      book.latestChapterTitle = lastChapter;
    }
    let tocUrl: string = rule.getString(source.ruleBookInfo.tocUrl).trim();
    if (tocUrl === '') {
      tocUrl = book.bookUrl;
    } else {
      tocUrl = resolveUrl(source.bookSourceUrl, tocUrl);
    }
    book.tocUrl = tocUrl;
    return book;
  }

  /**
   * 加载目录（支持 nextTocUrl 翻页合并）
   */
  async loadToc(book: Book): Promise<Chapter[]> {
    const repo: BookSourceRepo = BookSourceRepo.getInstance();
    const source: BookSource | null = await repo.getByUrl(book.origin);
    if (source === null) {
      throw new BizError('parse', '书源不存在或已被删除');
    }
    let currentUrl: string = book.tocUrl !== '' ? book.tocUrl : book.bookUrl;
    const visited: Set<string> = new Set<string>();
    const chapters: Chapter[] = [];
    let guard: number = 0;
    while (currentUrl !== '' && !visited.has(currentUrl) && guard < 100) {
      visited.add(currentUrl);
      const body: string = await this.fetchText(currentUrl);
      const page: AnalyzeRule = new AnalyzeRule(body);
      const elements: string[] = page.getElements(source.ruleToc.chapterList);
      for (let i = 0; i < elements.length; i++) {
        const el: string = elements[i];
        try {
          const er: AnalyzeRule = new AnalyzeRule(el);
          const title: string = cleanTextResult(er.getString(source.ruleToc.chapterName));
          let url: string = er.getString(source.ruleToc.chapterUrl).trim();
          if (title === '' || url === '') {
            continue;
          }
          url = resolveUrl(source.bookSourceUrl, url);
          if (url === '') {
            continue;
          }
          const ch: Chapter = new Chapter();
          ch.bookUrl = book.bookUrl;
          ch.title = title;
          ch.url = url;
          if (source.ruleToc.isVip !== '') {
            ch.isVip = er.getString(source.ruleToc.isVip).trim() !== '';
          }
          if (source.ruleToc.isVolume !== '') {
            ch.isVolume = er.getString(source.ruleToc.isVolume).trim() !== '';
          }
          chapters.push(ch);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'extract chapter failed: %{public}s', String(e));
        }
      }
      let next: string = '';
      if (source.ruleToc.nextTocUrl !== '') {
        try {
          next = page.getString(source.ruleToc.nextTocUrl).trim();
        } catch (e) {
          next = '';
        }
        if (next !== '') {
          next = resolveUrl(source.bookSourceUrl, next);
        }
      }
      currentUrl = next;
      guard++;
    }
    for (let i = 0; i < chapters.length; i++) {
      chapters[i].chapterIndex = i;
    }
    if (chapters.length === 0) {
      throw new EmptyResultError('目录为空');
    }
    return chapters;
  }

  /**
   * 加载章节正文（支持 nextContentUrl 合并、replaceRegex 清洗）
   */
  async loadContent(book: Book, chapter: Chapter): Promise<string> {
    const repo: BookSourceRepo = BookSourceRepo.getInstance();
    const source: BookSource | null = await repo.getByUrl(book.origin);
    if (source === null) {
      throw new BizError('parse', '书源不存在或已被删除');
    }
    const body: string = await this.fetchText(chapter.url);
    const page: AnalyzeRule = new AnalyzeRule(body);
    const contentRule: string = source.ruleContent.content;
    if (contentRule.trim() === '') {
      throw new BizError('parse', '书源未配置正文规则');
    }
    let content: string = page.getString(contentRule);
    if (source.ruleContent.nextContentUrl !== '') {
      let nextUrl: string = '';
      try {
        nextUrl = page.getString(source.ruleContent.nextContentUrl).trim();
      } catch (e) {
        nextUrl = '';
      }
      let guard: number = 0;
      while (nextUrl !== '' && guard < 10) {
        const resolved: string = resolveUrl(source.bookSourceUrl, nextUrl);
        if (resolved === '') {
          break;
        }
        const nextBody: string = await this.fetchText(resolved);
        const nextPage: AnalyzeRule = new AnalyzeRule(nextBody);
        content += nextPage.getString(contentRule);
        try {
          nextUrl = nextPage.getString(source.ruleContent.nextContentUrl).trim();
        } catch (e) {
          nextUrl = '';
        }
        guard++;
      }
    }
    if (source.ruleContent.replaceRegex !== '') {
      const parts: string[] = source.ruleContent.replaceRegex.split('##');
      if (parts.length >= 1 && parts[0] !== '') {
        try {
          const replacement: string = parts.length > 1 ? parts[1] : '';
          content = content.replace(new RegExp(parts[0], 'g'), replacement);
        } catch (e) {
          // 无效正则时忽略
        }
      }
    }
    let text: string = content;
    if (looksLikeHtml(text)) {
      text = htmlToReadableText(text);
    } else {
      text = cleanTextResult(text);
    }
    if (text === '') {
      throw new EmptyResultError('正文为空');
    }
    return text;
  }

  /**
   * 解析书源发现分类
   */
  async parseExploreCategories(source: BookSource): Promise<ExploreCategory[]> {
    const raw: string = source.exploreUrl.trim();
    if (raw === '') {
      throw new EmptyResultError('书源未配置发现地址');
    }
    if (raw.startsWith('@js:') || raw.indexOf('<js') >= 0) {
      throw new UnsupportedRuleError('发现地址使用了 JS 规则，暂不支持');
    }
    const result: ExploreCategory[] = [];
    if (raw.startsWith('[')) {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        throw new BizError('parse', '发现地址格式错误');
      }
      const arr: Object[] = parsed as Object[];
      for (let i = 0; i < arr.length; i++) {
        const rec: Record<string, Object> = arr[i] as Record<string, Object>;
        const titleObj: Object | undefined = rec['title'];
        const urlObj: Object | undefined = rec['url'];
        const title: string = typeof titleObj === 'string' ? String(titleObj) : '';
        const url: string = typeof urlObj === 'string' ? String(urlObj) : '';
        if (title !== '' && url !== '') {
          const cat: ExploreCategory = new ExploreCategory();
          cat.title = title;
          cat.url = url;
          result.push(cat);
        }
      }
      return result;
    }
    const single: ExploreCategory = new ExploreCategory();
    single.title = '发现';
    single.url = raw;
    result.push(single);
    return result;
  }

  /**
   * 发现分类书籍列表
   */
  async exploreByCategory(source: BookSource, categoryUrl: string, page: number): Promise<Book[]> {
    const analyzed: AnalyzedUrl = analyzeUrl(categoryUrl, '', page);
    const resp = await httpText(analyzed.url, toSpec(analyzed.options));
    return this.extractBooks(resp.body, source.ruleExplore, source);
  }
}
