/**
 * 书源编辑页：常用字段表单 + 完整 JSON 编辑（规则载体）
 */
import { BookSource, bookSourceFromJson, bookSourceToJson } from '../model/BookSourceModels';
import { BookSourceRepo } from '../service/BookSourceRepo';
import { SourceEditParam } from '../model/BookModels';
import { StorageKeys } from '../model/ReadConfigModels';
import { PageHeader } from '../common/PageHeader';

@Component
struct SourceEditPage {
  isNew: boolean = true;
  sourceUrl: string = '';
  @State name: string = '';
  @State url: string = '';
  @State group: string = '';
  @State searchUrl: string = '';
  @State exploreUrl: string = '';
  @State isEnabled: boolean = true;
  @State jsonText: string = '';
  @State loading: boolean = true;
  @State failedMsg: string = '';
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  init(): void {
    this.loading = true;
    this.failedMsg = '';
    if (this.isNew) {
      const blank: BookSource = new BookSource();
      this.name = '';
      this.url = '';
      this.group = '';
      this.searchUrl = '';
      this.exploreUrl = '';
      this.isEnabled = true;
      this.jsonText = bookSourceToJson(blank);
      this.loading = false;
      return;
    }
    BookSourceRepo.getInstance().getByUrl(this.sourceUrl).then((source: BookSource | null) => {
      if (source === null) {
        this.failedMsg = '书源不存在';
        this.loading = false;
        return;
      }
      this.name = source.bookSourceName;
      this.url = source.bookSourceUrl;
      this.group = source.bookSourceGroup;
      this.searchUrl = source.searchUrl;
      this.exploreUrl = source.exploreUrl;
      this.isEnabled = source.enabled;
      this.jsonText = bookSourceToJson(source);
      this.loading = false;
    }).catch(() => {
      this.failedMsg = '加载失败';
      this.loading = false;
    });
  }

  save(): void {
    let base: BookSource;
    try {
      base = bookSourceFromJson(this.jsonText);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: 'JSON 格式错误，请检查 JSON 内容' });
      return;
    }
    if (this.name.trim() !== '') {
      base.bookSourceName = this.name.trim();
    }
    if (this.url.trim() !== '') {
      base.bookSourceUrl = this.url.trim();
    }
    if (base.bookSourceUrl === '') {
      this.getUIContext().getPromptAction().showToast({ message: '书源地址不能为空' });
      return;
    }
    if (base.bookSourceName === '') {
      base.bookSourceName = base.bookSourceUrl;
    }
    base.bookSourceGroup = this.group.trim();
    base.searchUrl = this.searchUrl.trim();
    base.exploreUrl = this.exploreUrl.trim();
    base.enabled = this.isEnabled;
    BookSourceRepo.getInstance().saveSource(base).then(() => {
      AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
        (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.navPathStack.pop();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
    });
  }

  @Builder
  fieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.textSecondary)
      .margin({ top: 14, bottom: 6 })
      .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: this.isNew ? '新建书源' : '编辑书源',
          pathStack: this.navPathStack,
          textColor: this.textPrimary
        })
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.colorPrimary)
            Text('正在加载…')
              .fontSize(14)
              .fontColor(this.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.failedMsg !== '') {
            Column() {
              Text(this.failedMsg)
                .fontSize(14)
                .fontColor(this.textSecondary)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                this.fieldLabel('名称')
                TextInput({ placeholder: '书源名称', text: this.name })
                  .fontSize(14)
                  .height(42)
                  .onChange((value: string) => {
                    this.name = value;
                  })

                this.fieldLabel('地址')
                TextInput({ placeholder: 'https://example.com', text: this.url })
                  .fontSize(14)
                  .height(42)
                  .enabled(this.isNew)
                  .onChange((value: string) => {
                    this.url = value;
                  })

                this.fieldLabel('分组')
                TextInput({ placeholder: '多个分组用逗号分隔', text: this.group })
                  .fontSize(14)
                  .height(42)
                  .onChange((value: string) => {
                    this.group = value;
                  })

                this.fieldLabel('搜索地址')
                TextInput({ placeholder: '搜索 URL，支持 searchKey / searchPage 占位符', text: this.searchUrl })
                  .fontSize(14)
                  .height(42)
                  .onChange((value: string) => {
                    this.searchUrl = value;
                  })

                this.fieldLabel('发现地址')
                TextArea({ placeholder: '发现 URL，支持 {{page}} 占位符', text: this.exploreUrl })
                  .fontSize(14)
                  .constraintSize({ minHeight: 64 })
                  .onChange((value: string) => {
                    this.exploreUrl = value;
                  })

                Row() {
                  Text('启用')
                    .fontSize(14)
                    .fontColor(this.textPrimary)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
                    .onChange((isOn: boolean) => {
                      this.isEnabled = isOn;
                    })
                }
                .width('100%')
                .margin({ top: 18 })

                this.fieldLabel('书源 JSON（规则在此编辑）')
                TextArea({ text: this.jsonText })
                  .fontSize(11)
                  .constraintSize({ minHeight: 320 })
                  .fontColor(this.textSecondary)
                  .onChange((value: string) => {
                    this.jsonText = value;
                  })

                Button('保存')
                  .width('100%')
                  .height(44)
                  .fontSize(16)
                  .backgroundColor(this.colorPrimary)
                  .fontColor(Color.White)
                  .margin({ top: 20, bottom: 32 })
                  .onClick(() => {
                    this.save();
                  })
              }
              .padding({ left: 16, right: 16 })
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
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
      const p: SourceEditParam = ctx.pathInfo.param as SourceEditParam;
      if (p instanceof SourceEditParam) {
        this.isNew = p.isNew;
        this.sourceUrl = p.bookSourceUrl;
        this.init();
      }
    })
  }
}

@Builder
export function SourceEditPageBuilder() {
  SourceEditPage()
}
