# xcodeproj 1.27이 모르는 Xcode 27 프로젝트 형식을 Fastfile과 Podfile이 프로젝트를 열기 전에 등록
require "xcodeproj"

# 확장 복사 위치(dstSubfolder)를 모르면 프로젝트를 저장할 때 지움
# 확장이 앱의 PlugIns가 아닌 아카이브 루트에 설치되는 문제
copy_phase = Xcodeproj::Project::Object::PBXCopyFilesBuildPhase
unless copy_phase.method_defined?(:dst_subfolder)
  copy_phase.class_eval { attribute :dst_subfolder, String }
end

# CocoaPods는 앱 프로젝트의 objectVersion으로 Pods.xcodeproj를 만드는데 110의 호환 버전 문자열이 없어 pod install이 실패
# CocoaPods 이슈 12927
constants = Xcodeproj::Constants
unless constants::COMPATIBILITY_VERSION_BY_OBJECT_VERSION.key?(110)
  versions = constants::COMPATIBILITY_VERSION_BY_OBJECT_VERSION.merge(110 => "Xcode 27.0").freeze
  constants.send(:remove_const, :COMPATIBILITY_VERSION_BY_OBJECT_VERSION)
  constants.const_set(:COMPATIBILITY_VERSION_BY_OBJECT_VERSION, versions)
end
