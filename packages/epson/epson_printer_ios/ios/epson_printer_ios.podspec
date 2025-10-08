Pod::Spec.new do |s|
  s.name             = 'epson_printer_ios'
  s.version          = '0.0.1'
  s.summary          = 'iOS implementation of epson_printer'
  s.homepage         = 'https://github.com/eljam3239/flutter_epson'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Eli James' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Add the Epson static libraries and headers
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  
  # Make headers available for import - specify both simulator and device paths
  s.xcconfig = { 
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks/libepos2.xcframework/ios-arm64/Headers" "$(PODS_TARGET_SRCROOT)/Frameworks/libepos2.xcframework/ios-arm64_x86_64-simulator/Headers" "$(PODS_TARGET_SRCROOT)/Frameworks/libeposeasyselect.xcframework/ios-arm64/Headers" "$(PODS_TARGET_SRCROOT)/Frameworks/libeposeasyselect.xcframework/ios-arm64_x86_64-simulator/Headers"'
  }
  
  # System frameworks required by Epson SDK
  s.frameworks = 'CoreBluetooth', 'ExternalAccessory'
  s.libraries = 'xml2'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(SDKROOT)/usr/include/libxml2'
  }
end