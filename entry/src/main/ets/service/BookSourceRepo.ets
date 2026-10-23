/**
 * 书源仓库：files/bookSources.json 整文件读写，与 Legado 导入导出格式一致
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookSource, parseBookSourceList, bookSourceListToJson } from '../model/BookSourceModels';
import { AppContextHolder } from '../common/AppContextHolder';

const DOMAIN: number = 0x0000;
const TAG: string = 'Qingman.SourceRepo';

export class ImportResult {
  total: number = 0;
  imported: number = 0;
  updated: number = 0;
}

export class BookSourceRepo {
  private static instance: BookSourceRepo | null = null;
  private sources: BookSource[] = [];
  private filePath: string = '';
  private loaded: boolean = false;

  static getInstance(): BookSourceRepo {
    if (BookSourceRepo.instance === null) {
      BookSourceRepo.instance = new BookSourceRepo();
    }
    return BookSourceRepo.instance;
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const context = AppContextHolder.get();
    this.filePath = context.filesDir + '/bookSources.json';
    try {
      if (fileIo.accessSync(this.filePath)) {
        const text: string = fileIo.readTextSync(this.filePath);
        this.sources = parseBookSourceList(text);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load book sources failed: %{public}s', String(e));
      this.sources = [];
    }
    this.loaded = true;
  }

  private persist(): void {
    try {
      const json: string = bookSourceListToJson(this.sources);
      const file: fileIo.File = fileIo.openSync(this.filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'persist book sources failed: %{public}s', String(e));
    }
  }

  async getAll(): Promise<BookSource[]> {
    await this.load();
    return this.sources;
  }

  async getEnabled(): Promise<BookSource[]> {
    await this.load();
    const result: BookSource[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].enabled) {
        result.push(this.sources[i]);
      }
    }
    return result;
  }

  async getExploreEnabled(): Promise<BookSource[]> {
    await this.load();
    const result: BookSource[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      const s: BookSource = this.sources[i];
      if (s.enabled && s.enabledExplore && s.hasExplore()) {
        result.push(s);
      }
    }
    return result;
  }

  async getByUrl(url: string): Promise<BookSource | null> {
    await this.load();
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].bookSourceUrl === url) {
        return this.sources[i];
      }
    }
    return null;
  }

  /**
   * 导入书源 JSON（以 bookSourceUrl 为唯一键合并）
   */
  async importJson(jsonStr: string): Promise<ImportResult> {
    await this.load();
    const parsedList: BookSource[] = parseBookSourceList(jsonStr);
    const result: ImportResult = new ImportResult();
    for (let i = 0; i < parsedList.length; i++) {
      const incoming: BookSource = parsedList[i];
      if (incoming.bookSourceUrl === '') {
        continue;
      }
      result.total++;
      let found: boolean = false;
      for (let k = 0; k < this.sources.length; k++) {
        if (this.sources[k].bookSourceUrl === incoming.bookSourceUrl) {
          this.sources[k] = incoming;
          found = true;
          result.updated++;
          break;
        }
      }
      if (!found) {
        this.sources.push(incoming);
        result.imported++;
      }
    }
    this.persist();
    return result;
  }

  async saveSource(source: BookSource): Promise<void> {
    await this.load();
    let found: boolean = false;
    for (let k = 0; k < this.sources.length; k++) {
      if (this.sources[k].bookSourceUrl === source.bookSourceUrl) {
        this.sources[k] = source;
        found = true;
        break;
      }
    }
    if (!found) {
      this.sources.push(source);
    }
    this.persist();
  }

  async deleteSources(urls: string[]): Promise<number> {
    await this.load();
    const urlSet: Set<string> = new Set<string>();
    for (let i = 0; i < urls.length; i++) {
      urlSet.add(urls[i]);
    }
    const before: number = this.sources.length;
    const kept: BookSource[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      if (!urlSet.has(this.sources[i].bookSourceUrl)) {
        kept.push(this.sources[i]);
      }
    }
    this.sources = kept;
    this.persist();
    return before - this.sources.length;
  }

  async setEnabled(urls: string[], enabled: boolean): Promise<void> {
    await this.load();
    const urlSet: Set<string> = new Set<string>();
    for (let i = 0; i < urls.length; i++) {
      urlSet.add(urls[i]);
    }
    for (let i = 0; i < this.sources.length; i++) {
      if (urlSet.has(this.sources[i].bookSourceUrl)) {
        this.sources[i].enabled = enabled;
      }
    }
    this.persist();
  }

  async exportAll(): Promise<string> {
    await this.load();
    return bookSourceListToJson(this.sources);
  }

  async exportByUrls(urls: string[]): Promise<string> {
    await this.load();
    const urlSet: Set<string> = new Set<string>();
    for (let i = 0; i < urls.length; i++) {
      urlSet.add(urls[i]);
    }
    const selected: BookSource[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      if (urlSet.has(this.sources[i].bookSourceUrl)) {
        selected.push(this.sources[i]);
      }
    }
    return bookSourceListToJson(selected);
  }
}
