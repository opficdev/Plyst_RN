require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |spec|
  spec.name = 'PlystBridge'
  spec.version = package['version']
  spec.summary = package['description']
  spec.homepage = 'https://github.com/opficdev/Plyst_RN'
  spec.authors = 'opfic'
  spec.license = { :type => 'UNLICENSED' }
  spec.source = { :git => 'https://github.com/opficdev/Plyst_RN.git', :tag => spec.version.to_s }
  spec.platforms = min_supported_versions
  spec.module_name = 'PlystBridge'
  spec.swift_version = '6.0'
  spec.source_files = 'ios/**/*.{h,mm,swift}'
  # xcodebuild -create-xcframework에 필요한 .swiftinterface를 생성하며 ObjC umbrella header와 Swift가 혼합된 모듈이므로 인터페이스 검증을 생략한다.
  spec.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_EMIT_MODULE_INTERFACE' => 'YES',
    'OTHER_SWIFT_FLAGS' => '-no-verify-emitted-module-interface'
  }

  install_modules_dependencies(spec)
end
