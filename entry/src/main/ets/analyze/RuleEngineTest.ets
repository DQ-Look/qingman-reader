/**
 * 规则引擎 fixture 自测：不依赖网络，验证 JSONPath/CSS/默认规则/正则/替换/URL 解析/书源解析
 */
import { AnalyzeRule, splitTopLevel } from './AnalyzeRule';
import { decodeEntities, htmlToReadableText, resolveUrl, cleanTextResult } from './RuleUtils';
import { analyzeUrl } from '../service/AnalyzeUrl';
import { UnsupportedRuleError } from '../common/BizError';
import { parseBookSourceList, bookSourceListToJson } from '../model/BookSourceModels';

export class RuleTestResult {
  name: string = '';
  passed: boolean = false;
  message: string = '';

  constructor(name: string, passed: boolean, message: string) {
    this.name = name;
    this.passed = passed;
    this.message = message;
  }
}

const JSON_PAGE: string = '{"code":0,"data":{"books":[' +
  '{"title":"斗破苍穹","author":"天蚕土豆","url":"/b/1"},' +
  '{"title":"凡人修仙传","author":"忘语","url":"/b/2"}]}}';

const HTML_PAGE: string = '<html><head><title>书库</title></head><body>' +
  '<div class="list">' +
  '<div class="bookbox"><h4><a href="/b/1">书名1</a></h4><p class="author">作者1</p></div>' +
  '<div class="bookbox"><h4><a href="/b/2">书名2</a></h4><p class="author">作者2</p></div>' +
  '</div></body></html>';

const SOURCE_JSON: string = '[{"bookSourceName":"测试源","bookSourceUrl":"https://test.example.com",' +
  '"bookSourceGroup":"测试","enabled":true,"enabledExplore":true,' +
  '"searchUrl":"https://test.example.com/s?q=searchKey&page=searchPage",' +
  '"exploreUrl":[{"title":"玄幻","url":"https://test.example.com/cat/1/{{page}}"}],' +
  '"ruleSearch":{"bookList":"class.bookbox","name":"tag.h4@text","author":"class.author@text","bookUrl":"tag.a.0@href"},' +
  '"ruleToc":{"chapterList":"class.chapter@tag.a","chapterName":"text","chapterUrl":"href"},' +
  '"ruleContent":{"content":"id.content@text","replaceRegex":"测试正则##"}}]';

