/**
 * 轻量 HTML 解析器：容错的标签词法分析 → 简易 DOM 树
 */
import { decodeEntities } from './RuleUtils';

export class HtmlText {
  text: string = '';

  constructor(text: string) {
    this.text = text;
  }
}

type HtmlNode = HtmlElement | HtmlText;

const VOID_TAGS: string[] = [
  'br', 'hr', 'img', 'input', 'meta', 'link', 'area', 'base', 'col',
  'embed', 'source', 'track', 'wbr', 'param'
];

export class HtmlElement {
  tagName: string = '';
  attrs: Map<string, string> = new Map<string, string>();
  childNodes: HtmlNode[] = [];
  parent: HtmlElement | null = null;

  getAttr(name: string): string {
    const v: string | undefined = this.attrs.get(name.toLowerCase());
    if (v === undefined) {
      return '';
    }
    return v;
  }

  hasAttr(name: string): boolean {
    return this.attrs.has(name.toLowerCase());
  }

  classList(): string[] {
    const cls: string = this.getAttr('class');
    if (cls === '') {
      return [];
    }
    return cls.trim().split(/\s+/);
  }

  children(): HtmlElement[] {
    const result: HtmlElement[] = [];
    for (let i = 0; i < this.childNodes.length; i++) {
      const node: HtmlNode = this.childNodes[i];
      if (node instanceof HtmlElement) {
        result.push(node);
      }
    }
    return result;
  }

  textNodes(): HtmlText[] {
    const result: HtmlText[] = [];
    for (let i = 0; i < this.childNodes.length; i++) {
      const node: HtmlNode = this.childNodes[i];
      if (node instanceof HtmlText) {
        result.push(node);
      }
    }
    return result;
  }

  /**
   * 纯文本内容（递归，解码实体，压缩空白）
   */
  textContent(): string {
    let result: string = '';
    for (let i = 0; i < this.childNodes.length; i++) {
      const node: HtmlNode = this.childNodes[i];
      if (node instanceof HtmlText) {
        result += node.text;
      } else if (node.tagName === 'br') {
        result += ' ';
      } else {
        result += node.textContent();
      }
    }
    result = decodeEntities(result);
    result = result.replace(/\s+/g, ' ');
    return result.trim();
  }

  getElementById(id: string): HtmlElement | null {
    const queue: HtmlElement[] = [this];
    while (queue.length > 0) {
      const el: HtmlElement = queue.shift() as HtmlElement;
      if (el !== this && el.getAttr('id') === id) {
        return el;
      }
      const kids: HtmlElement[] = el.children();
      for (let i = 0; i < kids.length; i++) {
        queue.push(kids[i]);
      }
    }
    return null;
  }

  getElementsByClassName(cls: string): HtmlElement[] {
    const result: HtmlElement[] = [];
    const queue: HtmlElement[] = [this];
    while (queue.length > 0) {
      const el: HtmlElement = queue.shift() as HtmlElement;
      if (el !== this) {
        const classes: string[] = el.classList();
        if (classes.indexOf(cls) >= 0) {
          result.push(el);
        }
      }
      const kids: HtmlElement[] = el.children();
      for (let i = 0; i < kids.length; i++) {
        queue.push(kids[i]);
      }
    }
    return result;
  }

  getElementsByTagName(tag: string): HtmlElement[] {
    const lower: string = tag.toLowerCase();
    const result: HtmlElement[] = [];
    const queue: HtmlElement[] = [this];
    while (queue.length > 0) {
      const el: HtmlElement = queue.shift() as HtmlElement;
      if (el !== this && el.tagName === lower) {
        result.push(el);
      }
      const kids: HtmlElement[] = el.children();
      for (let i = 0; i < kids.length; i++) {
        queue.push(kids[i]);
      }
    }
    return result;
  }

  /**
   * 所有后代元素
   */
  descendants(): HtmlElement[] {
    const result: HtmlElement[] = [];
    const queue: HtmlElement[] = [this];
    while (queue.length > 0) {
      const el: HtmlElement = queue.shift() as HtmlElement;
      const kids: HtmlElement[] = el.children();
      for (let i = 0; i < kids.length; i++) {
        result.push(kids[i]);
        queue.push(kids[i]);
      }
    }
    return result;
  }

  innerHtml(): string {
    let result: string = '';
    for (let i = 0; i < this.childNodes.length; i++) {
      const node: HtmlNode = this.childNodes[i];
      if (node instanceof HtmlText) {
        result += node.text;
      } else {
        result += node.outerHtml();
      }
    }
    return result;
  }

