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
  # scripts/build-plyst-search.sh가 pod install 전에 만드는 Rust 정적 라이브러리
  spec.vendored_frameworks = 'build/PlystSearchCore.xcframework'

  install_modules_dependencies(spec)
end
