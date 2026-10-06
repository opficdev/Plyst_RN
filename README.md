# Plyst RN

[Plyst](https://github.com/opficdev/Plyst)의 화면 계층을 React Native로 점진 전환하는 브라운필드 프로젝트

학습과 실험 그리고 포트폴리오를 위한 별도 저장소이며 현재는 React Native를 도입하기 전의 기반 환경 구성 단계

## 원본과의 관계

- 원본 저장소: [opficdev/Plyst](https://github.com/opficdev/Plyst)
- 기준 커밋: [`ca7b5c72736dbc8ecc4eb068018085db83173a86`](https://github.com/opficdev/Plyst/commit/ca7b5c72736dbc8ecc4eb068018085db83173a86)
- 원본 이력을 가져온 뒤 독립적으로 개발하는 저장소

## 전환 범위

| 구분 | 범위 |
| --- | --- |
| 네이티브 유지 | Share Extension, Widget, 저장소와 서비스 계층 |
| React Native 전환 계획 | 본 앱의 화면 계층을 기능 단위로 점진 전환할 계획이며 아직 구현하지 않은 범위 |

## 개발 환경

- Xcode 27.0
- iOS 17.0 이상
- mise
- SwiftLint

## 설정

```sh
mise install
git config core.hooksPath .githooks
```

## 검증

```sh
make lint
make build
make test-build
make test
```

## AI 작업 흐름

작업 정책은 Notion의 `Plyst RN Agent Policy`에서 관리하며 [`CLAUDE.md`](./CLAUDE.md)는 활성 정책을 불러오는 부트스트랩 문서
