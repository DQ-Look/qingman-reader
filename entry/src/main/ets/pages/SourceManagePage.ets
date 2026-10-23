/**
 * 书源管理页：书源列表、启停、编辑入口、导入（本地/网络/剪贴板）、导出
 */
import { BookSource } from '../model/BookSourceModels';
import { BookSourceRepo, ImportResult } from '../service/BookSourceRepo';
import { SourceEditParam } from '../model/BookModels';
import { StorageKeys } from '../model/ReadConfigModels';
import { httpText, HttpRequestSpec, methodFromString, HttpTextResponse } from '../service/HttpClient';
import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit';

function readUriText(uri: string): string {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat: fileIo.Stat = fileIo.statSync(file.fd);
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buffer));
  } finally {
    fileIo.closeSync(file);
  }
}

@Component
struct SourceManagePage {
  @State sources: BookSource[] = [];
  @State loading: boolean = true;
  @State urlInputVisible: boolean = false;
  @State urlInput: string = '';
  @State importing: boolean = false;
  navPathStack: NavPathStack = new NavPathStack();
  @StorageProp(StorageKeys.COLOR_BACKGROUND) bgColor: string = '#F5F5F5';
  @StorageProp(StorageKeys.COLOR_PRIMARY) colorPrimary: string = '#795548';
  @StorageProp(StorageKeys.COLOR_ACCENT) colorAccent: string = '#E53935';
  @StorageProp(StorageKeys.COLOR_TEXT_PRIMARY) textPrimary: string = '#212121';
  @StorageProp(StorageKeys.COLOR_TEXT_SECONDARY) textSecondary: string = '#737373';
  @StorageProp(StorageKeys.COLOR_DIVIDER) dividerColor: string = '#E5E5E5';

  refresh(): void {
    this.loading = true;
    BookSourceRepo.getInstance().getAll().then((sources: BookSource[]) => {
      this.sources = sources;
      this.loading = false;
    }).catch(() => {
      this.loading = false;
    });
  }

  onReadyInit(): void {
    this.refresh();
  }

