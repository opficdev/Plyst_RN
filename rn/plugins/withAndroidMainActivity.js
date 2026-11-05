const fs = require('fs');
const path = require('path');
const { AndroidConfig, withAndroidManifest, withAndroidStyles, withDangerousMod, withMainActivity } = require('expo/config-plugins');

// rn/index.ts가 등록한 루트이며 iOS SceneComposition이 여는 moduleName과 같은 이름
const mainComponentName = 'AppRoot';
const pattern = /(override fun getMainComponentName\(\): String = )"[^"]*"/;

// Expo 템플릿 MainActivity가 여는 루트를 AppRoot로 바꿈
function withMainComponentName(config) {
  return withMainActivity(config, (config) => {
    const { contents } = config.modResults;
    if (!pattern.test(contents)) {
      throw new Error('MainActivity에서 getMainComponentName을 찾지 못함');
    }
    config.modResults.contents = contents.replace(pattern, `$1"${mainComponentName}"`);
    return config;
  });
}

// Android는 이미 그린 PlatformColor를 다시 해석하지 않음
// 화면 모양이 바뀌면 Activity를 다시 만들어 에셋 색을 새 모양으로 그림
function withUIModeRecreation(config) {
  return withAndroidManifest(config, (config) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(config.modResults);
    const changes = activity.$['android:configChanges'];
    if (changes) {
      activity.$['android:configChanges'] = changes
        .split('|')
        .filter((change) => change !== 'uiMode')
        .join('|');
    }
    return config;
  });
}

// iOS Info.plist의 URL 스킴과 같이 위젯과 브라우저가 plystrn://clipboard/save로 앱을 엶
const linkFilter = {
  action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }],
  category: [{ $: { 'android:name': 'android.intent.category.DEFAULT' } }, { $: { 'android:name': 'android.intent.category.BROWSABLE' } }],
  data: [{ $: { 'android:scheme': 'plystrn', 'android:host': 'clipboard', 'android:path': '/save' } }],
};

function withClipboardLinkFilter(config) {
  return withAndroidManifest(config, (config) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(config.modResults);
    const filters = (activity['intent-filter'] ?? []).filter((filter) => !filter.data?.some((data) => data.$['android:scheme'] === 'plystrn'));
    activity['intent-filter'] = [...filters, linkFilter];
    return config;
  });
}

// Expo 템플릿이 super.onCreate에 null을 넘겨 리스너는 복원 여부를 알 수 없음
// 복원된 Activity가 저장 링크를 다시 처리하지 않도록 여기서 data를 비움
const restoredLinkClear = 'if (savedInstanceState != null) intent = android.content.Intent(intent).setData(null)';
const onCreatePattern = /super\.onCreate\(null\)/;

function withRestoredLinkCleared(config) {
  return withMainActivity(config, (config) => {
    const { contents } = config.modResults;
    if (contents.includes(restoredLinkClear)) {
      return config;
    }
    if (!onCreatePattern.test(contents)) {
      throw new Error('MainActivity에서 super.onCreate(null)을 찾지 못함');
    }
    config.modResults.contents = contents.replace(onCreatePattern, `${restoredLinkClear}\n    super.onCreate(null)`);
    return config;
  });
}

// 다시 만든 Activity의 상태 표시줄과 내비게이션 바 아이콘 색을 테마가 화면 모양에 맞춰 정함
const lightSystemBars = 'plyst_light_system_bars';

function withSystemBarAppearance(config) {
  config = withAndroidStyles(config, (config) => {
    // windowLightNavigationBar는 API 27부터 있어 그보다 낮은 기기는 무시
    for (const [name, targetApi] of [
      ['android:windowLightStatusBar', undefined],
      ['android:windowLightNavigationBar', '27'],
    ]) {
      config.modResults = AndroidConfig.Styles.assignStylesValue(config.modResults, {
        add: true,
        parent: { name: 'AppTheme' },
        name,
        targetApi,
        value: `@bool/${lightSystemBars}`,
      });
    }
    return config;
  });
  return withDangerousMod(config, [
    'android',
    async (config) => {
      const res = path.join(config.modRequest.platformProjectRoot, 'app/src/main/res');
      for (const [folder, value] of [
        ['values', true],
        ['values-night', false],
      ]) {
        fs.mkdirSync(path.join(res, folder), { recursive: true });
        fs.writeFileSync(path.join(res, folder, `${lightSystemBars}.xml`), `<resources>\n  <bool name="${lightSystemBars}">${value}</bool>\n</resources>\n`);
      }
      return config;
    },
  ]);
}

// 입력 커서와 선택 핸들 색을 iOS 입력 칸의 기본 tintColor인 systemBlue로 맞춤
// AccentColor 에셋에 값이 없어 iOS는 시스템 색을 쓰므로 iOS 26 이후 systemBlue 값을 직접 둠
const textAccent = 'plyst_text_accent';
const systemBlue = { values: '#FF0088FF', 'values-night': '#FF0091FF' };

function withTextAccent(config) {
  config = withAndroidStyles(config, (config) => {
    config.modResults = AndroidConfig.Styles.assignStylesValue(config.modResults, {
      add: true,
      parent: { name: 'AppTheme' },
      name: 'colorAccent',
      value: `@color/${textAccent}`,
    });
    return config;
  });
  return withDangerousMod(config, [
    'android',
    async (config) => {
      const res = path.join(config.modRequest.platformProjectRoot, 'app/src/main/res');
      for (const [folder, value] of Object.entries(systemBlue)) {
        fs.mkdirSync(path.join(res, folder), { recursive: true });
        fs.writeFileSync(path.join(res, folder, `${textAccent}.xml`), `<resources>\n  <color name="${textAccent}">${value}</color>\n</resources>\n`);
      }
      return config;
    },
  ]);
}

module.exports = function withAndroidMainActivity(config) {
  config = withMainComponentName(config);
  config = withUIModeRecreation(config);
  config = withClipboardLinkFilter(config);
  config = withRestoredLinkCleared(config);
  config = withSystemBarAppearance(config);
  return withTextAccent(config);
};
