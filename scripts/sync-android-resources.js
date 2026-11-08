#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// iOS 에셋 카탈로그가 색과 이미지의 단일 원본
const repositoryRoot = path.resolve(__dirname, '..');
const catalogPath = path.join(repositoryRoot, 'ios/Plyst/Assets.xcassets');
const resPath = path.join(repositoryRoot, 'android/app/src/main/res');
// --check는 파일을 바꾸지 않고 커밋된 리소스가 원본과 다르면 실패
const isCheck = process.argv.includes('--check');

function readContents(dir) {
  return JSON.parse(fs.readFileSync(path.join(dir, 'Contents.json'), 'utf8'));
}

function catalogEntries(extension) {
  return fs
    .readdirSync(catalogPath)
    .filter((entry) => entry.endsWith(extension))
    .sort()
    .map((entry) => ({
      name: path.basename(entry, extension),
      dir: path.join(catalogPath, entry),
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

function readColorSets() {
  return catalogEntries('.colorset').flatMap(({ name, dir }) => {
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

// expo-image Android가 이미지 이름을 소문자와 밑줄로 바꿔 drawable을 찾는 규칙과 같은 변환
function drawableName(name) {
  const normalized = name.toLowerCase().replace(/-/g, '_');
  if (!/^[a-z][a-z0-9_]*$/.test(normalized)) {
    throw new Error(`${name}.imageset 이름은 Android 리소스 이름이 될 수 없음`);
  }
  return normalized;
}

function readImageSets() {
  return catalogEntries('.imageset').flatMap(({ name, dir }) =>
    (readContents(dir).images ?? []).flatMap((image) => {
      if (!image.filename) {
        return [];
      }
      if (image.scale) {
        throw new Error(`${name}.imageset의 배율별 이미지는 지원하지 않음`);
      }
      const appearance = appearanceOf(image);
      if (appearance === null) {
        return [];
      }
      const folder = appearance === 'dark' ? 'drawable-night-nodpi' : 'drawable-nodpi';
      return [
        {
          source: path.join(dir, image.filename),
          target: path.join(resPath, folder, `${drawableName(name)}${path.extname(image.filename).toLowerCase()}`),
        },
      ];
    }),
  );
}

function escapeName(name) {
  return name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// colorset에서 온 항목만 바꾸고 다른 색 항목은 그대로 둠
function syncColors(file, colors) {
  const original = fs.readFileSync(file, 'utf8');
  let xml = original;
  for (const { name, value } of colors) {
    const pattern = new RegExp(`<color name="${escapeName(name)}">[^<]*</color>`);
    const item = `<color name="${name}">${value}</color>`;
    xml = pattern.test(xml) ? xml.replace(pattern, item) : xml.replace('</resources>', `  ${item}\n</resources>`);
  }
  return { file, original, updated: xml };
}

const colorSets = readColorSets();
const colorFiles = [
  syncColors(
    path.join(resPath, 'values/colors.xml'),
    colorSets.map(({ name, light }) => ({ name, value: light })),
  ),
  syncColors(
    path.join(resPath, 'values-night/colors.xml'),
    colorSets.filter(({ dark }) => dark).map(({ name, dark }) => ({ name, value: dark })),
  ),
];
const images = readImageSets();

const differences = [
  ...colorFiles.filter(({ original, updated }) => original !== updated).map(({ file }) => file),
  ...images.filter(({ source, target }) => !fs.existsSync(target) || !fs.readFileSync(source).equals(fs.readFileSync(target))).map(({ target }) => target),
];

if (isCheck) {
  if (differences.length > 0) {
    console.error('Android 리소스가 ios/Plyst/Assets.xcassets와 다름');
    for (const file of differences) {
      console.error(`  ${path.relative(repositoryRoot, file)}`);
    }
    console.error('node scripts/sync-android-resources.js 실행 뒤 결과를 커밋');
    process.exit(1);
  }
} else {
  for (const { file, original, updated } of colorFiles) {
    if (original !== updated) {
      fs.writeFileSync(file, updated);
    }
  }
  for (const { source, target } of images) {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(source, target);
  }
}
