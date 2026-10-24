import { StorageKeys } from '../model/ReadConfigModels';

/**
 * 通用自定义标题栏：返回按钮 + 标题（替代系统 NavDestination 标题栏）。
 * 背景：setWindowLayoutFullScreen(true) 全屏布局下系统标题栏会被压塌
 * （布局高度异常、内容渲染错位进状态栏），故所有 NavDestination 页面
 * 统一 hideTitleBar(true) 并使用本组件自绘标题栏。
 * 使用约定：页面内容根组件需设置
 * .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
 * 使布局从 y=0 开始，本组件用 statusBarVp 自行避让状态栏。
 */
@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop textColor: string = '#182431';
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;
  pathStack: NavPathStack = new NavPathStack();
  onBack: () => void = () => {
  };

  build() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(26)
          .fontColor([this.textColor])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.pathStack.size() > 0) {
          this.pathStack.pop();
        }
        this.onBack();
      })

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 2 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.statusBarVp)
    .padding({ top: this.statusBarVp, left: 6, right: 16 })
    .alignItems(VerticalAlign.Center)
  }
}
