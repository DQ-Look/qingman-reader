/**
 * 简化 JSONPath 求值器
 * 支持 $.a.b.c / $.a[0].b / $.a[*].b
 * 动态属性访问基于 Record<string, Object>（ArkTS 推荐方式）
 */

export function jsonPathQuery(root: Object, path: string): Object[] {
  const results: Object[] = [];
  if (!path.startsWith('$')) {
    return results;
  }
  let current: Object[] = [root];
  const rest: string = path.substring(1);
  const tokenRe: RegExp = /\.([^.\[\]]+)|\[(\d+|\*)\]/g;
  let m: RegExpExecArray | null = tokenRe.exec(rest);
  while (m !== null) {
    const next: Object[] = [];
    if (m[1] !== undefined && m[1] !== '') {
      const prop: string = m[1];
      for (let i: number = 0; i < current.length; i++) {
        const v: Object | null = getJsonProp(current[i], prop);
        if (v !== null) {
          next.push(v);
        }
      }
    } else {
      const sel: string = m[2];
      for (let i: number = 0; i < current.length; i++) {
        const obj: Object = current[i];
        if (Array.isArray(obj)) {
          const arr: Object[] = obj as Object[];
          if (sel === '*') {
            for (let k: number = 0; k < arr.length; k++) {
              next.push(arr[k]);
            }
          } else {
            const idx: number = Number(sel);
            if (idx >= 0 && idx < arr.length) {
              next.push(arr[idx]);
            }
          }
        }
      }
    }
    current = next;
    if (current.length === 0) {
      break;
    }
    m = tokenRe.exec(rest);
  }
  return current;
}

function getJsonProp(obj: Object, prop: string): Object | null {
  if (obj === null || obj === undefined) {
    return null;
  }
  if (Array.isArray(obj) || typeof obj !== 'object') {
    return null;
  }
  const rec: Record<string, Object> = obj as Record<string, Object>;
  const v: Object | undefined = rec[prop];
  if (v === undefined || v === null) {
    return null;
  }
  return v;
}

/**
 * 将 JSON 查询结果转为字符串（对象序列化，原始值 String 化）
 */
export function jsonValueToString(v: Object): string {
  if (typeof v === 'object') {
    return JSON.stringify(v);
  }
  return String(v);
}
