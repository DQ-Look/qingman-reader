/**
 * 全局应用 Context 持有（EntryAbility onCreate 时设置）
 */
import { common } from '@kit.AbilityKit';
import { BizError } from './BizError';

export class AppContextHolder {
  private static appCtx: common.Context | null = null;

  static set(context: common.Context): void {
    AppContextHolder.appCtx = context;
  }

  static get(): common.Context {
    if (AppContextHolder.appCtx === null) {
      throw new BizError('init', '应用上下文未初始化');
    }
    return AppContextHolder.appCtx;
  }
}
