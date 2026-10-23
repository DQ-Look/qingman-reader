/**
 * 规则引擎门面：对齐 Legado 非JS规则子集
 * 支持：$.JSONPath / @css: / 默认规则(class@tag@text) / :regex 列表规则
 *       || 或选择、&& 并取、##正则替换## 后缀
 * 不支持：@js:、<js>、{{js}}、@XPath:、@get/@put（抛出 UnsupportedRuleError）
 */
import { HtmlElement, parseHtml } from './HtmlParser';
import { jsonPathQuery, jsonValueToString } from './JsonPath';
import { selectByCss } from './CssSelector';
import { UnsupportedRuleError, BizError } from '../common/BizError';
import { decodeEntities } from './RuleUtils';

export class RuleReplace {
  mainRule: string = '';
  pattern: string = '';
  replacement: string = '';
}

export class RuleStep {
  kind: string = ''; // class | id | tag | text | html | ownText | all | children | attr
  name: string = '';
  index: number = -1;
}

/**
 * 顶层分割规则字符串（跳过引号与括号内的分隔符）
 */
export function splitTopLevel(rule: string, sep: string): string[] {
  const results: string[] = [];
  let depth: number = 0;
  let quote: string = '';
  let buf: string = '';
  let i: number = 0;
  const len: number = rule.length;
  while (i < len) {
    const c: string = rule.charAt(i);
    if (quote !== '') {
      buf += c;
      if (c === quote) {
        quote = '';
      }
      i++;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      buf += c;
      i++;
      continue;
    }
    if (c === '(' || c === '[' || c === '{') {
      depth++;
      buf += c;
      i++;
      continue;
    }
    if (c === ')' || c === ']' || c === '}') {
      depth--;
      buf += c;
      i++;
      continue;
    }
    if (depth === 0 && rule.startsWith(sep, i)) {
      results.push(buf);
      buf = '';
      i += sep.length;
      continue;
    }
    buf += c;
    i++;
  }
  results.push(buf);
  return results;
}

function parseRuleStep(s: string): RuleStep | null {
  const step: string = s.trim();
  if (step === '') {
    return null;
  }
  const rs: RuleStep = new RuleStep();
  const firstDot: number = step.indexOf('.');
  const head: string = firstDot < 0 ? step : step.substring(0, firstDot);
  const tail: string = firstDot < 0 ? '' : step.substring(firstDot + 1);
  const lowerHead: string = head.toLowerCase();
  if (lowerHead === 'class' || lowerHead === 'tag' || lowerHead === 'id') {
    rs.kind = lowerHead;
    let name: string = tail;
    let idx: number = -1;
    const lastDot: number = tail.lastIndexOf('.');
    if (lastDot >= 0) {
      const idxStr: string = tail.substring(lastDot + 1);
      if (/^\d+$/.test(idxStr)) {
        idx = Number(idxStr);
        name = tail.substring(0, lastDot);
      }
    }
    rs.name = name;
    rs.index = idx;
    return rs;
  }
  if (lowerHead === 'text' || lowerHead === 'owntext' || lowerHead === 'html'
    || lowerHead === 'all' || lowerHead === 'children') {
    rs.kind = lowerHead === 'owntext' ? 'ownText' : lowerHead;
    if (/^\d+$/.test(tail)) {
      rs.index = Number(tail);
    }
    return rs;
  }
  rs.kind = 'attr';
  rs.name = step;
  return rs;
}

function applyIndex(list: HtmlElement[], idx: number): HtmlElement[] {
  if (idx < 0) {
    return list;
  }
  if (idx < list.length) {
    return [list[idx]];
  }
  return [];
}

export class AnalyzeRule {
  private content: string = '';
  private isJsonCtx: boolean = false;
  private jsonRoot: Object | null = null;
  private domRoot: HtmlElement | null = null;

