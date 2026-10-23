/**
 * 书籍与章节数据模型
 */
export class Book {
  name: string = '';
  author: string = '';
  bookUrl: string = '';
  origin: string = '';
  originName: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  latestChapterTitle: string = '';
  tocUrl: string = '';
  durChapterIndex: number = 0;
  durChapterTitle: string = '';
  durChapterPos: number = 0;
  groupName: string = '';
  customOrder: number = 0;
  lastRead: number = 0;
  variable: string = '';
}

export class Chapter {
  bookUrl: string = '';
  chapterIndex: number = 0;
  title: string = '';
  url: string = '';
  isVip: boolean = false;
  isVolume: boolean = false;
  tag: string = '';

  constructor() {
  }
}

/**
 * 导航参数：书籍详情页
 */
export class BookInfoParam {
  book: Book = new Book();
}

/**
 * 导航参数：目录页
 */
export class TocPageParam {
  bookUrl: string = '';
  currentChapter: number = 0;
  fromReading: boolean = false;
}

/**
 * 导航参数：阅读页
 */
export class ReadingPageParam {
  bookUrl: string = '';
  chapterIndex: number = -1;
}

/**
 * 导航参数：发现分类详情页
 */
export class ExploreDetailParam {
  sourceUrl: string = '';
}

/**
 * 导航参数：书源编辑页
 */
export class SourceEditParam {
  bookSourceUrl: string = '';
  isNew: boolean = true;
}
