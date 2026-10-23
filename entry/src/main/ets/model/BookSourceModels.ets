/**
 * 书源数据模型（字段名对齐 Legado 书源 JSON 格式）
 */

interface RawSearchRule {
  bookList?: string;
  name?: string;
  author?: string;
  bookUrl?: string;
  coverUrl?: string;
  intro?: string;
  lastChapter?: string;
  kind?: string;
}

interface RawBookInfoRule {
  name?: string;
  author?: string;
  intro?: string;
  kind?: string;
  coverUrl?: string;
  lastChapter?: string;
  tocUrl?: string;
}

interface RawTocRule {
  chapterList?: string;
  chapterName?: string;
  chapterUrl?: string;
  isVip?: string;
  isVolume?: string;
  nextTocUrl?: string;
}

interface RawContentRule {
  content?: string;
  nextContentUrl?: string;
  replaceRegex?: string;
}

interface RawBookSource {
  bookSourceName?: string;
  bookSourceUrl?: string;
  bookSourceGroup?: string;
  bookSourceType?: number;
  enabled?: boolean;
  enabledExplore?: boolean;
  customOrder?: number;
  lastUpdateTime?: number;
  respondTime?: number;
  weight?: number;
  exploreUrl?: string;
  searchUrl?: string;
  ruleSearch?: RawSearchRule;
  ruleExplore?: RawSearchRule;
  ruleBookInfo?: RawBookInfoRule;
  ruleToc?: RawTocRule;
  ruleContent?: RawContentRule;
}

function normStr(v: string | undefined | null): string {
  if (typeof v === 'string') {
    return v;
  }
  return '';
}

function normNum(v: number | undefined | null): number {
  if (typeof v === 'number') {
    return v;
  }
  return 0;
}

function normBool(v: boolean | undefined | null, dflt: boolean): boolean {
  if (typeof v === 'boolean') {
    return v;
  }
  return dflt;
}

export class SearchRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  bookUrl: string = '';
  coverUrl: string = '';
  intro: string = '';
  lastChapter: string = '';
  kind: string = '';
}

export class BookInfoRule {
  name: string = '';
  author: string = '';
  intro: string = '';
  kind: string = '';
  coverUrl: string = '';
  lastChapter: string = '';
  tocUrl: string = '';
}

export class TocRule {
  chapterList: string = '';
  chapterName: string = '';
  chapterUrl: string = '';
  isVip: string = '';
  isVolume: string = '';
  nextTocUrl: string = '';
}

export class ContentRule {
  content: string = '';
  nextContentUrl: string = '';
  replaceRegex: string = '';
}

export class BookSource {
  bookSourceName: string = '';
  bookSourceUrl: string = '';
  bookSourceGroup: string = '';
  bookSourceType: number = 0;
  enabled: boolean = true;
  enabledExplore: boolean = true;
  customOrder: number = 0;
  lastUpdateTime: number = 0;
  respondTime: number = 180000;
  weight: number = 0;
  exploreUrl: string = '';
  searchUrl: string = '';
  ruleSearch: SearchRule = new SearchRule();
  ruleExplore: SearchRule = new SearchRule();
  ruleBookInfo: BookInfoRule = new BookInfoRule();
  ruleToc: TocRule = new TocRule();
  ruleContent: ContentRule = new ContentRule();

  hasExplore(): boolean {
    return this.exploreUrl.trim() !== '';
  }

  hasSearch(): boolean {
    return this.searchUrl.trim() !== '';
  }
}

function parseSearchRule(raw: RawSearchRule | undefined): SearchRule {
  const r: SearchRule = new SearchRule();
  if (raw) {
    r.bookList = normStr(raw.bookList);
    r.name = normStr(raw.name);
    r.author = normStr(raw.author);
    r.bookUrl = normStr(raw.bookUrl);
    r.coverUrl = normStr(raw.coverUrl);
    r.intro = normStr(raw.intro);
    r.lastChapter = normStr(raw.lastChapter);
    r.kind = normStr(raw.kind);
  }
  return r;
}

function parseBookInfoRule(raw: RawBookInfoRule | undefined): BookInfoRule {
  const r: BookInfoRule = new BookInfoRule();
  if (raw) {
    r.name = normStr(raw.name);
    r.author = normStr(raw.author);
    r.intro = normStr(raw.intro);
    r.kind = normStr(raw.kind);
    r.coverUrl = normStr(raw.coverUrl);
    r.lastChapter = normStr(raw.lastChapter);
    r.tocUrl = normStr(raw.tocUrl);
  }
  return r;
}

function parseTocRule(raw: RawTocRule | undefined): TocRule {
  const r: TocRule = new TocRule();
  if (raw) {
    r.chapterList = normStr(raw.chapterList);
    r.chapterName = normStr(raw.chapterName);
    r.chapterUrl = normStr(raw.chapterUrl);
    r.isVip = normStr(raw.isVip);
    r.isVolume = normStr(raw.isVolume);
    r.nextTocUrl = normStr(raw.nextTocUrl);
  }
  return r;
}

