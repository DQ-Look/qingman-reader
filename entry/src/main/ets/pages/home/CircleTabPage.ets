/**
 * 社区 Tab：还原原版 circle_fragment_layout
 * 顶部背景 + "社区"标题 + 消息入口；分类/排序 Tab；帖子列表（本版未开放）
 */
import { StorageKeys } from '../../model/ReadConfigModels';

@Component
export struct CircleTabPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.SAFE_AREA_TOP_VP) statusBarVp: number = 34;
  @State currentSort: number = 0;

  @Builder
  sortTabItem(title: string, index: number) {
    Text(title)
      .fontSize(15)
      .fontWeight(index === this.currentSort ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(index === this.currentSort ? '#333333' : '#999999')
      .padding({ left: 8, right: 8 })
      .onClick(() => {
        this.currentSort = index;
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image($r('app.media.circle_fragment_top_bg'))
            .width('100%')
            .aspectRatio(390 / 75)
            .objectFit(ImageFit.Fill)
          Row() {
            Text('社区')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111111')
              .margin({ left: 12, bottom: 8 })
            Blank()
            Image($r('app.media.new_mine_fragment_message'))
              .width(24)
              .height(24)
              .margin({ right: 16, bottom: 4 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .padding({ top: this.statusBarVp })

        Row() {
          this.sortTabItem('关注', 0)
          this.sortTabItem('推荐', 1)
          this.sortTabItem('热榜', 2)
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')

        Column({ space: 12 }) {
          Text('社区功能未开放')
            .fontSize(14)
            .fontColor('#999999')
          Text('本版本专注于阅读体验')
            .fontSize(12)
            .fontColor('#BBBBBB')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')

      Image($r('app.media.circle_fab_add'))
        .width(56)
        .height(56)
        .margin({ right: 20, bottom: 76 })
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
