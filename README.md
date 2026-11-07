# Plyst RN

> 복사한 내용을 필요할 때 다시 꺼내 쓰는 iPhone, Android 클립 보관함<br>
> 클립을 찾고 상세 화면에서 이름과 고정 여부를 편집하는 React Native 앱

<a href="https://github.com/opficdev/Plyst"><img src="./docs/badges/uikit.svg" alt="UIKit 버전" /></a>

<a href="https://apps.apple.com/kr/app/plyst/id6818818750"><img src="./docs/badges/appstore.svg" alt="App Store 다운로드" /></a>

<table>
  <tr>
    <td width="10%"></td>
    <td width="30%" align="center"><b>Home</b></td>
    <td width="30%" align="center"><b>Widget</b></td>
    <td width="30%" align="center"><b>공유</b></td>
  </tr>
  <tr>
    <td align="center"><b>iOS</b></td>
    <td><img src="./docs/home.png" alt="iOS Home" width="100%" /></td>
    <td><img src="./docs/widget.png" alt="iOS Widget" width="100%" /></td>
    <td><img src="./docs/share.png" alt="iOS 공유" width="100%" /></td>
  </tr>
  <tr>
    <td align="center"><b>Android</b></td>
    <td><img src="./docs/android_home.png" alt="Android Home" width="100%" /></td>
    <td><img src="./docs/android_widget.png" alt="Android Widget" width="100%" /></td>
    <td><img src="./docs/android_share.png" alt="Android 공유" width="100%" /></td>
  </tr>
</table>

## 주요 기능

- 클립을 종류와 고정 여부로 분류하고 현재 클립보드를 저장
- 이름, 본문, 저장 시각으로 검색하고 최근 검색어를 관리
- 상세 화면에서 이름, 메모, 고정 여부를 편집하고 저장, 복사, 삭제 (이미지는 사진 앱에 저장)
- 위젯에서 앱을 열어 현재 클립보드를 저장
- 공유 시트에서 텍스트, 웹 URL, 이미지를 저장

## 핵심 성과

### **1. Rust 코어 도입으로 검색어 입력당 계산 37.0ms → 7.6ms 단축**

![위치 맵핑 생성의 작업 스레드 분리](./docs/search-rust.png)

> **문제**<br>
> 검색에 필요한 텍스트 처리가 JS 스레드에서 실행되어 클립이 늘수록 화면 반응이 늦어짐
>
> **해결**<br>
> 검색 화면을 열면 클립 텍스트를 Rust로 넘겨 작업 스레드에서 정규화<br>
> 검색어를 입력할 때마다 C++ TurboModule의 동기 호출로 Rust 코어에서 정규화 후 비교<br>
> 정규화 전후로 글자 위치가 달라지므로 맵핑으로 원문에서 강조할 위치 계산
>
> **성과**<br>
> ✅ iPhone 글자 입력당 검색 계산 **37.0ms → 7.6ms**<br>
> ✅ Android 에뮬레이터 글자 입력당 검색 계산 **47.1ms → 7.4ms**<br>
> ⚠️ 검색과 강조 범위 계산은 **JS 스레드에서 동기 실행**

```rust
let start = index_of(folded, query, cursor)?;
let end = start + query.len();
let map = field.map(general);
if map.boundaries.get(start) && map.boundaries.get(end) {  // 시작과 끝이 모두 글자 경계일 때만 일치
    let location = map.starts.get(start);  // 정규화 위치를 원문 위치로 변환
    let original_end = map.ends.get(end - 1);
    // ...
}
```