function parseContentRule(raw: RawContentRule | undefined): ContentRule {
  const r: ContentRule = new ContentRule();
  if (raw) {
    r.content = normStr(raw.content);
    r.nextContentUrl = normStr(raw.nextContentUrl);
    r.replaceRegex = normStr(raw.replaceRegex);
  }
  return r;
}

export function parseBookSource(raw: RawBookSource): BookSource {
  const s: BookSource = new BookSource();
  s.bookSourceName = normStr(raw.bookSourceName);
  s.bookSourceUrl = normStr(raw.bookSourceUrl);
  s.bookSourceGroup = normStr(raw.bookSourceGroup);
  s.bookSourceType = normNum(raw.bookSourceType);
  s.enabled = normBool(raw.enabled, true);
  s.enabledExplore = normBool(raw.enabledExplore, true);
  s.customOrder = normNum(raw.customOrder);
  s.lastUpdateTime = normNum(raw.lastUpdateTime);
  s.respondTime = normNum(raw.respondTime) === 0 ? 180000 : normNum(raw.respondTime);
  s.weight = normNum(raw.weight);
  s.exploreUrl = normStr(raw.exploreUrl);
  s.searchUrl = normStr(raw.searchUrl);
  s.ruleSearch = parseSearchRule(raw.ruleSearch);
  s.ruleExplore = parseSearchRule(raw.ruleExplore);
  s.ruleBookInfo = parseBookInfoRule(raw.ruleBookInfo);
  s.ruleToc = parseTocRule(raw.ruleToc);
  s.ruleContent = parseContentRule(raw.ruleContent);
  return s;
}

export function bookSourceFromJson(jsonStr: string): BookSource {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const raw: RawBookSource = parsed as RawBookSource;
  return parseBookSource(raw);
}

/**
 * 解析书源 JSON（数组或单个对象），返回解析出的书源列表
 */
export function parseBookSourceList(jsonStr: string): BookSource[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const result: BookSource[] = [];
  if (Array.isArray(parsed)) {
    const arr: Object[] = parsed as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (typeof item === 'object' && item !== null) {
        result.push(parseBookSource(item as RawBookSource));
      }
    }
  } else if (typeof parsed === 'object' && parsed !== null) {
    result.push(parseBookSource(parsed as RawBookSource));
  }
  return result;
}

/**
 * 序列化书源为 Legado 格式 JSON
 */
export function bookSourceToJson(source: BookSource): string {
  const raw: RawBookSource = {
    bookSourceName: source.bookSourceName,
    bookSourceUrl: source.bookSourceUrl,
    bookSourceGroup: source.bookSourceGroup,
    bookSourceType: source.bookSourceType,
    enabled: source.enabled,
    enabledExplore: source.enabledExplore,
    customOrder: source.customOrder,
    lastUpdateTime: source.lastUpdateTime,
    respondTime: source.respondTime,
    weight: source.weight,
    exploreUrl: source.exploreUrl,
    searchUrl: source.searchUrl,
    ruleSearch: {
      bookList: source.ruleSearch.bookList,
      name: source.ruleSearch.name,
      author: source.ruleSearch.author,
      bookUrl: source.ruleSearch.bookUrl,
      coverUrl: source.ruleSearch.coverUrl,
      intro: source.ruleSearch.intro,
      lastChapter: source.ruleSearch.lastChapter,
      kind: source.ruleSearch.kind
    },
    ruleExplore: {
      bookList: source.ruleExplore.bookList,
      name: source.ruleExplore.name,
      author: source.ruleExplore.author,
      bookUrl: source.ruleExplore.bookUrl,
      coverUrl: source.ruleExplore.coverUrl,
      intro: source.ruleExplore.intro,
      lastChapter: source.ruleExplore.lastChapter,
      kind: source.ruleExplore.kind
    },
    ruleBookInfo: {
      name: source.ruleBookInfo.name,
      author: source.ruleBookInfo.author,
      intro: source.ruleBookInfo.intro,
      kind: source.ruleBookInfo.kind,
      coverUrl: source.ruleBookInfo.coverUrl,
      lastChapter: source.ruleBookInfo.lastChapter,
      tocUrl: source.ruleBookInfo.tocUrl
    },
    ruleToc: {
      chapterList: source.ruleToc.chapterList,
      chapterName: source.ruleToc.chapterName,
      chapterUrl: source.ruleToc.chapterUrl,
      isVip: source.ruleToc.isVip,
      isVolume: source.ruleToc.isVolume,
      nextTocUrl: source.ruleToc.nextTocUrl
    },
    ruleContent: {
      content: source.ruleContent.content,
      nextContentUrl: source.ruleContent.nextContentUrl,
      replaceRegex: source.ruleContent.replaceRegex
    }
  };
  return JSON.stringify(raw, null, 2);
}

/**
 * 序列化书源列表为 Legado 格式 JSON
 */
export function bookSourceListToJson(sources: BookSource[]): string {
  const arr: string[] = [];
  for (let i = 0; i < sources.length; i++) {
    arr.push(bookSourceToJson(sources[i]));
  }
  return '[' + arr.join(',\n') + ']';
}
