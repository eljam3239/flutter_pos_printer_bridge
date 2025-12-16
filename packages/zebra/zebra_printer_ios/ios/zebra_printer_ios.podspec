Pod::Spec.new do |s|
  s.name             = 'zebra_printer_ios'
  s.version          = '0.0.1'
  s.summary          = 'iOS implementation of zebra_printer'
  s.homepage         = 'https://github.com/eljam3239/flutter_zebra'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Eli James' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Follow Zebra's official documentation exactly
  # Use vendored_libraries for the static library file (libZSDK_API.a)
  s.vendored_libraries = 'Frameworks/libZSDK_API.a'
  
  # Set header search paths to the Headers directory
  s.xcconfig = { 
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks/Headers"'
  }
  
  # System frameworks required by Zebra SDK
  s.frameworks = 'CoreBluetooth', 'ExternalAccessory'
  s.libraries = 'xml2'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Frameworks/Headers" "$(SDKROOT)/usr/include/libxml2"',
    'OTHER_LDFLAGS' => '-ObjC'
  }
end