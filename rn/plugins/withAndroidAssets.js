const fs = require('fs');
const path = require('path');
const { AndroidConfig, withAndroidColors, withAndroidColorsNight, withAndroidManifest, withDangerousMod, withFinalizedMod, withStringsXml } = require('expo/config-plugins');

// iOS 에셋 카탈로그가 색과 이미지의 단일 원본
const catalogPath = '../Plyst/Plyst/Assets.xcassets';
// SF Symbols를 대신하는 Android 전용 리소스 원본
const androidResourcePath = 'assets/android';
// 앱 아이콘 글리프가 원형 마스크의 안전 영역 안에 들어오는 전경 여백
const launcherForegroundInset = '12%';
// iOS 앱 타깃의 CFBundleDisplayName과 같은 앱 표시 이름
// expo.name은 rn/ios 생성 프로젝트 이름이라 바꾸지 않음
const appDisplayName = 'Plyst';

function readContents(dir) {
  return JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json'), 'utf8'));
}

function catalogEntries(projectRoot, extension) {
  const catalog = path.resolve(projectRoot, catalogPath);
  return fs
    .readdirSync(catalog)
    .filter((entry) => entry.endsWith(extension))
    .sort()
    .map((entry) => ({
      name: path.basename(entry, extension),
      dir: path.join(catalog, entry),
    }));
}

// 기본 모양과 다크 모양만 Android의 values와 values-night에 대응
function appearanceOf(item) {
  const appearances = item.appearances ?? [];
  if (appearances.length === 0) {
    return 'light';
  }
  const isDark = appearances.length === 1 && appearances[0].appearance === 'luminosity' && appearances[0].value === 'dark';
  return isDark ? 'dark' : null;
}

// Xcode가 쓰는 0xFA 형식과 0.980 형식의 성분만 허용
function channel(value, colorSetName) {
  if (/^0x[0-9a-f]{2}$/i.test(value)) {
    return Number.parseInt(value.slice(2), 16);
  }
  if (/^[01]?\.\d+$/.test(value)) {
    return Math.round(Number.parseFloat(value) * 255);
  }
  throw new Error(`${colorSetName}.colorset의 색 성분 ${value}는 지원하지 않는 형식`);
}

function androidColor(color, colorSetName) {
  if (color['color-space'] !== 'srgb' || !color.components) {
    throw new Error(`${colorSetName}.colorset은 srgb 성분 색이 아님`);
  }
  const { alpha, red, green, blue } = color.components;
  return `#${[alpha, red, green, blue].map((value) => channel(value, colorSetName).toString(16).padStart(2, '0').toUpperCase()).join('')}`;
}

function readColorSets(projectRoot) {
  return catalogEntries(projectRoot, '.colorset').flatMap(({ name, dir }) => {
    const colors = readContents(dir).colors ?? [];
    const values = {};
    for (const item of colors) {
      const appearance = appearanceOf(item);
      if (appearance !== null && item.color) {
        values[appearance] = androidColor(item.color, name);
      }
    }
    // AccentColor처럼 값이 없는 colorset은 건너뜀
    return values.light ? [{ name, ...values }] : [];
  });
}

function withCatalogColors(config) {
  config = withAndroidColors(config, (config) => {
    for (const { name, light } of readColorSets(config.modRequest.projectRoot)) {
      config.modResults = AndroidConfig.Colors.assignColorValue(config.modResults, { name, value: light });
    }
    return config;
  });
  return withAndroidColorsNight(config, (config) => {
    for (const { name, dark } of readColorSets(config.modRequest.projectRoot)) {
      if (dark) {
        config.modResults = AndroidConfig.Colors.assignColorValue(config.modResults, { name, value: dark });
      }
    }
    return config;
  });
}

// expo-image Android가 이미지 이름을 소문자와 밑줄로 바꿔 drawable을 찾는 규칙과 같은 변환
function drawableName(name) {
  const normalized = name.toLowerCase().replace(/-/g, '_');
  if (!/^[a-z][a-z0-9_]*$/.test(normalized)) {
    throw new Error(`${name}.imageset 이름은 Android 리소스 이름이 될 수 없음`);
  }
  return normalized;
}

