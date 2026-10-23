/**
 * Legado URL 解析：url,{options} 格式、searchKey/searchPage/page 占位符替换
 * URL 部分对 searchKey 做 URL 编码，body 部分保持原文
 * page 替换策略：若已存在 searchPage/{{page}} 标记则不再替换裸 page（避免 "?page=searchPage" 双重替换）
 */
import { UnsupportedRuleError } from '../common/BizError';
import { replaceAllStr } from '../analyze/RuleUtils';

export class UrlOptions {
  method: string = 'GET';
  body: string = '';
  headers: Record<string, string> = {};
  charset: string = '';
}

export class AnalyzedUrl {
  url: string = '';
  options: UrlOptions = new UrlOptions();

  constructor(url: string, options: UrlOptions) {
    this.url = url;
    this.options = options;
  }
}

interface RawUrlOption {
  method?: string;
  body?: string | Record<string, Object>;
  charset?: string;
}

/**
 * 在 url 中查找选项 JSON 的起始位置（",{",不进入引号内部）
 */
function findOptionsIndex(raw: string): number {
  let quote: string = '';
  for (let i: number = 0; i < raw.length; i++) {
    const c: string = raw.charAt(i);
    if (quote !== '') {
      if (c === quote) {
        quote = '';
      }
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      continue;
    }
    if (c === ',' && i + 1 < raw.length && raw.charAt(i + 1) === '{') {
      return i;
    }
  }
  return -1;
}

function escapeReplacement(s: string): string {
  return s.replace(/\$/g, '$$$$');
}

/**
 * 单词边界替换（左侧用捕获组而非 lookbehind，保证引擎兼容性）
 */
function replaceToken(s: string, token: string, to: string): string {
  const re: RegExp = new RegExp('(^|[^A-Za-z0-9_])' + token + '(?![A-Za-z0-9_])', 'g');
  return s.replace(re, '$1' + escapeReplacement(to));
}

function replacePageParams(s: string, page: number): string {
  let result: string = s;
  let hadPageToken: boolean = false;
  if (result.indexOf('{{searchPage}}') >= 0) {
    hadPageToken = true;
    result = replaceAllStr(result, '{{searchPage}}', String(page));
  }
  if (result.indexOf('{{page}}') >= 0) {
    hadPageToken = true;
    result = replaceAllStr(result, '{{page}}', String(page));
  }
  if (result.indexOf('searchPage') >= 0) {
    hadPageToken = true;
    result = replaceToken(result, 'searchPage', String(page));
  }
  if (!hadPageToken) {
    result = replaceToken(result, 'page', String(page));
  }
  return result;
}

function replaceKeyParams(s: string, searchKey: string, encode: boolean): string {
  let result: string = s;
  const rawKey: string = searchKey;
  const encodedKey: string = encodeURIComponent(searchKey);
  const keyToUse: string = encode ? encodedKey : rawKey;
  result = replaceAllStr(result, '{{searchKey}}', keyToUse);
  result = replaceAllStr(result, '{{key}}', keyToUse);
  result = replaceToken(result, 'searchKey', keyToUse);
  return result;
}

function parseHeadersFromOptionsJson(optionsJson: string): Record<string, string> {
  const empty: Record<string, string> = {};
  const m: RegExpMatchArray | null = optionsJson.match(/"headers"\s*:\s*(\{[^{}]*\})/);
  if (m === null) {
    return empty;
  }
  try {
    const parsed: Object = JSON.parse(m[1]) as Object;
    return parsed as Record<string, string>;
  } catch (e) {
    return empty;
  }
}

/**
 * 解析 Legado 格式 URL。
 * rawUrl 形如: https://x.com/search,{"method":"POST","body":"...","headers":{...},"charset":"gbk"}
 */
export function analyzeUrl(rawUrl: string, searchKey: string, page: number): AnalyzedUrl {
  const raw: string = rawUrl.trim();
  if (raw === '') {
    throw new UnsupportedRuleError('URL 为空');
  }
  if (raw.startsWith('@js:') || raw.indexOf('<js') >= 0) {
    throw new UnsupportedRuleError('URL 使用了 JS 规则，暂不支持');
  }
  const optIdx: number = findOptionsIndex(raw);
  let urlPart: string = raw;
  let optionsJson: string = '';
  if (optIdx >= 0) {
    urlPart = raw.substring(0, optIdx).trim();
    optionsJson = raw.substring(optIdx + 1).trim();
  }
  urlPart = replaceKeyParams(urlPart, searchKey, true);
  urlPart = replacePageParams(urlPart, page);
  optionsJson = replaceKeyParams(optionsJson, searchKey, false);
  optionsJson = replacePageParams(optionsJson, page);

  if (urlPart.indexOf('{{') >= 0) {
    throw new UnsupportedRuleError('URL 包含 JS 模板，暂不支持');
  }

  const options: UrlOptions = new UrlOptions();
  if (optionsJson !== '') {
    options.headers = parseHeadersFromOptionsJson(optionsJson);
    try {
      const parsed: Object = JSON.parse(optionsJson) as Object;
      const rawOpt: RawUrlOption = parsed as RawUrlOption;
      if (typeof rawOpt.method === 'string' && rawOpt.method !== '') {
        options.method = rawOpt.method.toUpperCase();
      }
      if (typeof rawOpt.body === 'string') {
        options.body = rawOpt.body;
      } else if (rawOpt.body !== undefined && rawOpt.body !== null && typeof rawOpt.body === 'object') {
        options.body = JSON.stringify(rawOpt.body);
      }
      if (typeof rawOpt.charset === 'string') {
        options.charset = rawOpt.charset;
      }
    } catch (e) {
      // 选项 JSON 解析失败时忽略选项，仅用 URL
    }
  }
  if (options.body.indexOf('{{') >= 0) {
    throw new UnsupportedRuleError('请求体包含 JS 模板，暂不支持');
  }
  return new AnalyzedUrl(urlPart, options);
}
