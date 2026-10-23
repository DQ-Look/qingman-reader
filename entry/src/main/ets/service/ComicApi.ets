/**
 * 青漫数据源客户端
 * 原版 App API（api.naigapp.com）按网络环境拒绝访问（502），
 * 官网 mihumh.com 的同源代理 /api/upstream/website/comic/* 与 App API 同源数据，且公网可达。
 * 响应包装：{code, success, data}，字段与 App 端 ComicListBean 系列一致。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpText, HttpRequestSpec } from './HttpClient';
import { StorageKeys } from '../model/ReadConfigModels';
import { NetworkError } from '../common/BizError';
import {
  ComicHomeSection, ComicItem, ComicEpisode, ComicEpisodeImage, ComicSearchResult,
  parseHomeData, parseEpisodeList, parseEpisodeImages, parseComicInfo, parseComicList,
  parseSearchResult
} from '../model/ComicApiModels';
const DOMAIN: number = 0x0000;
const TAG: string = 'Qingman.ComicApi';

export const DEFAULT_COMIC_BASE_URL: string = 'https://mihumh.com/api/upstream/website/comic';

class SearchRequestBody {
  keyword: string = '';
  pageIndex: number = 1;
  pageSize: number = 20;
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
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36',
      'Content-Type': 'application/json',
      'Referer': 'https://mihumh.com/'
    };
    return spec;
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
    return respBody;
  }

  /**
   * POST getGuaziWebsiteHomeData → 首页分区数据（今日热门/大家都在看…）
   */
  async getHomeData(): Promise<ComicHomeSection[]> {
    const body: string = await this.requestJson('/getGuaziWebsiteHomeData', http.RequestMethod.POST, '{}');
    return parseHomeData(body);
  }

  /**
   * POST getGuaziWebsiteHomeData → 原始响应（供本地缓存）
   */
  async getHomeDataRaw(): Promise<string> {
    return this.requestJson('/getGuaziWebsiteHomeData', http.RequestMethod.POST, '{}');
  }

  /**
   * GET getWebsiteLastComicList → 原始响应（供本地缓存）
   */
  async getLastComicsRaw(pageIndex: number, pageSize: number): Promise<string> {
    const path: string = '/getWebsiteLastComicList?pageIndex=' + pageIndex + '&pageSize=' + pageSize;
    return this.requestJson(path, http.RequestMethod.GET, '');
  }

  /**
   * GET info/{comicId} → 漫画详情
   */
  async getComicInfo(comicId: string): Promise<ComicItem> {
    const body: string = await this.getComicInfoRaw(comicId);
    return parseComicInfo(body);
  }

  /**
   * GET info/{comicId} → 漫画详情（原始响应，供本地缓存）
   */
  async getComicInfoRaw(comicId: string): Promise<string> {
    return this.requestJson('/info/' + comicId, http.RequestMethod.GET, '');
  }

  /**
   * GET getWebsiteLastComicList → 最近更新漫画
   */
  async getLastComics(pageIndex: number, pageSize: number): Promise<ComicItem[]> {
    const path: string = '/getWebsiteLastComicList?pageIndex=' + pageIndex + '&pageSize=' + pageSize;
    const body: string = await this.requestJson(path, http.RequestMethod.GET, '');
    return parseComicList(body);
  }

  /**
   * POST search → 漫画搜索（keyword + 分页）
   */
  async searchComics(keyword: string, pageIndex: number, pageSize: number): Promise<ComicSearchResult> {
    const bodyObj: SearchRequestBody = new SearchRequestBody();
    bodyObj.keyword = keyword;
    bodyObj.pageIndex = pageIndex;
    bodyObj.pageSize = pageSize;
    const body: string = JSON.stringify(bodyObj);
    const respBody: string = await this.requestJson('/search', http.RequestMethod.POST, body);
    return parseSearchResult(respBody);
  }

  /**
   * GET getWebsiteComicCategoryList → 漫画分类列表（题材 + 地区，原始响应）
   */
  async getComicCategoryListRaw(): Promise<string> {
    return this.requestJson('/getWebsiteComicCategoryList', http.RequestMethod.GET, '');
  }

  /**
   * POST search → 分类浏览（原始响应，供本地缓存）
   * state: -1 全部, 0 连载中, 1 已完结；categoryId: '' 不限
   */
  async browseComicsRaw(pageIndex: number, pageSize: number, sortField: string, state: number, categoryId: string): Promise<string> {
    let body: string = '{"pageIndex":' + pageIndex + ',"pageSize":' + pageSize +
      ',"sortField":"' + sortField + '","sortOrder":"desc"';
    if (state >= 0) {
      body += ',"state":' + state;
    }
    if (categoryId !== '') {
      body += ',"categoryId":"' + categoryId + '"';
    }
    body += '}';
    return this.requestJson('/search', http.RequestMethod.POST, body);
  }

  /**
   * POST search → 分类浏览（筛选条件 + 分页）
   */
  async browseComics(pageIndex: number, pageSize: number, sortField: string, state: number, categoryId: string): Promise<ComicSearchResult> {
    const body: string = await this.browseComicsRaw(pageIndex, pageSize, sortField, state, categoryId);
    return parseSearchResult(body);
  }

  /**
   * GET list/{comicId} → 章节列表
   */
  async getEpisodeList(comicId: string): Promise<ComicEpisode[]> {
    const body: string = await this.getEpisodeListRaw(comicId);
    return parseEpisodeList(body);
  }

  /**
   * GET list/{comicId} → 章节列表（原始响应，供本地缓存）
   */
  async getEpisodeListRaw(comicId: string): Promise<string> {
    return this.requestJson('/list/' + comicId, http.RequestMethod.GET, '');
  }

  /**
   * GET images/{episodeId} → 章节图片
   */
  async getEpisodeImages(episodeId: string): Promise<ComicEpisodeImage[]> {
    const body: string = await this.getEpisodeImagesRaw(episodeId);
    return parseEpisodeImages(body);
  }

  /**
   * GET images/{episodeId} → 章节图片（原始响应，供本地缓存/预取）
   */
  async getEpisodeImagesRaw(episodeId: string): Promise<string> {
    return this.requestJson('/images/' + episodeId, http.RequestMethod.GET, '');
  }
}