  constructor(content: string) {
    this.content = content;
    const t: string = content.trim();
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        this.jsonRoot = JSON.parse(t) as Object;
        this.isJsonCtx = true;
      } catch (e) {
        this.isJsonCtx = false;
      }
    }
  }

  private getDom(): HtmlElement {
    if (this.domRoot === null) {
      this.domRoot = parseHtml(this.content);
    }
    return this.domRoot;
  }

  /**
   * 列表规则：返回元素上下文字符串数组
   */
  getElements(ruleStr: string): string[] {
    const rule: string = ruleStr.trim();
    if (rule === '') {
      return [];
    }
    const split: RuleReplace = this.splitReplace(rule);
    const alternatives: string[] = splitTopLevel(split.mainRule, '||');
    let lastUnsupported: UnsupportedRuleError | null = null;
    for (let a: number = 0; a < alternatives.length; a++) {
      const conjuncts: string[] = splitTopLevel(alternatives[a], '&&');
      const results: string[] = [];
      let failed: boolean = false;
      for (let c: number = 0; c < conjuncts.length; c++) {
        try {
          const items: string[] = this.evalListSegment(conjuncts[c]);
          for (let i: number = 0; i < items.length; i++) {
            results.push(items[i]);
          }
        } catch (e) {
          if (e instanceof UnsupportedRuleError) {
            lastUnsupported = e;
            failed = true;
            break;
          }
          throw new BizError('analyze', e instanceof Error ? e.message : String(e));
        }
      }
      if (!failed) {
        const replaced: string[] = this.applyReplaceToList(results, split);
        if (replaced.length > 0) {
          return replaced;
        }
      }
    }
    if (lastUnsupported !== null) {
      throw lastUnsupported;
    }
    return [];
  }

  /**
   * 字符串规则
   */
  getString(ruleStr: string): string {
    const rule: string = ruleStr.trim();
    if (rule === '') {
      return '';
    }
    const split: RuleReplace = this.splitReplace(rule);
    const alternatives: string[] = splitTopLevel(split.mainRule, '||');
    let lastUnsupported: UnsupportedRuleError | null = null;
    for (let a: number = 0; a < alternatives.length; a++) {
      const conjuncts: string[] = splitTopLevel(alternatives[a], '&&');
      let failed: boolean = false;
      const pieces: string[] = [];
      for (let c: number = 0; c < conjuncts.length; c++) {
        try {
          pieces.push(this.evalStringSegment(conjuncts[c]));
        } catch (e) {
          if (e instanceof UnsupportedRuleError) {
            lastUnsupported = e;
            failed = true;
            break;
          }
          throw new BizError('analyze', e instanceof Error ? e.message : String(e));
        }
      }
      if (!failed) {
        const joined: string = pieces.join('');
        if (joined.trim() !== '') {
          return this.applyReplaceToText(joined, split);
        }
      }
    }
    if (lastUnsupported !== null) {
      throw lastUnsupported;
    }
    return '';
  }

  getStringOr(ruleStr: string, dflt: string): string {
    const v: string = this.getString(ruleStr);
    if (v === '') {
      return dflt;
    }
    return v;
  }

  private splitReplace(rule: string): RuleReplace {
    const rp: RuleReplace = new RuleReplace();
    const idx: number = rule.indexOf('##');
    if (idx >= 0) {
      rp.mainRule = rule.substring(0, idx);
      const tail: string = rule.substring(idx + 2);
      const parts: string[] = tail.split('##');
      rp.pattern = parts.length > 0 ? parts[0] : '';
      rp.replacement = parts.length > 1 ? parts[1] : '';
    } else {
      rp.mainRule = rule;
    }
    return rp;
  }

  private applyReplaceToText(text: string, rp: RuleReplace): string {
    if (rp.pattern === '') {
      return text;
    }
    try {
      return text.replace(new RegExp(rp.pattern, 'g'), rp.replacement);
    } catch (e) {
      return text;
    }
  }

  private applyReplaceToList(list: string[], rp: RuleReplace): string[] {
    if (rp.pattern === '') {
      return list;
    }
    const out: string[] = [];
    for (let i: number = 0; i < list.length; i++) {
      out.push(this.applyReplaceToText(list[i], rp));
    }
    return out;
  }

  /**
   * 规则模式识别。返回 [模式, 剥离前缀后的规则]
   */
  private detectMode(rule: string): string[] {
    let r: string = rule.trim();
    let mode: string = 'default';
    if (r.startsWith('@@')) {
      mode = 'default';
      r = r.substring(2);
    } else if (r.startsWith('@json:') || r.startsWith('@JSON:')) {
      mode = 'json';
      r = r.substring(6);
    } else if (r.startsWith('@css:') || r.startsWith('@CSS:')) {
      mode = 'css';
      r = r.substring(5);
    } else if (r.startsWith('@XPath:') || r.startsWith('@xpath:') || r.startsWith('//')) {
      throw new UnsupportedRuleError('XPath 规则暂不支持');
    } else if (r.startsWith('@js:') || r.startsWith('@JS:')) {
      throw new UnsupportedRuleError('JS 规则暂不支持');
    } else if (r.indexOf('<js') >= 0 || r.indexOf('{{') >= 0) {
      throw new UnsupportedRuleError('JS 规则暂不支持');
    } else if (r.startsWith('@get:') || r.startsWith('@put:')) {
      throw new UnsupportedRuleError('变量规则暂不支持');
    } else if (r.startsWith(':')) {
      mode = 'regex';
      r = r.substring(1);
    } else if (r.startsWith('$.') || r.startsWith('$[')) {
      mode = 'json';
    }
    const out: string[] = [mode, r];
    return out;
  }

  private evalListSegment(rule: string): string[] {
    if (rule.trim() === '') {
      return [];
    }
    const detected: string[] = this.detectMode(rule);
    const mode: string = detected[0];
    const r: string = detected[1];
    if (mode === 'json') {
      return this.jsonList(r);
    }
    if (mode === 'regex') {
      return this.regexList(r);
    }
    if (mode === 'css') {
      return this.cssList(r);
    }
    return this.defaultList(r);
  }

  private evalStringSegment(rule: string): string {
    if (rule.trim() === '') {
      return '';
    }
    const detected: string[] = this.detectMode(rule);
    const mode: string = detected[0];
    const r: string = detected[1];
    if (mode === 'json') {
      return this.jsonString(r);
    }
    if (mode === 'regex') {
      return this.regexString(r);
    }
    if (mode === 'css') {
      return this.cssString(r);
    }
    return this.defaultString(r);
  }

  private jsonList(path: string): string[] {
    if (!this.isJsonCtx || this.jsonRoot === null) {
      return [];
    }
    const found: Object[] = jsonPathQuery(this.jsonRoot, path.trim());
    let items: Object[] = found;
    if (found.length === 1 && Array.isArray(found[0])) {
      items = found[0] as Object[];
    }
    const out: string[] = [];
    for (let i: number = 0; i < items.length; i++) {
      out.push(jsonValueToString(items[i]));
    }
    return out;
  }

  private jsonString(path: string): string {
    if (!this.isJsonCtx || this.jsonRoot === null) {
      return '';
    }
    const found: Object[] = jsonPathQuery(this.jsonRoot, path.trim());
    if (found.length === 0) {
      return '';
    }
    return jsonValueToString(found[0]);
  }

  private stripRegexSlashes(pattern: string): string[] {
    let p: string = pattern.trim();
    let flags: string = 'g';
    if (p.length > 2 && p.startsWith('/') && p.lastIndexOf('/') > 0) {
      const lastSlash: number = p.lastIndexOf('/');
      const maybeFlags: string = p.substring(lastSlash + 1);
      if (/^[a-z]*$/.test(maybeFlags)) {
        flags = maybeFlags.indexOf('g') >= 0 ? maybeFlags : maybeFlags + 'g';
        p = p.substring(1, lastSlash);
      }
    }
    const out: string[] = [p, flags];
    return out;
  }

  private regexList(pattern: string): string[] {
    const stripped: string[] = this.stripRegexSlashes(pattern);
    let re: RegExp;
    try {
      re = new RegExp(stripped[0], stripped[1]);
    } catch (e) {
      return [];
    }
    const out: string[] = [];
    let m: RegExpExecArray | null = re.exec(this.content);
    while (m !== null) {
      if (m.length > 1) {
        const g1: string = m[1] === undefined ? '' : m[1];
        out.push(g1);
      } else {
        out.push(m[0]);
      }
      if (m.index === re.lastIndex) {
        re.lastIndex++;
      }
      m = re.exec(this.content);
    }
    return out;
  }

  private regexString(pattern: string): string {
    const stripped: string[] = this.stripRegexSlashes(pattern);
    let re: RegExp;
    try {
      re = new RegExp(stripped[0], stripped[1]);
    } catch (e) {
      return '';
    }
    const m: RegExpExecArray | null = re.exec(this.content);
    if (m === null) {
      return '';
    }
    if (m.length > 1 && m[1] !== undefined) {
      return m[1];
    }
    return m[0];
  }

  private cssList(selectorWithSteps: string): string[] {
    const parts: string[] = selectorWithSteps.split('@');
    const els: HtmlElement[] = selectByCss(this.getDom(), parts[0].trim());
    const terms: RuleStep[] = [];
    for (let i: number = 1; i < parts.length; i++) {
      const st: RuleStep | null = parseRuleStep(parts[i]);
      if (st !== null) {
        terms.push(st);
      }
    }
    const out: string[] = [];
    if (terms.length === 0) {
      for (let i: number = 0; i < els.length; i++) {
        out.push(els[i].outerHtml());
      }
      return out;
    }
    for (let i: number = 0; i < els.length; i++) {
      const v: string = this.terminalValue(els[i], terms[0]);
      if (v !== '') {
        out.push(v);
      }
    }
    return out;
  }

  private cssString(selectorWithSteps: string): string {
    const parts: string[] = selectorWithSteps.split('@');
    const els: HtmlElement[] = selectByCss(this.getDom(), parts[0].trim());
    if (els.length === 0) {
      return '';
    }
    const terms: RuleStep[] = [];
    for (let i: number = 1; i < parts.length; i++) {
      const st: RuleStep | null = parseRuleStep(parts[i]);
      if (st !== null) {
        terms.push(st);
      }
    }
    if (terms.length === 0) {
      return els[0].textContent();
    }
    return this.terminalValue(els[0], terms[0]);
  }

  private parseSteps(rule: string): RuleStep[] {
    const stepStrs: string[] = rule.split('@');
    const steps: RuleStep[] = [];
    for (let i: number = 0; i < stepStrs.length; i++) {
      const st: RuleStep | null = parseRuleStep(stepStrs[i]);
      if (st === null) {
        continue;
      }
      steps.push(st);
    }
    return steps;
  }

  private firstTerminalIndex(steps: RuleStep[]): number {
    for (let i: number = 0; i < steps.length; i++) {
      const kind: string = steps[i].kind;
      if (kind !== 'class' && kind !== 'id' && kind !== 'tag') {
        return i;
      }
    }
    return steps.length;
  }

  private walkElements(steps: RuleStep[], stopAt: number): HtmlElement[] {
    let current: HtmlElement[] = [this.getDom()];
    for (let i: number = 0; i < stopAt; i++) {
      const st: RuleStep = steps[i];
      const next: HtmlElement[] = [];
      if (st.kind === 'class') {
        for (let k: number = 0; k < current.length; k++) {
          const found: HtmlElement[] = current[k].getElementsByClassName(st.name);
          for (let j: number = 0; j < found.length; j++) {
            next.push(found[j]);
          }
        }
      } else if (st.kind === 'tag') {
        for (let k: number = 0; k < current.length; k++) {
          const found: HtmlElement[] = current[k].getElementsByTagName(st.name);
          for (let j: number = 0; j < found.length; j++) {
            next.push(found[j]);
          }
        }
      } else if (st.kind === 'id') {
        for (let k: number = 0; k < current.length; k++) {
          const found: HtmlElement | null = current[k].getElementById(st.name);
          if (found !== null) {
            next.push(found);
          }
        }
      }
      current = applyIndex(next, st.index);
      if (current.length === 0) {
        return [];
      }
    }
    return current;
  }

  private defaultList(rule: string): string[] {
    const steps: RuleStep[] = this.parseSteps(rule);
    if (steps.length === 0) {
      return [];
    }
    const tIdx: number = this.firstTerminalIndex(steps);
    const els: HtmlElement[] = this.walkElements(steps, tIdx);
    const out: string[] = [];
    if (tIdx >= steps.length) {
      for (let i: number = 0; i < els.length; i++) {
        out.push(els[i].outerHtml());
      }
      return out;
    }
    for (let i: number = 0; i < els.length; i++) {
      const v: string = this.terminalValue(els[i], steps[tIdx]);
      if (v !== '') {
        out.push(v);
      }
    }
    return out;
  }

  private defaultString(rule: string): string {
    const steps: RuleStep[] = this.parseSteps(rule);
    if (steps.length === 0) {
      return '';
    }
    const tIdx: number = this.firstTerminalIndex(steps);
    const els: HtmlElement[] = this.walkElements(steps, tIdx);
    if (els.length === 0) {
      return '';
    }
    if (tIdx >= steps.length) {
      return els[0].textContent();
    }
    return this.terminalValue(els[0], steps[tIdx]);
  }

  private terminalValue(el: HtmlElement, st: RuleStep): string {
    if (st.kind === 'text') {
      if (st.index >= 0) {
        const tns = el.textNodes();
        let count: number = 0;
        for (let i: number = 0; i < tns.length; i++) {
          const decoded: string = decodeEntities(tns[i].text).replace(/\s+/g, ' ').trim();
          if (decoded !== '') {
            if (count === st.index) {
              return decoded;
            }
            count++;
          }
        }
        return '';
      }
      return el.textContent();
    }
    if (st.kind === 'html' || st.kind === 'children') {
      return el.innerHtml();
    }
    if (st.kind === 'all') {
      return el.outerHtml();
    }
    if (st.kind === 'ownText') {
      let s: string = '';
      const tns = el.textNodes();
      for (let i: number = 0; i < tns.length; i++) {
        s += tns[i].text;
      }
      return decodeEntities(s).replace(/\s+/g, ' ').trim();
    }
    return el.getAttr(st.name);
  }
}
