/**
 * 青漫数据源客户端
 * 官方 App API（https://api.mihumh.xyz/api/app/*，由 Mihu APK 逆向确认）。
 * 需携带 X-App-* 请求头（包名/版本号/设备ID），匿名可用；
 * 相比官网代理（mihumh.com/api/upstream/website/comic）无每日免费章节次数限制。
 * 响应包装：{code, success, data}，字段与 App 端 ComicListBean 系列一致。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpText, HttpRequestSpec } from './HttpClient';
import { StorageKeys } from '../model/ReadConfigModels';
import { NetworkError } from '../common/BizError';
import {
  ComicHomeSection, ComicItem, ComicEpisode, ComicEpisodeImage, ComicSearchResult,
  parseHomeData, parseEpisodeList, parseEpisodeImages, parseComicInfo,
  parseSearchResult
} from '../model/ComicApiModels';
const DOMAIN: number = 0x0000;
const TAG: string = 'Qingman.ComicApi';

export const DEFAULT_COMIC_BASE_URL: string = 'https://api.mihumh.xyz/api/app';

/** App 客户端标识（对齐 Mihu APK v1.3.2 的 T2/c.java 拦截器） */
const APP_PACKAGE: string = 'com.comic.fm';
const APP_VERSION_CODE: string = '32';
const APP_VERSION_NAME: string = '1.3.2';

class SearchRequestBody {
  keyword: string = '';
  pageIndex: number = 1;
  pageSize: number = 20;
}

class PagedRequestBody {
  pageIndex: number = 1;
  pageSize: number = 20;
}

/** 数据源统一响应信封：{code, success, msg, data} */
interface RawEnvelope {
  code?: number;
  success?: boolean;
  msg?: string;
}

export class ComicApi {
  private static instance: ComicApi | null = null;
  /** GET 在途请求去重：同一 URL 并发调用共享同一 Promise（预取与页面加载复用） */
  private inflight: Map<string, Promise<string>> = new Map();

  static getInstance(): ComicApi {
    if (ComicApi.instance === null) {
      ComicApi.instance = new ComicApi();
    }
    return ComicApi.instance;
  }

  getBaseUrl(): string {
    const stored: string = AppStorage.get<string>(StorageKeys.COMIC_BASE_URL) ?? '';
    if (stored !== '') {
      return stored;
    }
    return DEFAULT_COMIC_BASE_URL;
  }

  setBaseUrl(url: string): void {
    AppStorage.setOrCreate<string>(StorageKeys.COMIC_BASE_URL, url);
  }

  private buildSpec(method: http.RequestMethod, body: string): HttpRequestSpec {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = method;
    spec.body = body;
    spec.headers = {
      'User-Agent': 'okhttp/4.12.0',
      'Content-Type': 'application/json',
      'X-App-Package': APP_PACKAGE,
      'X-App-Version-Code': APP_VERSION_CODE,
      'X-App-Version-Name': APP_VERSION_NAME,
      'X-App-Device-Id': this.deviceId()
    };
    return spec;
  }

  /** 首次调用生成随机设备号并持久化，之后保持稳定 */
  private deviceId(): string {
    let id: string = AppStorage.get<string>(StorageKeys.DEVICE_ID) ?? '';
    if (id === '') {
      id = this.randomHex(16);
      AppStorage.setOrCreate<string>(StorageKeys.DEVICE_ID, id);
    }
    return id;
  }

  private randomHex(len: number): string {
    const chars: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    let s: string = '';
    for (let i = 0; i < len; i++) {
      s += chars[Math.floor(Math.random() * 16)];
    }
    return s;
  }

  /**
   * GET 请求在途去重后转发；POST 直接执行
   */
  private requestJson(path: string, method: http.RequestMethod, body: string): Promise<string> {
    const url: string = this.getBaseUrl() + path;
    if (method !== http.RequestMethod.GET) {
      return this.doRequestJson(url, path, method, body);
    }
    const key: string = 'GET ' + url;
    const existing: Promise<string> | undefined = this.inflight.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const wrapped: Promise<string> = this.doRequestJson(url, path, method, body).finally(() => {
      this.inflight.delete(key);
    });
    this.inflight.set(key, wrapped);
    return wrapped;
  }

  private async doRequestJson(url: string, path: string, method: http.RequestMethod, body: string): Promise<string> {
    const begin: number = Date.now();
    const resp = await httpText(url, this.buildSpec(method, body));
    const respBody: string = resp.body;
    if (respBody === '') {
      throw new NetworkError('数据源空响应 HTTP ' + resp.responseCode + ' ' + path);
    }
    hilog.info(DOMAIN, TAG, '%{public}s -> HTTP %{public}d len=%{public}d cost=%{public}dms',
      path, resp.responseCode, respBody.length, Date.now() - begin);
    // 服务端业务错误（如 code 506 每日免费上限）HTTP 仍返回 200，按信封 success=false 判定
    const envelope: RawEnvelope | null = this.tryParseEnvelope(respBody);
    if (envelope !== null && envelope.success === false) {
      const msg: string = envelope.msg ?? '';
      const code: number = envelope.code ?? 0;
      throw new NetworkError(msg !== '' ? msg : '数据源错误 code ' + code + ' ' + path);
    }
    return respBody;
  }