export function runRuleEngineTests(): RuleTestResult[] {
  const results: RuleTestResult[] = [];
  const check: (name: string, cond: boolean, msg: string) => void = (name: string, cond: boolean, msg: string) => {
    results.push(new RuleTestResult(name, cond, cond ? '' : msg));
  };

  // 1. 实体解码
  check('decodeEntities 命名+数字实体',
    decodeEntities('&lt;a&gt;&amp;&nbsp;&#66;') === '<a>& B',
    '实际: ' + decodeEntities('&lt;a&gt;&amp;&nbsp;&#66;'));

  // 2. HTML 转可读文本
  const readable: string = htmlToReadableText('<p>第一段&nbsp;文字</p><br>第二行');
  check('htmlToReadableText',
    readable.indexOf('第一段 文字') >= 0 && readable.indexOf('第二行') >= 0,
    '实际: ' + readable);

  // 3. cleanTextResult 纯文本
  check('cleanTextResult 纯文本',
    cleanTextResult('  a\r\n\r\n\r\nb ') === 'a\n\nb',
    '实际: ' + cleanTextResult('  a\r\n\r\n\r\nb '));

  // 4. resolveUrl
  check('resolveUrl 根路径',
    resolveUrl('https://a.com/x/y', '/z') === 'https://a.com/z',
    '实际: ' + resolveUrl('https://a.com/x/y', '/z'));
  check('resolveUrl 相对路径',
    resolveUrl('https://a.com/x/y', 'z') === 'https://a.com/x/z',
    '实际: ' + resolveUrl('https://a.com/x/y', 'z'));
  check('resolveUrl 协议相对',
    resolveUrl('https://a.com', '//cdn.b.com/i.png') === 'https://cdn.b.com/i.png',
    '实际: ' + resolveUrl('https://a.com', '//cdn.b.com/i.png'));
  check('resolveUrl 上级目录',
    resolveUrl('https://a.com/x/y/p', '../z') === 'https://a.com/x/z',
    '实际: ' + resolveUrl('https://a.com/x/y/p', '../z'));

  // 5. splitTopLevel
  const parts: string[] = splitTopLevel('$.a||$.b||$.c', '||');
  check('splitTopLevel 或分割',
    parts.length === 3 && parts[0] === '$.a' && parts[2] === '$.c',
    '实际: ' + parts.join('|'));

  // 6. JSONPath 列表
  const jsonPage: AnalyzeRule = new AnalyzeRule(JSON_PAGE);
  const bookEls: string[] = jsonPage.getElements('$.data.books');
  check('JSONPath 列表',
    bookEls.length === 2,
    '实际: ' + bookEls.length);
  if (bookEls.length === 2) {
    const el0: AnalyzeRule = new AnalyzeRule(bookEls[0]);
    check('JSONPath 字段',
      el0.getString('$.title') === '斗破苍穹' && el0.getString('$.author') === '天蚕土豆',
      '实际: ' + el0.getString('$.title'));
  }

  // 7. JSONPath || 与 ## 替换
  const jsonAlt: AnalyzeRule = new AnalyzeRule('{"a":"x"}');
  check('JSONPath || 备选',
    jsonAlt.getString('$.missing||$.a') === 'x',
    '实际: ' + jsonAlt.getString('$.missing||$.a'));
  const jsonRep: AnalyzeRule = new AnalyzeRule('{"a":"hello world"}');
  check('JSONPath ## 正则替换',
    jsonRep.getString('$.a##o##0') === 'hell0 w0rld',
    '实际: ' + jsonRep.getString('$.a##o##0'));

  // 8. 默认规则（class@tag@text）
  const htmlPage: AnalyzeRule = new AnalyzeRule(HTML_PAGE);
  const boxes: string[] = htmlPage.getElements('class.bookbox');
  check('默认规则 列表 class.bookbox',
    boxes.length === 2,
    '实际: ' + boxes.length);
  if (boxes.length === 2) {
    const box0: AnalyzeRule = new AnalyzeRule(boxes[0]);
    check('默认规则 tag.h4@text',
      box0.getString('tag.h4@text') === '书名1',
      '实际: ' + box0.getString('tag.h4@text'));
    check('默认规则 索引 tag.a.0@href',
      box0.getString('tag.a.0@href') === '/b/1',
      '实际: ' + box0.getString('tag.a.0@href'));
    check('默认规则 class.author@text',
      box0.getString('class.author@text') === '作者1',
      '实际: ' + box0.getString('class.author@text'));
  }

  // 9. @css 规则
  const cssBoxes: string[] = htmlPage.getElements('@css:.bookbox');
  check('@css 列表',
    cssBoxes.length === 2,
    '实际: ' + cssBoxes.length);
  check('@css 字段',
    htmlPage.getString('@css:h4@text') === '书名1',
    '实际: ' + htmlPage.getString('@css:h4@text'));
  check('@css 属性',
    htmlPage.getString('@css:a@href') === '/b/1',
    '实际: ' + htmlPage.getString('@css:a@href'));

  // 10. :regex 规则
  check(':regex 字符串提取',
    htmlPage.getString(':<title>(.*?)</title>') === '书库',
    '实际: ' + htmlPage.getString(':<title>(.*?)</title>'));
  const regexBoxes: string[] = htmlPage.getElements(':<div class="bookbox">');
  check(':regex 列表',
    regexBoxes.length === 2,
    '实际: ' + regexBoxes.length);

  // 11. 不支持的规则识别
  let jsThrew: boolean = false;
  try {
    htmlPage.getString('@js:1+1');
  } catch (e) {
    jsThrew = e instanceof UnsupportedRuleError;
  }
  check('JS 规则抛 UnsupportedRuleError', jsThrew, '未抛出预期异常');
  let xpThrew: boolean = false;
  try {
    htmlPage.getString('@XPath://div');
  } catch (e) {
    xpThrew = e instanceof UnsupportedRuleError;
  }
  check('XPath 规则抛 UnsupportedRuleError', xpThrew, '未抛出预期异常');

  // 12. analyzeUrl 占位符
  const a1 = analyzeUrl('https://a.com/s?k=searchKey&page=searchPage', '斗破', 3);
  check('analyzeUrl searchKey 编码 + searchPage',
    a1.url === 'https://a.com/s?k=' + encodeURIComponent('斗破') + '&page=3',
    '实际: ' + a1.url);
  const a2 = analyzeUrl('https://a.com/list/{{page}}.html', '', 7);
  check('analyzeUrl {{page}}',
    a2.url === 'https://a.com/list/7.html',
    '实际: ' + a2.url);
  const a3 = analyzeUrl('https://a.com/api,{"method":"POST","body":"kw=searchKey&pn={{page}}",' +
    '"headers":{"User-Agent":"Tester"},"charset":"gbk"}', '大奉打更人', 2);
  check('analyzeUrl 选项解析 method/charset',
    a3.options.method === 'POST' && a3.options.charset === 'gbk',
    '实际: ' + a3.options.method + '/' + a3.options.charset);
  check('analyzeUrl body 原文 key + page',
    a3.options.body === 'kw=大奉打更人&pn=2',
    '实际: ' + a3.options.body);
  check('analyzeUrl headers',
    a3.options.headers['User-Agent'] === 'Tester',
    '实际: ' + a3.options.headers['User-Agent']);

  // 13. 书源解析与序列化
  const sources = parseBookSourceList(SOURCE_JSON);
  check('parseBookSourceList 数量',
    sources.length === 1,
    '实际: ' + sources.length);
  if (sources.length === 1) {
    const s = sources[0];
    check('书源字段解析',
      s.bookSourceName === '测试源' && s.bookSourceUrl === 'https://test.example.com'
        && s.ruleSearch.bookList === 'class.bookbox'
        && s.ruleToc.chapterName === 'text'
        && s.ruleContent.content === 'id.content@text',
      '实际: ' + s.bookSourceName + '/' + s.ruleSearch.bookList);
    const exported: string = bookSourceListToJson(sources);
    const reparsed = parseBookSourceList(exported);
    check('书源序列化回读',
      reparsed.length === 1 && reparsed[0].bookSourceUrl === s.bookSourceUrl
        && reparsed[0].ruleSearch.bookList === 'class.bookbox'
        && reparsed[0].ruleContent.replaceRegex === '测试正则##',
      '序列化回读不一致');
  }

  return results;
}
