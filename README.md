# Plyst RN

> 복사한 내용을 필요할 때 다시 꺼내 쓰는 iPhone 클립 보관함<br>
> 클립을 찾고 상세 화면에서 이름과 고정 여부를 편집하는 React Native 앱

<a href="https://github.com/opficdev/Plyst"><img src="https://img.shields.io/badge/UIKit_%EB%B2%84%EC%A0%84-opficdev%2FPlyst-181717?style=for-the-badge&logo=github&logoColor=white" alt="UIKit 버전" /></a>
<a href="https://app.notion.com/p/3f1b88a8aa5481f4938cc2484f4fd5c7"><img src="https://img.shields.io/badge/Notion-%EC%9E%91%EC%97%85_%EA%B3%B5%EA%B0%84-000000?style=for-the-badge&logo=notion&logoColor=white" alt="Notion 작업 공간" /></a>
<a href="https://testflight.apple.com/join/BA4MaW9h"><img src="https://img.shields.io/badge/TestFlight-%EB%B2%A0%ED%83%80_%EC%B0%B8%EC%97%AC-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="TestFlight 베타 참여" /></a>

| Home | Search | 텍스트 상세 |
| :---: | :---: | :---: |
| ![Home](./docs/home.png) | ![Search](./docs/search.png) | ![텍스트 상세](./docs/text_detail.png) |

| 이미지 상세 | Widget | Share Extension |
| :---: | :---: | :---: |
| ![이미지 상세](./docs/image_detail.png) | ![Widget](./docs/widget.png) | ![Share Extension](./docs/share.png) |

## 프로젝트 개요

화면과 상태는 RN이 맡고 iOS 실행 환경과 시스템 자원은 Swift가 맡는 브라운필드 앱

| 영역 | 담당 | 이유 |
| --- | --- | --- |
| 화면 구성과 화면 상태 (Home, Search, TextDetail, ImageDetail) | RN | 시스템 자원 없이 화면에서만 사용 |
| 검색 결과 계산과 하이라이트 | RN | `getClips()` 결과를 JavaScript에서 계산 |
| 토스트 | RN | `showToast`를 JavaScript에서 직접 호출 |
| 글자 수와 접두어 계산 | RN | `Model/clipText.ts`에서 `unicode-segmenter`로 계산 |
| 이미지 용량 표시 문구 | RN | `formatByteCount`가 한국어 `ByteCountFormatter` 출력을 재현 |
| 앱과 Scene 생명주기, RN 런타임, 화면 호스트 | Swift | iOS 실행 환경 필요 |
| 상세 화면의 시트와 상단 바 (닫기, 저장 버튼의 Liquid Glass) | Swift | UIKit `UIButton.Configuration.glass()`로 적용 (iOS 26 미만은 평면 버튼) |
| TurboModule 구현과 wire 값 변환 | Swift | Codegen 스펙의 네이티브 구현 |
| 클립 저장소(SQLite), 이미지 원본과 미리보기와 썸네일 파일, App Group | Swift | 저장 무결성과 앱과 Extension 간 공유 필요 |
| 클립 정렬(`ClipSortOrder`) | Swift | Share Extension 반입 경로에서 사용 |
| `isWebLink` 판정 | Swift | Foundation `URL`과 WHATWG `URL`의 판정 차이를 재현할 수 없음 |
| 클립보드 읽기와 쓰기, `lastUsedAt` 갱신 | Swift | 시스템 API와 다른 앱과의 권한 동작에 의존 |
| 사진 저장 | Swift | RN으로 옮겨도 사진 보관함 권한 판정은 Swift에 남아 책임이 나뉨 |
| 최근 검색어의 규칙과 저장 | Swift | 대소문자 비교 결과가 달라지고 목록을 원자적으로 교체해야 함 |
| Share Extension, Widget | Swift | Extension 실행 환경 필요 |

![클립 데이터 흐름](./docs/data-flow.png)

## 주요 기능

- Home에서 클립을 종류와 고정 여부로 분류하고 현재 클립보드를 저장
- Search에서 이름, 본문, 저장 시각으로 검색하고 최근 검색어를 관리
- 상세 화면에서 이름, 메모, 고정 여부를 편집하고 저장, 복사, 삭제 (이미지는 사진 앱에 저장)
- Widget에서 앱을 열어 현재 클립보드를 저장
- Share Extension에서 텍스트, 웹 URL, 이미지를 저장

## 핵심 성과

### **1. Redux Toolkit Store와 Listener로 화면의 상태 변경, Service 호출, 구독 정리를 역할별로 분리**
> **문제**<br>
> 화면 컴포넌트가 `useReducer`와 `useEffect`로 상태 변경, Service 호출, 이벤트 구독을 함께 처리<br>
> 화면을 닫은 뒤에도 구독과 비동기 요청이 남으면 종료된 화면의 상태를 갱신할 수 있음
>
> **해결**<br>
> 화면마다 Store를 만들고 `store.ts`, `actions.ts`, `listeners.ts`로 역할 분리<br>
> 원본 Swift Action 이름을 `action/<이름>`으로 유지해 ReactorKit의 Action, `mutate`, Mutation, `reduce` 흐름과 대응<br>
> 화면 마운트의 `start()`와 해제의 `dispose()`에서 Listener, 요청 큐, 구독을 한 곳에서 정리
>
> **성과**<br>
> ✅ Home, Search, TextDetail, ImageDetail 화면 컴포넌트에서 **Service 호출과 이벤트 구독 제거**<br>
> ✅ 해제된 화면에서는 `dispatch`가 상태를 바꾸지 않아 **종료된 화면의 비동기 결과가 새 화면에 반영되지 않음**<br>
> ✅ 이미 시작한 저장과 복사의 결과 토스트는 **별도 호스트에서 계속 표시**<br>
> ✅ **렌더링 없이** Store와 Listener를 Jest로 검증

