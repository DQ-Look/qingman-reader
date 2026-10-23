/**
 * 我的 Tab：还原原版 new_mine_fragment_layout
 * 顶部头像区 + 设置卡列表（书源管理/阅读设置/当前版本）
 */
@Component
export struct MineTabPage {
  pathStack: NavPathStack = new NavPathStack();

  openSourceManage(): void {
    this.pathStack.pushPathByName('sourceManage', null);
  }

  openSettings(): void {
    this.pathStack.pushPathByName('settings', null);
  }

  @Builder
  topIconRow() {
    Row() {
      Blank()
      Image($r('app.media.new_mine_fragment_message'))
        .width(24)
        .height(24)
        .margin({ right: 16 })
      Image($r('app.media.new_mine_fragment_setting'))
        .width(24)
        .height(24)
        .margin({ right: 16 })
        .onClick(() => {
          this.openSettings();
        })
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  settingRow(title: string, tips: string, action: () => void) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor('#111111')
      Blank()
      if (tips !== '') {
        Text(tips)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ right: 8 })
      }
      Image($r('app.media.home_right_icon'))
        .width(12)
        .height(12)
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action();
    })
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.topIconRow()

          Row({ space: 12 }) {
            Stack() {
              Image($r('app.media.default_user_avatar_icon'))
                .width(80)
                .height(80)
                .borderRadius(40)
            }
            .width(100)
            .height(100)
            .borderRadius(50)
            .backgroundColor('#FFFFFF')

            Column({ space: 6 }) {
              Text('书友')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#333333')
              Text('本地阅读 · 数据仅保存在本机')
                .fontSize(12)
                .fontColor('#999999')
            }
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .padding({ left: 12, top: 14 })
          .alignItems(VerticalAlign.Center)

          Column() {
            this.settingRow('书源管理', '', (): void => {
              this.openSourceManage();
            })
            Divider()
              .color('#F3F5F7')
              .margin({ left: 12 })
            this.settingRow('阅读设置', '', (): void => {
              this.openSettings();
            })
            Divider()
              .color('#F3F5F7')
              .margin({ left: 12 })
            this.settingRow('当前版本', '1.0.0', (): void => {
            })
          }
          .width('100%')
          .margin({ top: 24, left: 12, right: 12 })
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 88 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F5F7')
  }
}
