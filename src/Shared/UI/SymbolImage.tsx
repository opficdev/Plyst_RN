import { Image } from 'expo-image';
import type { ImageProps } from 'expo-image';
import { useState } from 'react';
import { Image as NativeImage, PixelRatio, Platform, StyleSheet, View, type ImageLoadEvent, type TextStyle } from 'react-native';

// sf_ drawable의 고유 크기는 SF Symbols 20pt 기호의 이미지 크기
const drawablePointSize = 20;

type SymbolImageProps = {
  name: string;
  contentFit?: ImageProps['contentFit'];
  style?: ImageProps['style'];
  onDisplay?: () => void;
  onLoad?: () => void;
};

// iOS는 SF Symbols를 그리고 Android는 prebuild가 복사한 같은 이름의 sf_ drawable을 그림
// expo-image Android의 tintColor는 PlatformColor를 받지 못해 Android는 React Native Image로 칠함
export function SymbolImage({ name, contentFit, style, onDisplay, onLoad }: SymbolImageProps) {
  if (Platform.OS !== 'android') {
    return <Image source={`sf:${name}`} contentFit={contentFit} style={style} onDisplay={onDisplay} onLoad={onLoad} />;
  }
  return <MaterialSymbolImage name={name} contentFit={contentFit} style={style} onDisplay={onDisplay} onLoad={onLoad} />;
}

// expo-image가 SF Symbols에 넘기는 굵기와 같은 단계의 drawable 접미사
function weightSuffix(fontWeight: TextStyle['fontWeight']) {
  switch (String(fontWeight)) {
    case '600':
      return '_w600';
    case '700':
    case 'bold':
      return '_w700';
    default:
      return '';
  }
}

type NaturalSize = { width: number; height: number };

// expo-image의 SF Symbols 규칙을 따름
// fontSize는 기호 크기이자 크기가 없는 상자의 한 변이고 fontWeight는 굵기
// drawable은 SF Symbols 이미지와 같은 여백을 담아 contain이면 같은 크기의 글리프를 그림
function MaterialSymbolImage({ name, contentFit, style, onDisplay, onLoad }: SymbolImageProps) {
  const [naturalSize, setNaturalSize] = useState<NaturalSize | null>(null);
  const { fontSize, fontWeight, color, ...rest } = StyleSheet.flatten(style) ?? {};
  const box = fontSize === undefined ? rest : { width: fontSize, height: fontSize, ...rest };
  const source = {
    uri: `sf_${name.replaceAll('.', '_')}${weightSuffix(fontWeight)}`,
  };
  const handleLoad = ({ nativeEvent }: ImageLoadEvent) => {
    const { width, height } = nativeEvent.source;
    setNaturalSize({ width, height });
    onDisplay?.();
    onLoad?.();
  };
  if (contentFit !== 'none') {
    return <NativeImage source={source} resizeMode="contain" onLoad={handleLoad} style={[box, { tintColor: color }]} />;
  }
  // none은 기호 크기의 글리프를 상자 가운데에 그림
  // 크기는 불러온 drawable의 픽셀 크기로 정하고 그전에는 상자에 맞춤
  const scale = (fontSize ?? 100) / drawablePointSize / PixelRatio.get();
  return (
    <View style={[box, styles.symbolBox]}>
      <NativeImage
        source={source}
        resizeMode="contain"
        onLoad={handleLoad}
        style={[
          naturalSize === null
            ? StyleSheet.absoluteFill
            : {
                width: naturalSize.width * scale,
                height: naturalSize.height * scale,
              },
          { tintColor: color },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  symbolBox: {
    alignItems: 'center',
    justifyContent: 'center',
  },
});
