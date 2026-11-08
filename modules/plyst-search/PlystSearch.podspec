require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |spec|
  spec.name = 'PlystSearch'
  spec.version = package['version']
  spec.summary = package['description']
  spec.homepage = 'https://github.com/opficdev/Plyst_RN'
  spec.authors = 'opfic'
  spec.license = { :type => 'UNLICENSED' }
  spec.source = { :git => 'https://github.com/opficdev/Plyst_RN.git', :tag => spec.version.to_s }
  spec.platforms = min_supported_versions
  spec.source_files = 'ios/**/*.{h,mm}', 'cpp/**/*.{h,cpp}'
  # C ABI 헤더는 core 소유
  # 심볼은 앱 타깃이 링크하는 PlystCore가 제공
  spec.pod_target_xcconfig = { 'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../../core/include"' }

  install_modules_dependencies(spec)
end
