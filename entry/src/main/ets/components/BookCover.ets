/**
 * 书籍封面组件：有封面图显示图片，无封面显示书名首字占位
 */
@Component
export struct BookCover {
  @State coverUrl: string = '';
  bookName: string = '';
  coverWidth: Length = 96;
  coverHeight: Length = 128;
  radius: number = 4;
  textSize: number = 28;

  firstChar(): string {
    if (this.bookName.length > 0) {
      return this.bookName.charAt(0);
    }
    return '书';
  }

  build() {
    Stack() {
      if (this.coverUrl !== '') {
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.radius)
          .onError(() => {
            this.coverUrl = '';
          })
      } else {
        Column() {
          Text(this.firstChar())
            .fontSize(this.textSize)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#8D6E63')
        .borderRadius(this.radius)
      }
    }
    .width(this.coverWidth)
    .height(this.coverHeight)
    .borderRadius(this.radius)
    .clip(true)
  }
}
