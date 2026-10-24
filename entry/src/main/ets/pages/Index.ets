/**
 * 应用主页面：还原原版 IndexActivity 结构
 * 五 Tab：首页/分类/书架/社区/我的
 * 底部页签使用 HdsTabs 悬浮样式 + 沉浸光感材质（IMMERSIVE / ADAPTIVE）
 */
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { StorageKeys } from '../model/ReadConfigModels';
import { BookshelfPage } from './BookshelfPage';
import { HomeTabPage } from './home/HomeTabPage';
import { CategoryTabPage } from './home/CategoryTabPage';
import { CircleTabPage } from './home/CircleTabPage';
import { MineTabPage } from './home/MineTabPage';

@Entry
@Component
struct Index {
  @State pathStack: NavPathStack = new NavPathStack();
  private tabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    PersistentStorage.persistProp(StorageKeys.NIGHT_MODE, false);
    PersistentStorage.persistProp(StorageKeys.APP_THEME_INDEX, 0);
    PersistentStorage.persistProp(StorageKeys.READER_TEXT_SIZE, 19);
    PersistentStorage.persistProp(StorageKeys.READER_LINE_SPACING, 8);
    PersistentStorage.persistProp(StorageKeys.READER_PARAGRAPH_SPACING, 12);
    PersistentStorage.persistProp(StorageKeys.READER_THEME_INDEX, 0);
    PersistentStorage.persistProp(StorageKeys.BOOKSHELF_VERSION, 0);
    PersistentStorage.persistProp(StorageKeys.READ_TARGET_INDEX, -1);
    PersistentStorage.persistProp(StorageKeys.READ_TARGET_VERSION, 0);
    PersistentStorage.persistProp(StorageKeys.DEVICE_ID, '');
  }

  build() {
    Navigation(this.pathStack) {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomeTabPage({ pathStack: this.pathStack })
        }
        .tabBar(new BottomTabBarStyle($r('app.media.home_new_tab_one'), '首页'))

        TabContent() {
          CategoryTabPage({ pathStack: this.pathStack })
        }
        .tabBar(new BottomTabBarStyle($r('app.media.home_new_tab_two'), '分类'))

        TabContent() {
          BookshelfPage({ pathStack: this.pathStack })
        }
        .tabBar(new BottomTabBarStyle($r('app.media.home_new_tab_three'), '书架'))

        TabContent() {
          CircleTabPage({ pathStack: this.pathStack })
        }
        .tabBar(new BottomTabBarStyle($r('app.media.home_new_tab_four'), '社区'))

        TabContent() {
          MineTabPage({ pathStack: this.pathStack })
        }
        .tabBar(new BottomTabBarStyle($r('app.media.home_new_tab_five'), '我的'))
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .scrollable(false)
      .barOverlap(true)
      .barFloatingStyle({
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .width('100%')
      .height('100%')
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor('#FFFFFF')
  }
}
