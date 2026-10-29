/**
 * HTTP 客户端：GET/POST、请求头、编码检测链（URL选项charset → 响应头 → meta嗅探 → UTF-8）
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkError } from '../common/BizError';

const DOMAIN: number = 0x0000;
const TAG: string = 'Qingman.Http';

export const DEFAULT_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

export class HttpTextResponse {
  body: string = '';
  responseCode: number = 0;
  contentType: string = '';
}

export class HttpRequestSpec {
  method: http.RequestMethod = http.RequestMethod.GET;
  headers: Record<string, string> = {};
  body: string = '';
  charset: string = '';
}

function charsetFromContentType(contentType: string): string {
  if (contentType === '') {
    return '';
  }
  const m: RegExpMatchArray | null = contentType.match(/charset\s*=\s*"?([\w-]+)/i);
  if (m !== null) {
    return m[1].toLowerCase();
  }
  return '';
}

function sniffMetaCharset(bytes: Uint8Array): string {
  const n: number = Math.min(bytes.length, 2048);
  let s: string = '';
  for (let i: number = 0; i < n; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  const m: RegExpMatchArray | null = s.match(/charset\s*=\s*["']?([\w-]+)/i);
  if (m !== null) {
    return m[1].toLowerCase();
  }
  return '';
}

function decodeBody(buf: ArrayBuffer, charsetHint: string, contentType: string): string {
  const bytes: Uint8Array = new Uint8Array(buf);
  if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
    return utf8Decode(bytes);
  }
  let charset: string = charsetHint.trim().toLowerCase();
  if (charset === '') {
    charset = charsetFromContentType(contentType);
  }
  if (charset === '') {
    charset = sniffMetaCharset(bytes);
  }
  if (charset === '') {
    charset = 'utf-8';
  }
  try {
    const decoder: util.TextDecoder = util.TextDecoder.create(charset);
    return decoder.decodeToString(bytes);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'decode with charset %{public}s failed, fallback utf-8', charset);
    return utf8Decode(bytes);
  }
}

function utf8Decode(bytes: Uint8Array): string {
  try {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  } catch (e) {
    return '';
  }
}

function headerValue(headers: Record<string, string>, name: string): string {
  const lower: string = name.toLowerCase();
  if (headers[lower] !== undefined) {
    return headers[lower];
  }
  if (headers[name] !== undefined) {
    return headers[name];
  }
  const capitalized: string = name.charAt(0).toUpperCase() + name.slice(1);
  if (headers[capitalized] !== undefined) {
    return headers[capitalized];
  }
  return '';
}

function contentTypeFromResponseHeader(header: Record<string, string>): string {
  return headerValue(header, 'content-type');
}

/**
 * 发起请求并返回解码后的文本
 */
export async function httpText(url: string, spec: HttpRequestSpec): Promise<HttpTextResponse> {
  const client: http.HttpRequest = http.createHttp();
  try {
    const headers: Record<string, string> = {};
    const keys: string[] = Object.keys(spec.headers);
    for (let i: number = 0; i < keys.length; i++) {
      headers[keys[i]] = spec.headers[keys[i]];
    }
    if (headerValue(headers, 'user-agent') === '') {
      headers['User-Agent'] = DEFAULT_USER_AGENT;
    }
    let extraData: string | undefined = undefined;
    if (spec.body !== '' && spec.method !== http.RequestMethod.GET) {
      extraData = spec.body;
      if (headerValue(headers, 'content-type') === '') {
        const trimmed: string = spec.body.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          headers['Content-Type'] = 'application/json';
        } else {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
      }
    }
    const options: http.HttpRequestOptions = {
      method: spec.method,
      header: headers,
      extraData: extraData,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 15000,
      readTimeout: 20000
    };
    const resp: http.HttpResponse = await client.request(url, options);
    const code: number = resp.responseCode;
    const header: Record<string, string> = resp.header as Record<string, string>;
    const contentType: string = contentTypeFromResponseHeader(header);
    const buf: ArrayBuffer = resp.result as ArrayBuffer;
    const body: string = decodeBody(buf, spec.charset, contentType);
    if (body === '' && code >= 400) {
      throw new NetworkError('HTTP ' + code + ' ' + url);
    }
    const result: HttpTextResponse = new HttpTextResponse();
    result.body = body;
    result.responseCode = code;
    result.contentType = contentType;
    return result;
  } catch (e) {
    if (e instanceof NetworkError) {
      throw e;
    }
    let errMsg: string = '';
    let errCode: number = 0;
    if (e instanceof Error) {
      errMsg = e.message;
    } else {
      // http 网络层失败以 BusinessError（code+message）拒绝，instanceof Error 不成立
      const err = e as BusinessError;
      if (typeof err.code === 'number') {
        errCode = err.code;
      }
      if (typeof err.message === 'string') {
        errMsg = err.message;
      }
    }
    hilog.warn(DOMAIN, TAG, 'request failed code=%{public}d msg=%{public}s url=%{public}s', errCode, errMsg, url);
    throw new NetworkError('请求失败: [' + errCode + '] ' + errMsg + ' ' + url);
  } finally {
    client.destroy();
  }
}

export function methodFromString(m: string): http.RequestMethod {
  const upper: string = m.toUpperCase();
  if (upper === 'POST') {
    return http.RequestMethod.POST;
  }
  if (upper === 'PUT') {
    return http.RequestMethod.PUT;
  }
  if (upper === 'DELETE') {
    return http.RequestMethod.DELETE;
  }
  if (upper === 'HEAD') {
    return http.RequestMethod.HEAD;
  }
  return http.RequestMethod.GET;
}