function copyImageSets(projectRoot, resDir) {
  for (const { name, dir } of catalogEntries(projectRoot, '.imageset')) {
    for (const image of readContents(dir).images ?? []) {
      if (!image.filename) {
        continue;
      }
      if (image.scale) {
        throw new Error(`${name}.imageset의 배율별 이미지는 지원하지 않음`);
      }
      const appearance = appearanceOf(image);
      if (appearance === null) {
        continue;
      }
      const folder = appearance === 'dark' ? 'drawable-night-nodpi' : 'drawable-nodpi';
      const target = path.join(resDir, folder);
      fs.mkdirSync(target, { recursive: true });
      fs.copyFileSync(path.join(dir, image.filename), path.join(target, `${drawableName(name)}${path.extname(image.filename).toLowerCase()}`));
    }
  }
}

function withCatalogImages(config) {
  return withDangerousMod(config, [
    'android',
    async (config) => {
      const { projectRoot, platformProjectRoot } = config.modRequest;
      const resDir = path.join(platformProjectRoot, 'app/src/main/res');
      copyImageSets(projectRoot, resDir);
      fs.cpSync(path.resolve(projectRoot, androidResourcePath), resDir, {
        recursive: true,
      });
      return config;
    },
  ]);
}

// Expo가 만든 전경 레이어는 108dp 전체를 채우므로 inset으로 줄여 글리프를 안전 영역에 맞춤
// 줄어든 전경도 보이는 72dp 영역을 모두 덮어 배경 레이어는 시차 효과에서만 드러남
function withLauncherForegroundInset(config) {
  return withFinalizedMod(config, [
    'android',
    async (config) => {
      const dir = path.join(config.modRequest.platformProjectRoot, 'app/src/main/res/mipmap-anydpi-v26');
      const xml = `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground>
        <inset android:drawable="@mipmap/ic_launcher_foreground" android:inset="${launcherForegroundInset}"/>
    </foreground>
</adaptive-icon>
`;
      for (const file of ['ic_launcher.xml', 'ic_launcher_round.xml']) {
        fs.writeFileSync(path.join(dir, file), xml);
      }
      return config;
    },
  ]);
}

// Expo가 expo.name으로 쓴 app_name을 앱 표시 이름으로 덮어씀
function withAppDisplayName(config) {
  return withStringsXml(config, (config) => {
    config.modResults = AndroidConfig.Strings.setStringItem(
      [
        AndroidConfig.Resources.buildResourceItem({
          name: 'app_name',
          value: appDisplayName,
        }),
      ],
      config.modResults,
    );
    return config;
  });
}

// 위젯 정보가 앱 리소스를 참조하므로 라이브러리 매니페스트가 아니라 앱 매니페스트에 등록
const widgetProvider = 'opfic.plyst.host.app.PlystWidgetProvider';

function withClipboardWidget(config) {
  return withAndroidManifest(config, (config) => {
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(config.modResults);
    const receivers = (application.receiver ?? []).filter((receiver) => receiver.$['android:name'] !== widgetProvider);
    application.receiver = [
      ...receivers,
      {
        $: { 'android:name': widgetProvider, 'android:exported': 'false', 'android:label': '@string/plyst_widget_label' },
        'intent-filter': [{ action: [{ $: { 'android:name': 'android.appwidget.action.APPWIDGET_UPDATE' } }] }],
        'meta-data': [{ $: { 'android:name': 'android.appwidget.provider', 'android:resource': '@xml/plyst_widget_info' } }],
      },
    ];
    return config;
  });
}

module.exports = function withAndroidAssets(config) {
  config = withAppDisplayName(config);
  config = withClipboardWidget(config);
  config = withCatalogColors(config);
  config = withCatalogImages(config);
  return withLauncherForegroundInset(config);
};
