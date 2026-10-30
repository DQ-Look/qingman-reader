/**
 * 漫画 App API 数据模型（api.mihumh.xyz/api/app/*）
 * 与 App 端（ComicListBean 系列）同源数据，字段名一致
 */

/** 章节目录 kv_cache 前缀（key = 前缀 + comicId） */
export const CACHE_PREFIX_EPS: string = 'comic_eps_';

/** 章节图片 kv_cache 前缀（key = 前缀 + episodeId） */
export const CACHE_PREFIX_IMGS: string = 'comic_imgs_';

/** auth_key 签发时间 2 小时内视为新鲜，跳过网络刷新 */
const AUTH_KEY_FRESH_MS: number = 2 * 60 * 60 * 1000;

/**
 * 从 URL 的 auth_key 时间戳判断是否仍新鲜（服务端签发时打的是当前时间戳）
 */
export function urlFresh(url: string): boolean {
  const key: string = 'auth_key=';
  const idx: number = url.indexOf(key);
  if (idx < 0) {
    return false;
  }
  const rest: string = url.substring(idx + key.length);
  const end: number = rest.indexOf('-');
  if (end <= 0) {
    return false;
  }
  const ts: number = Number(rest.substring(0, end));
  if (!ts) {
    return false;
  }
  // auth_key 的时间戳为秒级，需乘 1000 与 Date.now()（毫秒）对齐
  return Date.now() - ts * 1000 < AUTH_KEY_FRESH_MS;
}

/**
 * 章节图片列表缓存是否仍新鲜（看第一张图的 auth_key）
 */
export function imagesFresh(imgs: ComicEpisodeImage[]): boolean {
  if (imgs.length === 0) {
    return false;
  }
  return urlFresh(imgs[0].imageUrl);
}

/**
 * 章节目录缓存是否仍新鲜（看第一章封面的 auth_key）
 */
export function episodesFresh(eps: ComicEpisode[]): boolean {
  if (eps.length === 0) {
    return false;
  }
  return urlFresh(eps[0].coverUrl);
}

interface RawBaseResponse {
  code?: number;
  success?: boolean;
  msg?: string;
  data?: Object;
}

interface RawCategory {
  categoryId?: string;
  categoryName?: string;
}

interface RawComicItem {
  comicId?: string;
  comicName?: string;
  picUrl?: string;
  author?: string;
  synopsis?: string;
  episodeNum?: number;
  lastEpisodeName?: string;
  categoryName?: string;
  playNum?: number;
  collectNum?: number;
  updateTime?: string;
  categoryList?: Object[];
  state?: number;
  memberLevel?: number;
  createName?: string;
}

interface RawHomeSection {
  title?: string;
  iconUrl?: string;
  comicList?: Object[];
  rankList?: Object[];
}

interface RawRank {
  rankingName?: string;
  rankingCode?: string;
  comicList?: Object[];
}

interface RawEpisode {
  id?: string;
  comicId?: string;
  episodeId?: string;
  episodeNum?: number;
  name?: string;
  imageUrl?: string;
  price?: number;
  isAllowRead?: number;
  updateTime?: string;
}

interface RawEpisodeImage {
  imageId?: string;
  episodeId?: string;
  imageUrl?: string;
  imageIndex?: number;
}

interface RawPagedData {
  pageIndex?: number;
  pageSize?: number;
  total?: number;
  list?: Object[];
}

export class ComicItem {
  comicId: string = '';
  comicName: string = '';
  picUrl: string = '';
  author: string = '';
  synopsis: string = '';
  episodeNum: number = 0;
  lastEpisodeName: string = '';
  categoryName: string = '';
  playNum: number = 0;
  collectNum: number = 0;
  updateTime: string = '';
  categories: string[] = [];
  state: number = 0;
  createName: string = '';
}

export class ComicHomeSection {
  title: string = '';
  iconUrl: string = '';
  comics: ComicItem[] = [];
  /** 排行榜分区的榜单（新作榜/人气榜/收藏榜/上升榜） */
  ranks: ComicRank[] = [];
}

export class ComicRank {
  rankingName: string = '';
  rankingCode: string = '';
  comics: ComicItem[] = [];
}

export class ComicEpisode {
  episodeId: string = '';
  comicId: string = '';
  name: string = '';
  episodeNum: number = 0;
  coverUrl: string = '';
  updateTime: string = '';
}

export class ComicEpisodeImage {
  imageId: string = '';
  episodeId: string = '';
  imageUrl: string = '';
  imageIndex: number = 0;
}

export class ComicComment {
  commentId: string = '';
  userName: string = '';
  userAvatar: string = '';
  content: string = '';
  createTime: string = '';
  likeCount: number = 0;
  replyCount: number = 0;
}

export class ComicCommentResult {
  total: number = 0;
  comments: ComicComment[] = [];
}

interface RawComment {
  commentId?: string;
  userName?: string;
  userAvatar?: string;
  content?: string;
  createTime?: string;
  likeCount?: number;
  replyCount?: number;
}

