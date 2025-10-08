Pod::Spec.new do |s|
  s.name             = 'star_printer_ios'
  s.version          = '1.0.0'
  s.summary          = 'iOS implementation of the star_printer plugin.'
  s.description      = <<-DESC
iOS implementation of the star_printer plugin using StarXpand SDK.
                       DESC
  s.homepage         = 'https://github.com/eljam3239/flutter_star/tree/main'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Eli James' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # StarXpand SDK - Using local xcframework
  s.vendored_frameworks = 'StarIO10.xcframework'
  s.frameworks = 'ExternalAccessory'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
