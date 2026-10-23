/**
 * 简化 CSS 选择器引擎
 * 支持：tag / .class / #id 组合、后代（空格）、:eq(n) / :nth-child(n)
 */
import { HtmlElement } from './HtmlParser';

export class SimpleSelector {
  tag: string = '';
  id: string = '';
  classes: string[] = [];
  eqIndex: number = -1;
  nthChild: number = -1;
}

export function parseSimpleSelector(token: string): SimpleSelector | null {
  const sel: SimpleSelector = new SimpleSelector();
  let body: string = token;
  const pseudoMatch: RegExpMatchArray | null = token.match(/:(eq|nth-child)\((\d+)\)$/);
  if (pseudoMatch !== null) {
    if (pseudoMatch[1] === 'eq') {
      sel.eqIndex = Number(pseudoMatch[2]);
    } else {
      sel.nthChild = Number(pseudoMatch[2]);
    }
    const idx: number = pseudoMatch.index as number;
    body = token.substring(0, idx);
  }
  let buf: string = '';
  let mode: number = 0; // 0=tag 1=class 2=id
  const flush = (): void => {
    if (buf === '') {
      return;
    }
    if (mode === 0) {
      sel.tag = buf.toLowerCase();
    } else if (mode === 1) {
      sel.classes.push(buf);
    } else {
      sel.id = buf;
    }
    buf = '';
  };
  for (let i: number = 0; i < body.length; i++) {
    const c: string = body.charAt(i);
    if (c === '.') {
      flush();
      mode = 1;
    } else if (c === '#') {
      flush();
      mode = 2;
    } else {
      buf += c;
    }
  }
  flush();
  if (sel.tag === '' && sel.id === '' && sel.classes.length === 0) {
    return null;
  }
  return sel;
}

function matchesSelector(el: HtmlElement, sel: SimpleSelector): boolean {
  if (sel.tag !== '' && el.tagName !== sel.tag) {
    return false;
  }
  if (sel.id !== '' && el.getAttr('id') !== sel.id) {
    return false;
  }
  const classes: string[] = el.classList();
  for (let i: number = 0; i < sel.classes.length; i++) {
    if (classes.indexOf(sel.classes[i]) < 0) {
      return false;
    }
  }
  return true;
}

function nthChildOf(el: HtmlElement, oneBased: number): boolean {
  const parent: HtmlElement | null = el.parent;
  if (parent === null) {
    return false;
  }
  const siblings: HtmlElement[] = parent.children();
  for (let i: number = 0; i < siblings.length; i++) {
    if (siblings[i] === el) {
      return (i + 1) === oneBased;
    }
  }
  return false;
}

/**
 * 在 root 子树内执行 CSS 选择器（后代组合）
 */
export function selectByCss(root: HtmlElement, selector: string): HtmlElement[] {
  const parts: string[] = selector.trim().split(/\s+/);
  if (parts.length === 0 || parts[0] === '') {
    return [];
  }
  let current: HtmlElement[] = [];
  for (let p: number = 0; p < parts.length; p++) {
    const sel: SimpleSelector | null = parseSimpleSelector(parts[p]);
    if (sel === null) {
      return [];
    }
    const needNth: boolean = sel.nthChild >= 0;
    const matched: HtmlElement[] = [];
    if (p === 0) {
      const candidates: HtmlElement[] = root.descendants();
      for (let i: number = 0; i < candidates.length; i++) {
        const el: HtmlElement = candidates[i];
        if (matchesSelector(el, sel) && (!needNth || nthChildOf(el, sel.nthChild))) {
          matched.push(el);
        }
      }
    } else {
      for (let c: number = 0; c < current.length; c++) {
        const candidates: HtmlElement[] = current[c].descendants();
        for (let i: number = 0; i < candidates.length; i++) {
          const el: HtmlElement = candidates[i];
          if (matched.indexOf(el) >= 0) {
            continue;
          }
          if (matchesSelector(el, sel) && (!needNth || nthChildOf(el, sel.nthChild))) {
            matched.push(el);
          }
        }
      }
    }
    if (sel.eqIndex >= 0) {
      current = sel.eqIndex < matched.length ? [matched[sel.eqIndex]] : [];
    } else {
      current = matched;
    }
    if (current.length === 0) {
      return [];
    }
  }
  return current;
}
