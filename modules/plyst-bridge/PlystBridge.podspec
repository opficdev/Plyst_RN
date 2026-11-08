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
  spec.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  install_modules_dependencies(spec)
end