  outerHtml(): string {
    if (this.tagName === '') {
      return this.innerHtml();
    }
    let attrsStr: string = '';
    this.attrs.forEach((value: string, key: string) => {
      attrsStr += ' ' + key + '="' + value.replace(/"/g, '&quot;') + '"';
    });
    const inner: string = this.innerHtml();
    return '<' + this.tagName + attrsStr + '>' + inner + '</' + this.tagName + '>';
  }
}

class ParsedTag {
  tagName: string = '';
  attrs: Map<string, string> = new Map<string, string>();
  selfClosing: boolean = false;
}

function findTagEnd(html: string, start: number): number {
  let quote: string = '';
  for (let i: number = start + 1; i < html.length; i++) {
    const c: string = html.charAt(i);
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
    if (c === '>') {
      return i;
    }
  }
  return -1;
}

function parseTagContent(content: string): ParsedTag {
  const parsed: ParsedTag = new ParsedTag();
  let i: number = 0;
  const len: number = content.length;
  while (i < len && content.charCodeAt(i) > 32) {
    i++;
  }
  parsed.tagName = content.substring(0, i).toLowerCase();
  while (i < len) {
    while (i < len && content.charCodeAt(i) <= 32) {
      i++;
    }
    if (i >= len) {
      break;
    }
    let start: number = i;
    while (i < len && content.charAt(i) !== '=' && content.charCodeAt(i) > 32) {
      i++;
    }
    const attrName: string = content.substring(start, i).toLowerCase();
    while (i < len && content.charCodeAt(i) <= 32) {
      i++;
    }
    let value: string = '';
    if (i < len && content.charAt(i) === '=') {
      i++;
      while (i < len && content.charCodeAt(i) <= 32) {
        i++;
      }
      if (i < len && (content.charAt(i) === '"' || content.charAt(i) === "'")) {
        const quote: string = content.charAt(i);
        i++;
        start = i;
        while (i < len && content.charAt(i) !== quote) {
          i++;
        }
        value = content.substring(start, i);
        if (i < len) {
          i++;
        }
      } else {
        start = i;
        while (i < len && content.charCodeAt(i) > 32) {
          i++;
        }
        value = content.substring(start, i);
      }
    }
    if (attrName === '/') {
      parsed.selfClosing = true;
    } else if (attrName !== '') {
      parsed.attrs.set(attrName, decodeEntities(value));
    }
  }
  return parsed;
}

/**
 * 解析 HTML 片段，返回合成的根元素
 */
export function parseHtml(html: string): HtmlElement {
  const root: HtmlElement = new HtmlElement();
  const stack: HtmlElement[] = [root];
  const len: number = html.length;
  let i: number = 0;
  while (i < len) {
    const top: HtmlElement = stack[stack.length - 1];
    const lt: number = html.indexOf('<', i);
    if (lt < 0) {
      top.childNodes.push(new HtmlText(html.substring(i)));
      break;
    }
    if (lt > i) {
      top.childNodes.push(new HtmlText(html.substring(i, lt)));
    }
    if (html.startsWith('<!--', lt)) {
      const end: number = html.indexOf('-->', lt + 4);
      i = end < 0 ? len : end + 3;
      continue;
    }
    if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
      const end: number = html.indexOf('>', lt);
      i = end < 0 ? len : end + 1;
      continue;
    }
    if (html.startsWith('</', lt)) {
      const end: number = html.indexOf('>', lt);
      if (end < 0) {
        break;
      }
      const name: string = html.substring(lt + 2, end).trim().toLowerCase();
      for (let k: number = stack.length - 1; k >= 1; k--) {
        if (stack[k].tagName === name) {
          stack.length = k;
          break;
        }
      }
      i = end + 1;
      continue;
    }
    const end: number = findTagEnd(html, lt);
    if (end < 0) {
      top.childNodes.push(new HtmlText(html.substring(lt)));
      break;
    }
    const tagContent: string = html.substring(lt + 1, end);
    const parsedTag: ParsedTag = parseTagContent(tagContent);
    if (parsedTag.tagName === '' || /[^a-zA-Z0-9-]/.test(parsedTag.tagName)) {
      top.childNodes.push(new HtmlText(html.substring(lt, end + 1)));
      i = end + 1;
      continue;
    }
    const el: HtmlElement = new HtmlElement();
    el.tagName = parsedTag.tagName;
    el.attrs = parsedTag.attrs;
    el.parent = top;
    top.childNodes.push(el);
    if (el.tagName === 'script' || el.tagName === 'style') {
      const closeRe: RegExp = new RegExp('</' + el.tagName + '\\s*>', 'gi');
      closeRe.lastIndex = end + 1;
      const m: RegExpExecArray | null = closeRe.exec(html);
      if (m !== null) {
        const raw: string = html.substring(end + 1, m.index);
        el.childNodes.push(new HtmlText(raw));
        i = m.index + m[0].length;
      } else {
        el.childNodes.push(new HtmlText(html.substring(end + 1)));
        i = len;
      }
      continue;
    }
    if (!parsedTag.selfClosing && VOID_TAGS.indexOf(el.tagName) < 0) {
      stack.push(el);
    }
    i = end + 1;
  }
  return root;
}