```ts
export const textDetailActions = {
  save: createAction('action/save'),
  // ...
};

scope.listen(actions.save, async () => {
  const result = await saveTextDetail(clipID, state.draft);
  // ...
});
```

### **2. Codegen TurboModule로 저장소 접근 경로를 한 곳으로 제한해 RN의 DB와 파일 직접 접근 차단**
> **문제**<br>
> RN과 Swift가 호출 형식을 따로 정의하면 한쪽만 바뀌어도 호출이 어긋날 수 있음
>
> **해결**<br>
> PlystClip, PlystHome, PlystScreen의 Codegen 스펙 하나로 RN 호출과 Swift 구현 연결<br>
> RN 결과물과 브리지를 XCFramework로 묶어 PlystReactNative 패키지로 앱에 연결
>
> **성과**<br>
> ✅ RN 의존성에 **SQLite, 파일 시스템, 클립보드 모듈 없음**<br>
> ✅ 모든 데이터 호출과 이벤트 전달이 **같은 Codegen 스펙을 거치는 구조**

```ts
export interface Spec extends TurboModule {
  readonly onClipChange: CodegenTypes.EventEmitter<ClipChange>;  // Swift에서 RN으로 변경 이벤트 전달
  getClip(id: string): Promise<ClipRecord | null>;               // RN에서 Swift 저장소 조회
  getClips(): Promise<ClipRecord[]>;
  // ...
}
```

### **3. 표시 크기 썸네일과 요청 큐 제한으로 이미지 150개 목록의 메모리 증가량을 UIKit 버전 이하로 유지**
> **문제**<br>
> RN 목록은 이미지 디코딩과 화면 밖 요청 누적으로 이미지 수가 늘수록 UIKit 버전보다 메모리가 빠르게 늘 수 있음
>
> **해결**<br>
> 2열 카드 목록(FlashList masonry)에서 카드 너비와 화면 배율에 맞춘 ImageIO 썸네일 요청<br>
> 화면 밖 대기 요청을 제거하고 실행 중인 요청은 완료 시 결과 폐기<br>
> 썸네일 URI 보관 수 48개와 요청 큐 동시 실행 수 2개로 제한
>
> **성과**<br>
> ✅ 이미지 2개 대비 150개의 최대 메모리 증가량을 비교 시 UIKit **+42.80MB**, RN **+25.48MB**<br>
> ✅ 이미지 150개 목록을 스크롤하여 왕복한 뒤 메모리 비교 시 UIKit **56.71MB**, RN **52.72MB**<br>
> ⚠️ RN 런타임의 고정 메모리는 이미지 2개에서 **+18.78MB**로 UIKit 버전보다 높음

| 이미지 수 | UIKit 왕복 후 / 최대 | RN 왕복 후 / 최대 |
|:---:|:---:|:---:|
| 2개 | 19.38 / 20.96MB | 38.16 / 42.04MB |
| 16개 | 30.80 / 31.59MB | 59.90 / 61.75MB |
| 32개 | 44.12 / 45.75MB | 52.59 / 64.85MB |
| 48개 | 56.90 / 59.05MB | 50.07 / 65.83MB |
| 64개 | 59.57 / 64.26MB | 49.50 / 63.75MB |
| 150개 | 56.71 / 63.75MB | 52.72 / 67.52MB |

| 측정 조건 | 값 |
|:---:|:---:|
| 기기 | iPhone 16 Pro, iOS 26.7.1, USB 연결 |
| 빌드 | UIKit: Release / RN: Hermes 번들 |
| 데이터 | 같은 규칙으로 만든 이미지 2~150개와 텍스트 12개 |
| 이동 | 목록의 처음과 끝을 2회 왕복, 초당 2,200pt |
| 메모리 | 앱 안에서 `phys_footprint`를 250ms 간격으로 관측 |

---

## 기술 스택

| 구분 | 스택 |
| --- | --- |
| 최소 지원 버전 | iOS 17.0+ |
| 지원 기기 | iPhone |
| 언어 | TypeScript 6.0.3, Swift 6.0 |
| 화면 | React Native 0.86.3, React 19.2.3, Expo 57.0.27, FlashList 2.3.3, expo-image 57.0.5, UIKit 호스트 |
| 앱 확장 | Share Extension, WidgetKit, SwiftUI |
| 상태 관리 | Redux Toolkit 2.13.0, React Redux 9.3.0 (RN 화면)<br>ReactorKit 3.2.0, RxSwift 6.10.2 (Share Extension 상태 관리) |
| 네이티브 브리지 | TurboModule, Codegen |
| 앱 통합 | React Native Brownfield 5.3.0, XCFramework |
| 저장소 | SQLiteData 1.12.0, GRDB 7.11.1, swift-structured-queries 0.39.2 |
| Apple 프레임워크 | UIKit, Foundation, WidgetKit, SwiftUI, ImageIO, Photos |
| 테스트 | Jest 29.7.0, XCTest |
| 자동화 | GitHub Actions, fastlane |
