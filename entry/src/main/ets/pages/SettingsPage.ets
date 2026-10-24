/**
 * 设置页：应用主题 / 夜间模式 / 阅读默认值 / 书源管理入口 / 规则引擎自测 / 关于
 */
import { StorageKeys, APP_THEMES, READER_THEMES, AppThemePreset, ReaderTheme, applyAppColors } from '../model/ReadConfigModels';
import { runRuleEngineTests, RuleTestResult } from '../analyze/RuleEngineTest';
import { PageHeader } from '../common/PageHeader';

const APP_VERSION: string = '1.0.0';

@Component
export struct SettingsPage {
  pathStack: NavPathStack = new NavPathStack();
  @State testing: boolean = false;
  @StorageProp(StorageKeys.APP_THEME_INDEX) @Watch('onThemeChanged') appThemeIndex: number = 0;
  @StorageProp(StorageKeys.NIGHT_MODE) @Watch('onThemeChanged') nightMode: boolean = false;
  @StorageProp(StorageKeys.READER_TEXT_SIZE) readerTextSize: number = 19;
  @StorageProp(StorageKeys.READER_LINE_SPACING) readerLineSpacing: number = 8;
  @StorageProp(StorageKeys.READER_PARAGRAPH_SPACING) readerParagraphSpacing: number = 12;
  @StorageProp(StorageKeys.READER_THEME_INDEX) readerThemeIndex: number = 0;
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  onThemeChanged(): void {
    applyAppColors(this.appThemeIndex, this.nightMode);
  }

  setNightMode(on: boolean): void {
    AppStorage.setOrCreate<boolean>(StorageKeys.NIGHT_MODE, on);
  }

  setAppTheme(index: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.APP_THEME_INDEX, index);
  }

  setReaderTheme(index: number): void {
    AppStorage.setOrCreate<number>(StorageKeys.READER_THEME_INDEX, index);
  }

  runTests(): void {
    this.testing = true;
    const results: RuleTestResult[] = runRuleEngineTests();
    this.testing = false;
    let passCount: number = 0;
    const failures: string[] = [];
    for (let i = 0; i < results.length; i++) {
      if (results[i].passed) {
        passCount++;
      } else {
        failures.push(results[i].name + '：' + results[i].message);
      }
    }
    let message: string = '共 ' + results.length + ' 项，通过 ' + passCount + ' 项';
    if (failures.length > 0) {
      message += '\n未通过：\n' + failures.join('\n');
    }
    this.getUIContext().showAlertDialog({
      title: '规则引擎自测',
      message: message,
      confirm: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.textSecondary)
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 8 })
  }

  build() {
    Column() {
      PageHeader({
        title: '设置',
        pathStack: this.pathStack,
        textColor: this.textPrimary
      })

      Scroll() {
        Column() {
          this.sectionTitle('外观')
          Row() {
            Text('夜间模式')
              .fontSize(15)
              .fontColor(this.textPrimary)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.nightMode })
              .selectedColor(this.colorPrimary)
              .onChange((isOn: boolean) => {
                this.setNightMode(isOn);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          Row({ space: 14 }) {
            ForEach(APP_THEMES, (theme: AppThemePreset, index: number) => {
              Column({ space: 4 }) {
                Stack() {
                  if (index === this.appThemeIndex) {
                    Circle()
                      .width(40)
                      .height(40)
                      .fill(Color.Transparent)
                      .stroke(this.colorPrimary)
                      .strokeWidth(2)
                  }
                  Circle()
                    .width(32)
                    .height(32)
                    .fill(theme.primary)
                }
                .width(40)
                .height(40)
                Text(theme.name)
                  .fontSize(10)
                  .fontColor(index === this.appThemeIndex ? this.colorPrimary : this.textSecondary)
              }
              .onClick(() => {
                this.setAppTheme(index);
              })
            }, (theme: AppThemePreset) => theme.name)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          .alignItems(VerticalAlign.Center)

          this.sectionTitle('阅读默认值')

          Row({ space: 12 }) {
            Text('字号')
              .fontSize(14)
              .fontColor(this.textSecondary)
              .width(40)
            Slider({ value: this.readerTextSize, min: 12, max: 32, step: 1 })
              .layoutWeight(1)
              .selectedColor(this.colorPrimary)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End) {
                  AppStorage.setOrCreate<number>(StorageKeys.READER_TEXT_SIZE, Math.round(value));
                }
              })
            Text(this.readerTextSize.toString())
              .fontSize(14)
              .width(28)
              .fontColor(this.textPrimary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          Row({ space: 12 }) {
            Text('行距')
              .fontSize(14)
              .fontColor(this.textSecondary)
              .width(40)
            Slider({ value: this.readerLineSpacing, min: 0, max: 24, step: 1 })
              .layoutWeight(1)
              .selectedColor(this.colorPrimary)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End) {
                  AppStorage.setOrCreate<number>(StorageKeys.READER_LINE_SPACING, Math.round(value));
                }
              })
            Text(this.readerLineSpacing.toString())
              .fontSize(14)
              .width(28)
              .fontColor(this.textPrimary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          Row({ space: 12 }) {
            Text('段距')
              .fontSize(14)
              .fontColor(this.textSecondary)
              .width(40)
            Slider({ value: this.readerParagraphSpacing, min: 0, max: 32, step: 1 })
              .layoutWeight(1)
              .selectedColor(this.colorPrimary)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End) {
                  AppStorage.setOrCreate<number>(StorageKeys.READER_PARAGRAPH_SPACING, Math.round(value));
                }
              })
            Text(this.readerParagraphSpacing.toString())
              .fontSize(14)
              .width(28)
              .fontColor(this.textPrimary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })

          Row({ space: 14 }) {
            ForEach(READER_THEMES, (theme: ReaderTheme, index: number) => {
              Stack() {
                if (index === this.readerThemeIndex) {
                  Circle()
                    .width(40)
                    .height(40)
                    .fill(Color.Transparent)
                    .stroke(this.colorPrimary)
                    .strokeWidth(2)
                }
                Circle()
                  .width(32)
                  .height(32)
                  .fill(theme.bgDay)
              }
              .width(40)
              .height(40)
              .onClick(() => {
                this.setReaderTheme(index);
              })
            }, (theme: ReaderTheme) => theme.name)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 16 })
          .alignItems(VerticalAlign.Center)

          this.sectionTitle('数据')

          Row() {
            Text('书源管理')
              .fontSize(15)
              .fontColor(this.textPrimary)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([this.textSecondary])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(() => {
            this.pathStack.pushPathByName('sourceManage', '');
          })

          Divider()
            .color(this.dividerColor)
            .margin({ left: 16, right: 16 })

          Row() {
            Text('规则引擎自测')
              .fontSize(15)
              .fontColor(this.textPrimary)
              .layoutWeight(1)
            if (this.testing) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.colorPrimary)
            } else {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([this.textSecondary])
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(() => {
            this.runTests();
          })

          Divider()
            .color(this.dividerColor)
            .margin({ left: 16, right: 16 })

          this.sectionTitle('关于')
          Row() {
            Text('青漫 v' + APP_VERSION)
              .fontSize(15)
              .fontColor(this.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14 })
          Text('基于 Legado 规则引擎（非 JS 子集）的 HarmonyOS 阅读器。书源规则由用户自行导入，应用不内置任何书源。')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .lineHeight(19)
            .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

@Component
struct SettingsDestinationPage {
  navPathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      SettingsPage({ pathStack: this.navPathStack })
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
    })
  }
}

@Builder
export function SettingsPageBuilder() {
  SettingsDestinationPage()
}
