Pod::Spec.new do |s|
  s.name             = 'fqapi_core'
  s.version          = '0.1.0'
  s.summary          = 'fqapp Rust native core'
  s.description      = 'In-process Rust backend for fqapp (flutter_rust_bridge).'
  s.homepage         = 'https://github.com/ch6vip/fqapp'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'fqapp' => 'noreply@localhost' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'fqapi_core.xcframework'
end
