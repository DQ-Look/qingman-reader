/**
 * 阅读主题预设与应用主题（取值对齐原 APK assets/defaultData/readConfig.json 与 themeConfig.json）
 */

export class StorageKeys {
  static readonly NIGHT_MODE: string = 'qm.nightMode';
  static readonly APP_THEME_INDEX: string = 'qm.app.themeIndex';
  static readonly READER_TEXT_SIZE: string = 'qm.reader.textSize';
  static readonly READER_LINE_SPACING: string = 'qm.reader.lineSpacing';
  static readonly READER_PARAGRAPH_SPACING: string = 'qm.reader.paragraphSpacing';
  static readonly READER_THEME_INDEX: string = 'qm.reader.themeIndex';
  static readonly BOOKSHELF_VERSION: string = 'qm.bookshelfVersion';
  static readonly READ_TARGET_INDEX: string = 'qm.readTarget.index';
  static readonly READ_TARGET_VERSION: string = 'qm.readTarget.version';
  static readonly COLOR_PRIMARY: string = 'qm.color.primary';
  static readonly COLOR_ACCENT: string = 'qm.color.accent';
  static readonly COLOR_BACKGROUND: string = 'qm.color.background';
  static readonly COLOR_BOTTOM_BAR: string = 'qm.color.bottomBar';
  static readonly COLOR_TEXT_PRIMARY: string = 'qm.color.textPrimary';
  static readonly COLOR_TEXT_SECONDARY: string = 'qm.color.textSecondary';
  static readonly COLOR_DIVIDER: string = 'qm.color.divider';
  static readonly COMIC_BASE_URL: string = 'qm.api.baseUrl';
  static readonly DEVICE_ID: string = 'qm.api.deviceId';
}

export class ReaderTheme {
  readonly name: string;
  readonly bgDay: string;
  readonly textDay: string;
  readonly bgNight: string;
  readonly textNight: string;

  constructor(name: string, bgDay: string, textDay: string, bgNight: string, textNight: string) {
    this.name = name;
    this.bgDay = bgDay;
    this.textDay = textDay;
    this.bgNight = bgNight;
    this.textNight = textNight;
  }
}

/**
 * 阅读主题预设（对应原版 readConfig.json：微信读书 + 预设1~5）
 */
export const READER_THEMES: ReaderTheme[] = [
  new ReaderTheme('微信读书', '#C0EDC6', '#0B0B0B', '#000000', '#ADADAD'),
  new ReaderTheme('白', '#FFFFFF', '#000000', '#000000', '#FFFFFF'),
  new ReaderTheme('羊皮纸', '#DDC090', '#3E3422', '#3C3F43', '#DCDFE1'),
  new ReaderTheme('护眼', '#C2D8AA', '#596C44', '#3C3F43', '#88C16F'),
  new ReaderTheme('淡紫', '#DBB8E2', '#68516C', '#3C3F43', '#F6AEAE'),
  new ReaderTheme('海蓝', '#ABCEE0', '#3D4C54', '#3C3F43', '#90BFF5')
];

export class AppThemePreset {
  readonly name: string;
  readonly isNight: boolean;
  readonly primary: string;
  readonly accent: string;
  readonly background: string;
  readonly bottomBar: string;

  constructor(name: string, isNight: boolean, primary: string, accent: string,
    background: string, bottomBar: string) {
    this.name = name;
    this.isNight = isNight;
    this.primary = primary;
    this.accent = accent;
    this.background = background;
    this.bottomBar = bottomBar;
  }
}

/**
 * 应用主题预设（对应原版 themeConfig.json）
 */
export const APP_THEMES: AppThemePreset[] = [
  new AppThemePreset('默认', false, '#795548', '#E53935', '#F5F5F5', '#EEEEEE'),
  new AppThemePreset('典雅蓝', false, '#03A9F4', '#AD1457', '#F5F5F5', '#EEEEEE'),
  new AppThemePreset('黑白', true, '#303030', '#E0E0E0', '#424242', '#424242'),
  new AppThemePreset('A屏黑', true, '#000000', '#FFFFFF', '#000000', '#000000')
];

const TEXT_PRIMARY_LIGHT: string = '#212121';
const TEXT_PRIMARY_DARK: string = '#E6E6E6';
const TEXT_SECONDARY_LIGHT: string = '#737373';
const TEXT_SECONDARY_DARK: string = '#A6A6A6';
const DIVIDER_LIGHT: string = '#E5E5E5';
const DIVIDER_DARK: string = '#2A2A2A';
const FALLBACK_DARK_BG: string = '#121212';
const FALLBACK_DARK_BOTTOM: string = '#1E1E1E';

/**
 * 根据主题索引与夜间开关计算当前应用配色并写入 AppStorage
 */
export function applyAppColors(themeIndex: number, nightMode: boolean): void {
  let index: number = themeIndex;
  if (index < 0 || index >= APP_THEMES.length) {
    index = 0;
  }
  const theme: AppThemePreset = APP_THEMES[index];
  let background: string = theme.background;
  let bottomBar: string = theme.bottomBar;
  let primary: string = theme.primary;
  let textPrimary: string = TEXT_PRIMARY_LIGHT;
  let textSecondary: string = TEXT_SECONDARY_LIGHT;
  let divider: string = DIVIDER_LIGHT;
  if (nightMode) {
    if (!theme.isNight) {
      background = FALLBACK_DARK_BG;
      bottomBar = FALLBACK_DARK_BOTTOM;
    }
    textPrimary = TEXT_PRIMARY_DARK;
    textSecondary = TEXT_SECONDARY_DARK;
    divider = DIVIDER_DARK;
  } else if (theme.isNight) {
    // 深色主题在日间模式下也使用深色背景，但文字保持高对比
    textPrimary = TEXT_PRIMARY_DARK;
    textSecondary = TEXT_SECONDARY_DARK;
    divider = DIVIDER_DARK;
  }
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_PRIMARY, primary);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_ACCENT, theme.accent);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_BACKGROUND, background);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_BOTTOM_BAR, bottomBar);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_TEXT_PRIMARY, textPrimary);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_TEXT_SECONDARY, textSecondary);
  AppStorage.setOrCreate<string>(StorageKeys.COLOR_DIVIDER, divider);
}