  /**
   * 尝试解析响应信封；非 JSON 或无 success 字段时返回 null（交由具体解析器处理）
   */
  private tryParseEnvelope(body: string): RawEnvelope | null {
    try {
      const parsed: Object = JSON.parse(body) as Object;
      const env: RawEnvelope = parsed as RawEnvelope;
      if (env.success === undefined) {
        return null;
      }
      return env;
    } catch (e) {
      return null;
    }
  }

  /**
   * POST comic/getAppHomeData → 首页分区数据（精品热漫/大家都在看…）
   */
  async getHomeData(): Promise<ComicHomeSection[]> {
    const body: string = await this.requestJson('/comic/getAppHomeData', http.RequestMethod.POST, '{}');
    return parseHomeData(body);
  }

  /**
   * POST comic/getAppHomeData → 原始响应（供本地缓存）
   */
  async getHomeDataRaw(): Promise<string> {
    return this.requestJson('/comic/getAppHomeData', http.RequestMethod.POST, '{}');
  }

  /**
   * POST comic/recent → 原始响应（供本地缓存，data 为 {total, list} 分页结构）
   */
  async getLastComicsRaw(pageIndex: number, pageSize: number): Promise<string> {
    const bodyObj: PagedRequestBody = new PagedRequestBody();
    bodyObj.pageIndex = pageIndex;
    bodyObj.pageSize = pageSize;
    return this.requestJson('/comic/recent', http.RequestMethod.POST, JSON.stringify(bodyObj));
  }

  /**
   * GET comic/info/{comicId} → 漫画详情
   */
  async getComicInfo(comicId: string): Promise<ComicItem> {
    const body: string = await this.getComicInfoRaw(comicId);
    return parseComicInfo(body);
  }

  /**
   * GET comic/info/{comicId} → 漫画详情（原始响应，供本地缓存）
   */
  async getComicInfoRaw(comicId: string): Promise<string> {
    return this.requestJson('/comic/info/' + comicId, http.RequestMethod.GET, '');
  }

  /**
   * POST comic/recent → 最近更新漫画（分页结构 {total, list}）
   */
  async getRecentComics(pageIndex: number, pageSize: number): Promise<ComicSearchResult> {
    const body: string = await this.getLastComicsRaw(pageIndex, pageSize);
    return parseSearchResult(body);
  }

  /**
   * POST comic/search → 漫画搜索（keyword + 分页）
   */
  async searchComics(keyword: string, pageIndex: number, pageSize: number): Promise<ComicSearchResult> {
    const bodyObj: SearchRequestBody = new SearchRequestBody();
    bodyObj.keyword = keyword;
    bodyObj.pageIndex = pageIndex;
    bodyObj.pageSize = pageSize;
    const body: string = JSON.stringify(bodyObj);
    const respBody: string = await this.requestJson('/comic/search', http.RequestMethod.POST, body);
    return parseSearchResult(respBody);
  }

  /**
   * GET comic/getAppComicCategoryList → 漫画分类列表（题材，原始响应）
   */
  async getComicCategoryListRaw(): Promise<string> {
    return this.requestJson('/comic/getAppComicCategoryList', http.RequestMethod.GET, '');
  }

  /**
   * POST comic/search → 分类浏览（原始响应，供本地缓存）
   * state: -1 全部, 0 连载中, 1 已完结；categoryId: '' 不限
   */
  async browseComicsRaw(pageIndex: number, pageSize: number, sortField: string, state: number, categoryId: string): Promise<string> {
    let body: string = '{"pageIndex":' + pageIndex + ',"pageSize":' + pageSize +
      ',"sortField":"' + sortField + '","sortOrder":"desc"';
    if (state >= 0) {
      body += ',"state":"' + state + '"';
    }
    if (categoryId !== '') {
      body += ',"categoryId":"' + categoryId + '"';
    }
    body += '}';
    return this.requestJson('/comic/search', http.RequestMethod.POST, body);
  }

  /**
   * POST search → 分类浏览（筛选条件 + 分页）
   */
  async browseComics(pageIndex: number, pageSize: number, sortField: string, state: number, categoryId: string): Promise<ComicSearchResult> {
    const body: string = await this.browseComicsRaw(pageIndex, pageSize, sortField, state, categoryId);
    return parseSearchResult(body);
  }

  /**
   * GET comic/episode/list/{comicId} → 章节列表
   */
  async getEpisodeList(comicId: string): Promise<ComicEpisode[]> {
    const body: string = await this.getEpisodeListRaw(comicId);
    return parseEpisodeList(body);
  }

  /**
   * GET comic/episode/list/{comicId} → 章节列表（原始响应，供本地缓存）
   */
  async getEpisodeListRaw(comicId: string): Promise<string> {
    return this.requestJson('/comic/episode/list/' + comicId, http.RequestMethod.GET, '');
  }

  /**
   * GET comic/episode/images/{episodeId} → 章节图片
   */
  async getEpisodeImages(episodeId: string): Promise<ComicEpisodeImage[]> {
    const body: string = await this.getEpisodeImagesRaw(episodeId);
    return parseEpisodeImages(body);
  }

  /**
   * GET comic/episode/images/{episodeId} → 章节图片（原始响应，供本地缓存/预取）
   */
  async getEpisodeImagesRaw(episodeId: string): Promise<string> {
    return this.requestJson('/comic/episode/images/' + episodeId, http.RequestMethod.GET, '');
  }
}
