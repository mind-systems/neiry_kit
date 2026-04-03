#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint neiry_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'neiry_kit'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin wrapping the Neiry Capsule BCI/neurofeedback SDK.'
  s.description      = <<-DESC
Flutter plugin that wraps the Neiry Capsule neurofeedback SDK for iOS and Android,
exposing device discovery, EEG streaming, and classifier APIs via platform channels.
                       DESC
  s.homepage         = 'https://github.com/neiry/neiry_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Neiry' => 'dev@neiry.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Vendored Capsule SDK XCFramework
  s.vendored_frameworks = '../official/iOS/CapsuleClient.framework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/../.symlinks/plugins/neiry_kit/ios/../official/iOS/CapsuleClient.framework/Headers"'
  }
  s.swift_version = '5.0'

  # Privacy manifest
  # s.resource_bundles = {'neiry_kit_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
