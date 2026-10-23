/**
 * 发现页：展示发现启用的书源列表，点击进入书源发现分类
 */
import { BookSource } from '../model/BookSourceModels';
import { BookSourceRepo } from '../service/BookSourceRepo';
import { ExploreDetailParam } from '../model/BookModels';
import { StorageKeys } from '../model/ReadConfigModels';

@Component
export struct ExplorePage {
  pathStack: NavPathStack = new NavPathStack();
  @State sources: BookSource[] = [];
  @State loading: boolean = true;
  @StorageProp(StorageKeys.BOOKSHELF_VERSION) @Watch('onVersionChange') bookshelfVersion: number = 0;
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  aboutToAppear(): void {
    this.refresh();
  }

  onVersionChange(): void {
    this.refresh();
  }

  refresh(): void {
    this.loading = true;
    BookSourceRepo.getInstance().getExploreEnabled().then((sources: BookSource[]) => {
      this.sources = sources;
      this.loading = false;
    }).catch(() => {
      this.loading = false;
    });
  }

  openSource(source: BookSource): void {
    const p: ExploreDetailParam = new ExploreDetailParam();
    p.sourceUrl = source.bookSourceUrl;
    this.pathStack.pushPathByName('exploreDetail', p);
  }

  build() {
    Column() {
      Row() {
        Text('发现')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.colorPrimary)
          Text('正在加载书源…')
            .fontSize(14)
            .fontColor(this.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.sources.length === 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.compass'))
              .fontSize(56)
              .fontColor([this.textSecondary])
            Text('暂无启用发现的书源')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.textPrimary)
            Text('导入书源并启用「发现」后即可在这里逛书')
              .fontSize(13)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.sources, (source: BookSource) => {
              ListItem() {
                Row() {
                  Column({ space: 4 }) {
                    Text(source.bookSourceName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (source.bookSourceGroup !== '') {
                      Text(source.bookSourceGroup.split(/[;；,，]/).filter((g: string) => g.trim() !== '').join(' · '))
                        .fontSize(12)
                        .fontColor(this.colorPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([this.textSecondary])
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.openSource(source);
                })
              }
            }, (source: BookSource) => source.bookSourceUrl)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({
            strokeWidth: 0.5,
            color: this.dividerColor,
            startMargin: 16,
            endMargin: 16
          })
          .scrollBar(BarState.Off)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}
