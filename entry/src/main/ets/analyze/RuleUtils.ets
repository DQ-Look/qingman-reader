/**
 * 规则引擎通用工具：实体解码、HTML 转文本、URL 解析
 */

const NAMED_ENTITIES: string[][] = [
  ['&nbsp;', ' '],
  ['&lt;', '<'],
  ['&gt;', '>'],
  ['&quot;', '"'],
  ['&apos;', "'"],
  ['&#39;', "'"],
  ['&amp;', '&']
];

/**
 * 解码 HTML 实体（命名实体 + 数字实体）
 */
export function decodeEntities(text: string): string {
  let result: string = text;
  for (let i = 0; i < NAMED_ENTITIES.length; i++) {
    const pair: string[] = NAMED_ENTITIES[i];
    while (result.indexOf(pair[0]) >= 0) {
      result = result.replace(pair[0], pair[1]);
    }
  }
  // 数字实体 &#123; 与 &#x1F;
  const numRe: RegExp = /&#(\d+);/g;
  const matchesNum: RegExpMatchArray | null = result.match(numRe);
  if (matchesNum !== null) {
    for (let i = 0; i < matchesNum.length; i++) {
      const m: string = matchesNum[i];
      const code: number = Number(m.substring(2, m.length - 1));
      if (code > 0 && code < 0x10FFFF) {
        result = result.replace(m, String.fromCharCode(code));
      }
    }
  }
  const hexRe: RegExp = /&#x([0-9a-fA-F]+);/g;
  const matchesHex: RegExpMatchArray | null = result.match(hexRe);
  if (matchesHex !== null) {
    for (let i = 0; i < matchesHex.length; i++) {
      const m: string = matchesHex[i];
      const code: number = parseInt(m.substring(3, m.length - 1), 16);
      if (code > 0 && code < 0x10FFFF) {
        result = result.replace(m, String.fromCharCode(code));
      }
    }
  }
  return result;
}

/**
 * 将 HTML 正文转为可读文本：<br>/</p> 转换行、去标签、解码实体
 */
export function htmlToReadableText(html: string): string {
  let s: string = html;
  s = s.replace(/<script[\s\S]*?<\/script>/gi, '');
  s = s.replace(/<style[\s\S]*?<\/style>/gi, '');
  s = s.replace(/<!--[\s\S]*?-->/g, '');
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/(p|div|h[1-6]|li|tr|blockquote|section|article)>/gi, '\n\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  s = s.replace(/\r\n/g, '\n');
  s = s.replace(/[ \t\u3000]+/g, ' ');
  s = s.replace(/ ?\n ?/g, '\n');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/**
 * 判断文本是否含有需要清洗的 HTML 标签
 */
export function looksLikeHtml(text: string): boolean {
  return /<[a-zA-Z][^>]*>/.test(text);
}

/**
 * 清洗规则结果文本：若是 HTML 片段则转为纯文本，否则仅整理空白
 */
export function cleanTextResult(text: string): string {
  if (looksLikeHtml(text)) {
    return htmlToReadableText(text);
  }
  let s: string = decodeEntities(text);
  s = s.replace(/\r\n/g, '\n');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/**
 * 解析 baseUrl 中的协议+主机
 */
function getOrigin(url: string): string {
  const idx: number = url.indexOf('://');
  if (idx < 0) {
    return '';
  }
  const slashIdx: number = url.indexOf('/', idx + 3);
  if (slashIdx < 0) {
    return url;
  }
  return url.substring(0, slashIdx);
}

/**
 * 相对 URL 补全为绝对 URL
 */
export function resolveUrl(baseUrl: string, url: string): string {
  const u: string = url.trim();
  if (u === '') {
    return u;
  }
  if (u.startsWith('http://') || u.startsWith('https://')) {
    return u;
  }
  const origin: string = getOrigin(baseUrl);
  if (origin === '') {
    return u;
  }
  if (u.startsWith('//')) {
    const schemeEnd: number = origin.indexOf('://');
    return origin.substring(0, schemeEnd) + ':' + u;
  }
  if (u.startsWith('/')) {
    return origin + u;
  }
  // 相对路径：取 baseUrl 目录
  let dir: string = baseUrl;
  const qIdx: number = dir.indexOf('?');
  if (qIdx >= 0) {
    dir = dir.substring(0, qIdx);
  }
  const lastSlash: number = dir.lastIndexOf('/');
  if (lastSlash >= 0) {
    dir = dir.substring(0, lastSlash + 1);
  } else {
    dir = origin + '/';
  }
  // 处理 ./ ../
  let combined: string = dir + u;
  while (combined.indexOf('/../') >= 0) {
    combined = combined.replace(/[^/]+\/\.\.\//, '');
  }
  combined = combined.replace(/\.\//g, '');
  return combined;
}

/**
 * 全局替换字符串
 */
export function replaceAllStr(source: string, from: string, to: string): string {
  if (from === '') {
    return source;
  }
  return source.split(from).join(to);
}

/**
 * 解析 "http://xxx" 形式字符串（容忍 JSON 引号包裹），失败返回 null
 */
export function tryExtractUrl(text: string): string | null {
  const idx: number = text.indexOf('http');
  if (idx < 0) {
    return null;
  }
  let candidate: string = text.substring(idx).trim();
  const quoteEnd: number = candidate.indexOf('"');
  if (quoteEnd >= 0) {
    candidate = candidate.substring(0, quoteEnd);
  }
  if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
    return candidate;
  }
  return null;
}
