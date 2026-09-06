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

  # Use the xcframework so Xcode auto-selects the correct slice:
  # ios-arm64 for device, ios-arm64_x86_64-simulator for the simulator.
  # The flat libZSDK_API.a only contains device slices and fails to link
  # against the iOS simulator on Apple Silicon.
  s.vendored_frameworks = 'Frameworks/ZSDK_API.xcframework'
  
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
    # -ObjC loads ObjC categories, -all_load ensures ALL symbols from static libraries are included
    # This prevents release build link-time optimization from stripping SDK methods
    'OTHER_LDFLAGS' => '-ObjC -all_load'
  }
  
  # Ensure symbols aren't stripped in release builds
  s.user_target_xcconfig = {
    'DEAD_CODE_STRIPPING' => 'NO',
    'STRIP_INSTALLED_PRODUCT' => 'NO'
  }
end