Pod::Spec.new do |s|
  s.name = 'Swinet'
  s.version = '1.0.0'
  s.license = 'MIT'
  s.summary = 'Lightweight and Powerfull HTTP Networking in Swift'
  s.homepage = 'https://github.com/dinhquan/Swinet'
  s.authors = { 'Quan Nguyen' => 'dinhquan191@gmail.com' }
  s.source = { :git => 'https://github.com/dinhquan/Swinet.git', :tag => s.version }

  s.ios.deployment_target = '11.0'

  s.swift_versions = ['5.1', '5.2', '5.3', '5.4', '5.5']

  s.source_files = 'Source/*.swift'
end