| 측정 조건 | 값 |
|:---:|:---:|
| 기기 | iPhone 16 Pro, iOS 27.2<br>Android 에뮬레이터 Pixel 8, Android 36, arm64 |
| 빌드 | Release, 측정 코드 포함 |
| 데이터 | NFD 한글과 악센트 문자가 섞인 합성 텍스트 클립 5,000개(혼합 데이터), 본문 약 1KB |
| 입력 | `search`와 `클립보드`를 한 글자씩 입력 |
| 횟수 | 변경 전후를 번갈아 맵핑 생성 뒤 6회 측정한 글자 입력당 검색과 강조 범위 계산의 중앙값 |
| 판정 | iPhone과 Android 에뮬레이터(대체 브릿지)에서 혼합과 단순 데이터의 글자 입력당 계산 중앙값, p95, JS 작업, 첫 입력, 메모리 증가 지표 20개가 모두 변경 전보다 작음 |

### **2. 카드 memo 분리로 JS 스레드 작업 시간 2.62s → 1.69s 단축**

![카드 재렌더링 범위 축소](./docs/card-rerender.png)

> **문제**<br>
> FlashList가 화면 상태 전체를 참조해 값 하나만 바뀌어도 보이는 카드 전체를 재렌더링<br>
> 카드마다 렌더 때 새로 만든 핸들러를 받아 바뀐 카드만 골라 렌더할 수 없는 구조
>
> **해결**<br>
> 카드는 고정 핸들러와 표시에 필요한 props만 받는 memo 컴포넌트로 분리<br>
> FlashList의 `renderItem`은 카드 props에 쓰는 값만 참조<br>
> 홈 콘텐츠 높이는 바뀌어도 렌더를 일으키지 않는 `useRef`로 보관
>
> **성과**<br>
> ✅ 홈 리스트 스크롤 기준 JS 스레드 작업 시간 **2.62s → 1.69s**<br>
> ✅ 검색 결과 리스트 스크롤 기준 JS 스레드 작업 시간 **1.99s → 1.57s**<br>
> ⚠️ 메인 스레드 작업 시간은 **변화 없음**

```tsx
const [cardHandlers] = useState<HomeCardHandlers>(() => ({
  onSelect: (clip) => handlers.current.selectClip(clip),  // 렌더마다 새로 만들지 않는 고정 핸들러
  // ...
}));

// 다른 카드의 썸네일이 바뀌어 셀이 다시 렌더되어도 이 카드의 표시 값이 같으면 렌더를 건너뜀
const HomeGridItem = memo(function HomeGridItem({ clip, now, thumbnailUri, isThumbnailFailed, handlers }) {
  // ...
});
```

| 측정 조건 | 값 |
|:---:|:---:|
| 기기 | iPhone 18 Pro 시뮬레이터, iOS 27.2 |
| 빌드 | Release |
| 데이터 | 이미지 50개 리스트 |
| 이동 | 리스트를 2회 왕복 스크롤 |
| 횟수 | 변경 전후 각 3회 평균 |

### **3. Redux Toolkit Listener로 종료된 화면의 상태 갱신 차단**
> **문제**<br>
> 화면 컴포넌트가 `useReducer`와 `useEffect`로 상태 변경, Service 호출, 이벤트 구독을 함께 처리<br>
> 화면을 닫은 뒤에도 구독과 비동기 요청이 남으면 종료된 화면의 상태를 갱신할 수 있음
>
> **해결**<br>
> 화면마다 Store를 만들고 `createSlice`로 State와 Action을 정의하고 `listeners.ts`에 Service 호출과 구독을 분리<br>
> `dispatch(textDetailActions.nameChanged(name))`처럼 Action 생성자를 호출해 문자열 `type`을 직접 쓰지 않음<br>
> 화면 마운트의 `start()`와 해제의 `dispose()`에서 Listener를 끊고 요청 큐와 구독을 한 곳에서 정리
>
> **성과**<br>
> ✅ Home, Search, TextDetail, ImageDetail 화면 컴포넌트에서 **Service 호출과 이벤트 구독 제거**<br>
> ✅ Action 이름과 payload의 오타를 **컴파일에서 검출**<br>
> ✅ 해제된 화면의 Listener는 `signal`이 abort된 뒤 `dispatch`하지 않아 **종료된 화면의 비동기 결과가 새 화면에 반영되지 않음**<br>
> ✅ 이미 시작한 저장과 복사의 결과 토스트는 **별도 호스트에서 계속 표시**<br>
> ✅ **렌더링 없이** Store와 Listener를 Jest로 검증

