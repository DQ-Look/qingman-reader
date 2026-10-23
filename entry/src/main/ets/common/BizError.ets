/**
 * 业务错误定义
 */
export class BizError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'BizError';
    this.code = code;
  }
}

export class UnsupportedRuleError extends BizError {
  constructor(message: string) {
    super('unsupportedRule', message);
    this.name = 'UnsupportedRuleError';
  }
}

export class NetworkError extends BizError {
  constructor(message: string) {
    super('network', message);
    this.name = 'NetworkError';
  }
}

export class ParseError extends BizError {
  constructor(message: string) {
    super('parse', message);
    this.name = 'ParseError';
  }
}

export class EmptyResultError extends BizError {
  constructor(message: string) {
    super('empty', message);
    this.name = 'EmptyResultError';
  }
}
