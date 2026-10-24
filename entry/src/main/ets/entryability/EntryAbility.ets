/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { AppContextHolder } from '../common/AppContextHolder';
import { StorageKeys } from '../model/ReadConfigModels';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContextHolder.set(this.context);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 全局沉浸：内容加载完成后再铺满状态栏/手势条（与官方示例一致的时序，
      // 避免与 loadContent 竞态导致 NavDestination 系统标题栏渲染错位）。
      // 避让区高度须在全屏生效后读取（非全屏时窗口内容不与状态栏/手势条重叠，读值为 0）
      windowStage.getMainWindow().then((win: window.Window) => {
        win.setWindowLayoutFullScreen(true).then(() => {
          this.publishSafeAreaVp(win);
        }).catch(() => {
        });
        win.on('avoidAreaChange', () => {
          this.publishSafeAreaVp(win);
        });
      }).catch(() => {
      });
    });
  }

  /** 状态栏/手势条避让高度（vp）写入 AppStorage，供各页 @StorageProp 订阅 */
  private publishSafeAreaVp(win: window.Window): void {
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      if (density <= 0) {
        return;
      }
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate<number>(StorageKeys.SAFE_AREA_TOP_VP, sys.topRect.height / density);
      AppStorage.setOrCreate<number>(StorageKeys.SAFE_AREA_BOTTOM_VP, nav.bottomRect.height / density);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to publish safe area. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}