export class ComicParam {
  comicId: string = '';
  comicName: string = '';
  picUrl: string = '';
}

/** 首页分区「更多」页参数（title 同时用于排序字段映射） */
export class ComicMoreParam {
  title: string = '';
  sortField: string = 'collectNum';
}

export class ComicSearchResult {
  total: number = 0;
  comics: ComicItem[] = [];
}

export class ComicCategory {
  categoryId: string = '';
  categoryName: string = '';
}

export class ComicReaderParam {
  comicId: string = '';
  comicName: string = '';
  episodes: ComicEpisode[] = [];
  startIndex: number = 0;
  /** 续读起始页（章节内图片索引，从 0 开始） */
  startPage: number = 0;
}

/**
 * 漫画在书架（book 表）中的合成 bookUrl 前缀
 */
export const COMIC_BOOK_URL_PREFIX: string = 'qingman://comic/';

function normStr(v: Object | undefined): string {
  if (typeof v === 'string') {
    return v;
  }
  return '';
}

function normNum(v: Object | undefined): number {
  if (typeof v === 'number') {
    return v;
  }
  return 0;
}

function parseComicItem(raw: RawComicItem): ComicItem {
  const item: ComicItem = new ComicItem();
  item.comicId = normStr(raw.comicId);
  item.comicName = normStr(raw.comicName);
  item.picUrl = normStr(raw.picUrl);
  item.author = normStr(raw.author);
  item.synopsis = normStr(raw.synopsis);
  item.episodeNum = normNum(raw.episodeNum);
  item.lastEpisodeName = normStr(raw.lastEpisodeName);
  item.categoryName = normStr(raw.categoryName);
  item.playNum = normNum(raw.playNum);
  item.collectNum = normNum(raw.collectNum);
  item.updateTime = normStr(raw.updateTime);
  item.state = normNum(raw.state);
  item.createName = normStr(raw.createName);
  if (Array.isArray(raw.categoryList)) {
    const list: string[] = [];
    const arr: Object[] = raw.categoryList as Object[];
    for (let i = 0; i < arr.length; i++) {
      const el: Object = arr[i];
      if (typeof el === 'string') {
        list.push(el as string);
      } else if (typeof el === 'object' && el !== null) {
        const cat: RawCategory = el as RawCategory;
        const catName: string = normStr(cat.categoryName);
        if (catName !== '') {
          list.push(catName);
        }
      }
    }
    item.categories = list;
  }
  return item;
}

function parseComicArray(raw: Object[] | undefined): ComicItem[] {
  const result: ComicItem[] = [];
  if (raw === undefined || !Array.isArray(raw)) {
    return result;
  }
  for (let i = 0; i < raw.length; i++) {
    const el: Object = raw[i];
    if (typeof el === 'object' && el !== null) {
      result.push(parseComicItem(el as RawComicItem));
    }
  }
  return result;
}

function parseRank(raw: RawRank): ComicRank {
  const rank: ComicRank = new ComicRank();
  rank.rankingName = normStr(raw.rankingName);
  rank.rankingCode = normStr(raw.rankingCode);
  rank.comics = parseComicArray(raw.comicList);
  return rank;
}

function parseHomeSection(raw: RawHomeSection): ComicHomeSection {
  const sec: ComicHomeSection = new ComicHomeSection();
  sec.title = normStr(raw.title);
  sec.iconUrl = normStr(raw.iconUrl);
  sec.comics = parseComicArray(raw.comicList);
  if (Array.isArray(raw.rankList)) {
    const arr: Object[] = raw.rankList as Object[];
    for (let i = 0; i < arr.length; i++) {
      const el: Object = arr[i];
      if (typeof el === 'object' && el !== null) {
        sec.ranks.push(parseRank(el as RawRank));
      }
    }
  }
  return sec;
}

/**
 * 解析 comic/getAppHomeData 响应（{code,success,data:[{title,comicList}]}）
 */
export function parseHomeData(jsonStr: string): ComicHomeSection[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicHomeSection[] = [];
  const data: Object | undefined = resp.data;
  if (data === undefined || !Array.isArray(data)) {
    return result;
  }
  const arr: Object[] = data as Object[];
  for (let i = 0; i < arr.length; i++) {
    const el: Object = arr[i];
    if (typeof el === 'object' && el !== null) {
      result.push(parseHomeSection(el as RawHomeSection));
    }
  }
  return result;
}

/**
 * 解析 info/{comicId} 单个漫画详情响应（data 为对象）
 */
export function parseComicInfo(jsonStr: string): ComicItem {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const data: Object | undefined = resp.data;
  if (typeof data === 'object' && data !== null) {
    return parseComicItem(data as RawComicItem);
  }
  return new ComicItem();
}

/**
 * 解析 data 为漫画数组类的响应（如旧缓存 getWebsiteLastComicList 的裸数组）；
 * 也兼容 data 为 {total, list:[漫画]} 的分页结构（如 comic/recent）
 */