```ts
export const textDetailSlice = createSlice({
  name: 'textDetail',
  reducers: {
    nameChanged(state, { payload }: PayloadAction<string>) {
      if (state.phase === 'loaded') state.draft.name = payload;
    },
    // ...
  },
});

listen({
  actionCreator: textDetailActions.save,
  effect: async (_, api) => {
    const result = await saveTextDetail(clipID, draft);
    if (!api.signal.aborted) api.dispatch(textDetailActions.saved(result.clip));
    // ...
  },
});
```

### **4. Codegen TurboModule로 RN의 저장소 직접 접근 차단**
> **문제**<br>
> RN과 Swift가 호출 형식을 따로 정의하면 한쪽만 바뀌어도 호출이 어긋날 수 있음
>
> **해결**<br>
> PlystClip, PlystHome의 Codegen 인터페이스와 PlystDetailBarButton 컴포넌트로 RN 호출과 Swift 구현 연결<br>
> RN 결과물과 브리지를 XCFramework로 묶어 PlystReactNative 패키지로 앱에 연결
>
> **성과**<br>
> ✅ RN 의존성에 **SQLite, 파일 시스템, 클립보드 모듈 없음**<br>
> ✅ 모든 데이터 호출과 이벤트 전달이 **같은 Codegen 인터페이스를 거치는 구조**

```ts
export interface Spec extends TurboModule {
  readonly onClipChange: CodegenTypes.EventEmitter<ClipChange>;  // Swift에서 RN으로 변경 이벤트 전달
  getClip(id: string): Promise<ClipRecord | null>;               // RN에서 Swift 저장소 조회
  getClips(): Promise<ClipRecord[]>;
  // ...
}
```

---

## 앱 아키텍처

- 화면과 상태는 iOS와 Android가 같은 RN 코드를 사용
- 검색 계산과 클립 규칙, 저장소, 이미지 파일, 처리 순서는 두 플랫폼이 같은 Rust 코드를 사용
- 실행 환경과 시스템 자원은 플랫폼별 네이티브 호스트가 담당

![앱 아키텍처](./docs/architecture.png)

## 기술 스택

| 구분 | 스택 |
| --- | --- |
| 최소 지원 버전 | iOS 17.0+, Android 7.0+ (API 24) |
| 지원 기기 | iPhone, Android |
| 언어 | TypeScript 6.0.3, Swift 6.0, Kotlin 2.1.20, Rust 1.99.1, C++20 |
| 화면 | React Native 0.86.3, React 19.2.3, Expo 57.0.27, FlashList 2.3.3, expo-image 57.0.5 |
| 앱 확장 | Share Extension, Widget Extension (iOS)<br>App Widget, Share Activity (Android) |
| 상태 관리 | Redux Toolkit 2.13.0, React Redux 9.3.0 (RN 화면)<br>ReactorKit 3.2.0, RxSwift 6.10.2 (Share Extension 상태 관리) |
| 네이티브 브리지 | TurboModule, Codegen, C++ TurboModule(JSI)<br>UniFFI 0.32.2, JNA 5.17.0 (Rust 공통 코어) |
| 앱 통합 | React Native Brownfield 5.3.0, XCFramework (iOS)<br>Expo prebuild (Android) |
| 저장소 | rusqlite 0.41.1 번들 SQLite (Rust 공통 코어) |
| Apple 프레임워크 | UIKit, Foundation, WidgetKit, SwiftUI, ImageIO, Photos |
| Android 프레임워크 | AppWidget, ClipboardManager, MediaStore, FileProvider |
| 테스트 | Jest 29.7.0, XCTest, cargo test |
| 자동화 | GitHub Actions, fastlane |
