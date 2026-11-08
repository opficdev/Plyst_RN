# 프로젝트 전용 ProGuard 규칙
# 기본 규칙 파일 뒤에 덧붙여 적용

# react-native-reanimated
-keep class com.swmansion.reanimated.** { *; }
-keep class com.facebook.react.turbomodule.** { *; }
