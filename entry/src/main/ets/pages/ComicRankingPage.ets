/**
 * 排行榜页：还原原版首页排行榜块 HomeComicRankingFragment 的四榜
 * 新作榜(updateTime)/人气榜(playNum)/收藏榜(collectNum)/上升榜(searchNum)
 * 单列带名次列表 + 上拉加载更多
 */
import { StorageKeys } from '../model/ReadConfigModels';
import { ComicItem, ComicParam, ComicSearchResult } from '../model/ComicApiModels';
import { ComicApi } from '../service/ComicApi';
import { PageHeader } from '../common/PageHeader';

const RANK_PAGE_SIZE: number = 50;

class RankTab {
  name: string = '';
  sortField: string = '';

  constructor(name: string, sortField: string) {
    this.name = name;
    this.sortField = sortField;
  }
}

@Component
struct ComicRankingPage {
  private tabs: RankTab[] = [
    new RankTab('新作榜', 'updateTime'),
    new RankTab('人气榜', 'playNum'),
    new RankTab('收藏榜', 'collectNum'),
    new RankTab('上升榜', 'searchNum')
  ];
  @State activeTab: number = 0;
  @State comics: ComicItem[] = [];
  @State total: number = 0;
  @State page: number = 0;
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State failedMsg: string = '';
  @State requested: boolean = false;
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.SAFE_AREA_BOTTOM_VP) navBarVp: number = 24;
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';

  selectTab(index: number): void {
    if (index === this.activeTab && this.requested) {
      return;
    }
    this.activeTab = index;
    this.loadFirst();
  }

  loadFirst(): void {
    this.requested = true;
    this.loading = true;
    this.failedMsg = '';
    this.loadingMore = false;
    const sortField: string = this.tabs[this.activeTab].sortField;
    ComicApi.getInstance().browseComics(1, RANK_PAGE_SIZE, sortField, -1, '').then((res: ComicSearchResult) => {
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
    const sortField: string = this.tabs[this.activeTab].sortField;
    ComicApi.getInstance().browseComics(this.page + 1, RANK_PAGE_SIZE, sortField, -1, '').then((res: ComicSearchResult) => {
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
  rankRow(index: number, comic: ComicItem) {
    Row({ space: 10 }) {
      Text(String(index + 1))
        .fontSize(index < 3 ? 18 : 15)
        .fontWeight(FontWeight.Bold)
        .fontColor(index < 3 ? '#FF7043' : '#BBBBBB')
        .width(28)
        .textAlign(TextAlign.Center)
      if (comic.picUrl !== '') {
        Image(comic.picUrl)
          .width(56)
          .height(74)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .backgroundColor('#EFEEF4')
      } else {
        Column() {
          Text(comic.comicName.length > 0 ? comic.comicName.substring(0, 1) : '漫')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(56)
        .height(74)
        .backgroundColor('#8D8D93')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text(comic.comicName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
        Text(comic.author === '' ? '未知作者' : comic.author)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
        Text('更新至 ' + comic.episodeNum + ' 话')
          .fontSize(12)
          .fontColor('#6C5CE7')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '排行榜',
          pathStack: this.navPathStack
        })
        Row({ space: 8 }) {
          ForEach(this.tabs, (tab: RankTab, index: number) => {
            Text(tab.name)
              .fontSize(14)
              .fontWeight(index === this.activeTab ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(index === this.activeTab ? Color.White : '#666666')
              .backgroundColor(index === this.activeTab ? '#6C5CE7' : '#F4F1FF')
              .borderRadius(16)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .maxLines(1)
              .onClick(() => {
                this.selectTab(index);
              })
          }, (tab: RankTab): string => tab.name)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 4, bottom: 8 })

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
            Text('暂无榜单内容')
              .fontSize(14)
              .fontColor('#999999')
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.comics, (comic: ComicItem, index: number) => {
              ListItem() {
                this.rankRow(index, comic)
              }
            }, (comic: ComicItem): string => comic.comicId + '_' + comic.comicName)
            if (this.loadingMore) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#6C5CE7')
                  Text('正在加载...')
                    .fontSize(12)
                    .fontColor('#999999')
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 12, bottom: 12 })
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 16 + this.navBarVp })
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
      this.loadFirst();
    })
  }
}

@Builder
export function ComicRankingPageBuilder() {
  ComicRankingPage()
}