  importAndReport(jsonStr: string): void {
    if (jsonStr.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '内容为空' });
      return;
    }
    BookSourceRepo.getInstance().importJson(jsonStr).then((r: ImportResult) => {
      this.getUIContext().getPromptAction().showToast({
        message: '新增 ' + r.imported + ' 个，更新 ' + r.updated + ' 个'
      });
      this.bumpDataVersion();
      this.refresh();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '书源 JSON 解析失败' });
    });
  }

  bumpDataVersion(): void {
    AppStorage.setOrCreate<number>(StorageKeys.BOOKSHELF_VERSION,
      (AppStorage.get<number>(StorageKeys.BOOKSHELF_VERSION) ?? 0) + 1);
  }

  importFromClipboard(): void {
    const board = pasteboard.getSystemPasteboard();
    board.getData().then((data: pasteboard.PasteData) => {
      const text: string = data.getPrimaryText();
      this.importAndReport(text);
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '读取剪贴板失败' });
    });
  }

  importFromLocalFile(): void {
    const options = new picker.DocumentSelectOptions();
    const documentPicker = new picker.DocumentViewPicker();
    documentPicker.select(options).then((uris: Array<string>) => {
      if (uris.length === 0) {
        return;
      }
      const text: string = readUriText(uris[0]);
      this.importAndReport(text);
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '读取文件失败' });
    });
  }

  importFromUrl(): void {
    const url: string = this.urlInput.trim();
    if (url === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入书源链接' });
      return;
    }
    this.importing = true;
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = methodFromString('GET');
    httpText(url, spec).then((resp: HttpTextResponse) => {
      this.importing = false;
      this.urlInputVisible = false;
      this.importAndReport(resp.body);
    }).catch((e: Error) => {
      this.importing = false;
      this.getUIContext().getPromptAction().showToast({
        message: '下载失败：' + (e instanceof Error ? e.message : String(e))
      });
    });
  }

  exportAll(): void {
    BookSourceRepo.getInstance().exportAll().then((json: string) => {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = ['bookSources.json'];
      const documentPicker = new picker.DocumentViewPicker();
      return documentPicker.save(saveOptions).then((uris: Array<string>) => {
        if (uris.length === 0) {
          return;
        }
        const file = fileIo.openSync(uris[0],
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, json);
        } finally {
          fileIo.closeSync(file);
        }
        this.getUIContext().getPromptAction().showToast({ message: '已导出 ' + this.sources.length + ' 个书源' });
      });
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
    });
  }

  toggleSource(source: BookSource, enabled: boolean): void {
    const urls: string[] = [source.bookSourceUrl];
    BookSourceRepo.getInstance().setEnabled(urls, enabled).then(() => {
      this.bumpDataVersion();
      this.refresh();
    });
  }

  confirmDelete(source: BookSource): void {
    this.getUIContext().showAlertDialog({
      title: '删除书源',
      message: '确定删除书源「' + source.bookSourceName + '」？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.colorAccent,
        action: () => {
          const urls: string[] = [source.bookSourceUrl];
          BookSourceRepo.getInstance().deleteSources(urls).then(() => {
            this.getUIContext().getPromptAction().showToast({ message: '已删除' });
            this.bumpDataVersion();
            this.refresh();
          });
        }
      }
    });
  }

  openEditor(source: BookSource | null): void {
    const p: SourceEditParam = new SourceEditParam();
    if (source !== null) {
      p.bookSourceUrl = source.bookSourceUrl;
      p.isNew = false;
    }
    this.navPathStack.pushPathByName('sourceEdit', p);
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Button('导入')
            .fontSize(13)
            .height(32)
            .backgroundColor(this.colorPrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.chooseImportWay();
            })
          Button('导出')
            .fontSize(13)
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor(this.colorPrimary)
            .border({ width: 1, color: this.colorPrimary })
            .onClick(() => {
              this.exportAll();
            })
          Blank()
          Button('新建')
            .fontSize(13)
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor(this.colorPrimary)
            .border({ width: 1, color: this.colorPrimary })
            .onClick(() => {
              this.openEditor(null);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

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
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(56)
                .fontColor([this.textSecondary])
              Text('还没有书源')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.textPrimary)
              Text('书源是青漫抓取书籍的规则，可从网络链接、剪贴板或本地文件导入')
                .fontSize(13)
                .fontColor(this.textSecondary)
                .textAlign(TextAlign.Center)
                .padding({ left: 40, right: 40 })
              Button('新建书源')
                .backgroundColor(this.colorPrimary)
                .fontColor(Color.White)
                .margin({ top: 8 })
                .onClick(() => {
                  this.openEditor(null);
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.sources, (source: BookSource) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text(source.bookSourceName)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(source.bookSourceUrl)
                        .fontSize(11)
                        .fontColor(this.textSecondary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (source.bookSourceGroup !== '') {
                        Text(source.bookSourceGroup)
                          .fontSize(11)
                          .fontColor(this.colorPrimary)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                      .onChange((isOn: boolean) => {
                        this.toggleSource(source, isOn);
                      })
                    SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                      .fontSize(20)
                      .fontColor([this.textSecondary])
                      .onClick(() => {
                        this.showSourceActions(source);
                      })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => {
                    this.openEditor(source);
                  })
                }
              }, (source: BookSource) => source.bookSourceUrl + '#' + source.enabled)
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
      .bindSheet($$this.urlInputVisible, this.urlImportPanel(), {
        height: 240,
        dragBar: true,
        showClose: true
      })
    }
    .title('书源管理')
    .backgroundColor(this.bgColor)
    .onShown(() => {
      this.refresh();
    })
    .onReady((ctx: NavDestinationContext) => {
      this.navPathStack = ctx.pathStack;
      this.onReadyInit();
    })
  }

  chooseImportWay(): void {
    this.getUIContext().showActionSheet({
      title: '导入书源',
      message: '选择导入方式',
      sheets: [
        {
          title: '从网络链接导入',
          action: () => {
            this.urlInput = '';
            this.urlInputVisible = true;
          }
        },
        {
          title: '从剪贴板导入',
          action: () => {
            this.importFromClipboard();
          }
        },
        {
          title: '从本地文件导入',
          action: () => {
            this.importFromLocalFile();
          }
        }
      ]
    });
  }

  showSourceActions(source: BookSource): void {
    this.getUIContext().showActionSheet({
      title: source.bookSourceName,
      message: source.bookSourceUrl,
      sheets: [
        {
          title: '编辑',
          action: () => {
            this.openEditor(source);
          }
        },
        {
          title: '删除',
          action: () => {
            this.confirmDelete(source);
          }
        }
      ]
    });
  }

  @Builder
  urlImportPanel() {
    Column({ space: 16 }) {
      Text('从网络导入书源')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textPrimary)
        .width('100%')
      TextInput({ placeholder: '输入书源 JSON 链接', text: this.urlInput })
        .fontSize(14)
        .height(44)
        .onChange((value: string) => {
          this.urlInput = value;
        })
      Button(this.importing ? '正在下载…' : '导入')
        .width('100%')
        .height(42)
        .backgroundColor(this.colorPrimary)
        .fontColor(Color.White)
        .enabled(!this.importing)
        .onClick(() => {
          this.importFromUrl();
        })
    }
    .padding(24)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function SourceManagePageBuilder() {
  SourceManagePage()
}
