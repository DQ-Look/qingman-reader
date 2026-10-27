/**
 * 首页分区「更多」页：还原原版 ComicMoreActivity
 * 按分区标题映射 sortField（98%萌新→updateTime、咪虎推荐→todayPlayNum、
 * 精品热漫→playNum、默认→collectNum），三列封面网格 + 上拉加载更多
 */
import { StorageKeys } from '../model/ReadConfigModels';
import { ComicItem, ComicParam, ComicMoreParam, ComicSearchResult } from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { PageHeader } from '../common/PageHeader';

const MORE_PAGE_SIZE: number = 45;

@Component
struct ComicMorePage {
  @State title: string = '';
  @State sortField: string = 'collectNum';
  @State comics: ComicItem[] = [];
  @State total: number = 0;
  @State page: number = 0;
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State failedMsg: string = '';
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.SAFE_AREA_BOTTOM_VP) navBarVp: number = 24;
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';

  loadFirst(): void {
    this.loading = true;
    this.failedMsg = '';
    ComicApi.getInstance().browseComics(1, MORE_PAGE_SIZE, this.sortField, -1, '').then((res: ComicSearchResult) => {
      this.comics = res.comics;
      this.total = res.total;
      this.page = 1;
      this.loading = false;
    }).catch((e: Error) => {
      this.failedMsg = e.message;
      this.loading = false;
    });
  }

  loadMore(): void {
    if (this.loading || this.loadingMore || this.failedMsg !== '' || this.comics.length === 0) {
      return;
    }
    if (this.total > 0 && this.comics.length >= this.total) {
      return;
    }
    this.loadingMore = true;
    ComicApi.getInstance().browseComics(this.page + 1, MORE_PAGE_SIZE, this.sortField, -1, '').then((res: ComicSearchResult) => {
      const seen: Set<string> = new Set<string>();
      const merged: ComicItem[] = this.comics.slice();
      for (let i = 0; i < merged.length; i++) {
        seen.add(merged[i].comicId);
      }
      for (let i = 0; i < res.comics.length; i++) {
        if (!seen.has(res.comics[i].comicId)) {
          merged.push(res.comics[i]);
        }
      }
      this.comics = merged;
      this.total = res.total;
      this.page += 1;
      this.loadingMore = false;
    }).catch(() => {
      this.loadingMore = false;
    });
  }

  openComicDetail(comic: ComicItem): void {
    const p: ComicParam = new ComicParam();
    p.comicId = comic.comicId;
    p.comicName = comic.comicName;
    p.picUrl = comic.picUrl;
    this.navPathStack.pushPathByName('comicDetail', p);
  }

  @Builder
  comicCard(comic: ComicItem) {
    Column({ space: 6 }) {
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width('100%')
          .aspectRatio(0.75)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(comic.comicName.length > 0 ? comic.comicName.substring(0, 1) : '漫')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .aspectRatio(0.75)
        .backgroundColor('#8D8D93')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Text(comic.comicName)
        .fontSize(13)
        .fontColor('#333333')
        .maxLines(2)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.title,
          pathStack: this.navPathStack
        })
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color('#6C5CE7')
            Text('正在加载...')
              .fontSize(13)
              .fontColor('#999999')
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.failedMsg !== '') {
          Column({ space: 12 }) {
            Text('加载失败')
              .fontSize(14)
              .fontColor('#333333')
            Text(this.failedMsg)
              .fontSize(12)
              .fontColor('#999999')
              .maxLines(2)
            Text('重试')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .padding({ left: 22, right: 22, top: 8, bottom: 8 })
              .backgroundColor('#6C5CE7')
              .borderRadius(17)
              .margin({ top: 6 })
              .onClick(() => {
                this.loadFirst();
              })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.comics.length === 0) {
          Column({ space: 10 }) {
            Text('暂无内容')
              .fontSize(14)
              .fontColor('#999999')
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.comics, (comic: ComicItem) => {
              GridItem() {
                this.comicCard(comic)
              }
            }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(12)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 16 + this.navBarVp })
          .scrollBar(BarState.Off)
          .onReachEnd(() => {
            this.loadMore();
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor(this.bgColor)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      const p: ComicMoreParam = ctx.pathInfo.param as ComicMoreParam;
      if (p instanceof ComicMoreParam) {
        this.title = p.title;
        this.sortField = p.sortField;
        this.loadFirst();
      }
    })
  }
}

@Builder
export function ComicMorePageBuilder() {
  ComicMorePage()
}