export function parseComicList(jsonStr: string): ComicItem[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const data: Object | undefined = resp.data;
  if (data === undefined) {
    return [];
  }
  if (Array.isArray(data)) {
    return parseComicArray(data as Object[]);
  }
  if (typeof data === 'object' && data !== null) {
    const page: RawPagedData = data as RawPagedData;
    if (page.list !== undefined && Array.isArray(page.list)) {
      return parseComicArray(page.list);
    }
  }
  return [];
}

/**
 * 解析 POST search 搜索响应（data 为 {total, list:[漫画]}）
 */
export function parseSearchResult(jsonStr: string): ComicSearchResult {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicSearchResult = new ComicSearchResult();
  const data: Object | undefined = resp.data;
  if (typeof data !== 'object' || data === null) {
    return result;
  }
  const page: RawPagedData = data as RawPagedData;
  result.total = normNum(page.total);
  result.comics = parseComicArray(page.list);
  return result;
}

/**
 * 解析 comic/getAppComicCategoryList 分类列表响应（data 为 [{categoryId, categoryName}]）
 */
export function parseCategoryList(jsonStr: string): ComicCategory[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicCategory[] = [];
  const data: Object | undefined = resp.data;
  if (data === undefined || !Array.isArray(data)) {
    return result;
  }
  const arr: Object[] = data as Object[];
  for (let i = 0; i < arr.length; i++) {
    const el: Object = arr[i];
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const raw: RawCategory = el as RawCategory;
    const id: string = normStr(raw.categoryId);
    const name: string = normStr(raw.categoryName);
    if (id !== '' && name !== '' && name !== '全部') {
      const cat: ComicCategory = new ComicCategory();
      cat.categoryId = id;
      cat.categoryName = name;
      result.push(cat);
    }
  }
  return result;
}

/**
 * 解析 list/{comicId} 章节列表响应
 */
export function parseEpisodeList(jsonStr: string): ComicEpisode[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicEpisode[] = [];
  const data: Object | undefined = resp.data;
  if (data === undefined || !Array.isArray(data)) {
    return result;
  }
  const arr: Object[] = data as Object[];
  for (let i = 0; i < arr.length; i++) {
    const el: Object = arr[i];
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const raw: RawEpisode = el as RawEpisode;
    const ep: ComicEpisode = new ComicEpisode();
    ep.episodeId = normStr(raw.episodeId);
    ep.comicId = normStr(raw.comicId);
    ep.name = normStr(raw.name);
    ep.episodeNum = normNum(raw.episodeNum);
    ep.coverUrl = normStr(raw.imageUrl);
    ep.updateTime = normStr(raw.updateTime);
    if (ep.episodeId !== '') {
      result.push(ep);
    }
  }
  return result;
}

/**
 * 解析 POST comment/page 评论分页响应（data 为 {total, list:[评论]}，
 * 对齐原版 HomeRequestModel.q() 的 getGetCommentListResult）
 */
export function parseCommentPage(jsonStr: string): ComicCommentResult {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicCommentResult = new ComicCommentResult();
  const data: Object | undefined = resp.data;
  if (typeof data !== 'object' || data === null) {
    return result;
  }
  const page: RawPagedData = data as RawPagedData;
  result.total = normNum(page.total);
  if (!Array.isArray(page.list)) {
    return result;
  }
  const arr: Object[] = page.list as Object[];
  for (let i = 0; i < arr.length; i++) {
    const el: Object = arr[i];
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const raw: RawComment = el as RawComment;
    const c: ComicComment = new ComicComment();
    c.commentId = normStr(raw.commentId);
    c.userName = normStr(raw.userName);
    c.userAvatar = normStr(raw.userAvatar);
    c.content = normStr(raw.content);
    c.createTime = normStr(raw.createTime);
    c.likeCount = normNum(raw.likeCount);
    c.replyCount = normNum(raw.replyCount);
    if (c.commentId !== '') {
      result.comments.push(c);
    }
  }
  return result;
}

/**
 * 解析 images/{episodeId} 章节图片响应
 */
export function parseEpisodeImages(jsonStr: string): ComicEpisodeImage[] {
  const parsed: Object = JSON.parse(jsonStr) as Object;
  const resp: RawBaseResponse = parsed as RawBaseResponse;
  const result: ComicEpisodeImage[] = [];
  const data: Object | undefined = resp.data;
  if (data === undefined || !Array.isArray(data)) {
    return result;
  }
  const arr: Object[] = data as Object[];
  for (let i = 0; i < arr.length; i++) {
    const el: Object = arr[i];
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const raw: RawEpisodeImage = el as RawEpisodeImage;
    const img: ComicEpisodeImage = new ComicEpisodeImage();
    img.imageId = normStr(raw.imageId);
    img.episodeId = normStr(raw.episodeId);
    img.imageUrl = normStr(raw.imageUrl);
    img.imageIndex = normNum(raw.imageIndex);
    if (img.imageUrl !== '') {
      result.push(img);
    }
  }
  result.sort((a: ComicEpisodeImage, b: ComicEpisodeImage): number => a.imageIndex - b.imageIndex);
  return result;
}
