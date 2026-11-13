#!/usr/bin/env ruby
# Reproducible wiring after flutter create; never generate or request signing keys.
require 'xcodeproj'
require 'pathname'
root = Pathname.new(__dir__)
project = Xcodeproj::Project.open(root.join('Runner.xcodeproj').to_s)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
extension = project.targets.find { |t| t.name == 'ShareExtension' } || project.new_target(:app_extension, 'ShareExtension', :ios, '15.0')
bundle = ENV.fetch('REFRACT_BUNDLE_IDENTIFIER', 'dev.refract')
group_id = ENV.fetch('REFRACT_APP_GROUP_IDENTIFIER', 'group.dev.refract')
version = File.read(root.join('../pubspec.yaml')).match(/^version:\s*([^+\s]+)\+(\d+)/) or abort 'pubspec version missing'
shared = project.main_group.find_subpath('Shared', true); shared.path = 'Shared'
ext_group = project.main_group.find_subpath('ShareExtension', true); ext_group.path = 'ShareExtension'
store = shared.files.find { |f| f.path == 'HandoffStore.swift' } || shared.new_file('HandoffStore.swift')
provider = shared.files.find { |f| f.path == 'HandoffProvider.swift' } || shared.new_file('HandoffProvider.swift')
controller = ext_group.files.find { |f| f.path == 'ShareViewController.swift' } || ext_group.new_file('ShareViewController.swift')
[runner, extension].each do |target|
  [store, provider].each { |ref| target.source_build_phase.add_file_reference(ref, true) unless target.source_build_phase.files_references.include?(ref) }
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    config.build_settings['REFRACT_APP_GROUP_IDENTIFIER'] = group_id
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "#{target.name}/#{target.name}.entitlements"
    config.build_settings['DEVELOPMENT_TEAM'] = ENV['DEVELOPMENT_TEAM'] if ENV['DEVELOPMENT_TEAM'] && !ENV['DEVELOPMENT_TEAM'].empty?
  end
end
extension.source_build_phase.add_file_reference(controller, true) unless extension.source_build_phase.files_references.include?(controller)
extension.build_configurations.each do |config|
  config.build_settings.merge!('PRODUCT_NAME' => 'ShareExtension', 'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle}.ShareExtension", 'INFOPLIST_FILE' => 'ShareExtension/Info.plist',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES', 'GENERATE_INFOPLIST_FILE' => 'NO',
    'MARKETING_VERSION' => version[1], 'CURRENT_PROJECT_VERSION' => version[2],
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'])
end
runner.add_dependency(extension) unless runner.dependencies.any? { |d| d.target == extension }
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Share Extension' } || runner.new_copy_files_build_phase('Embed Share Extension')
embed.dst_subfolder_spec = '13'
# Flutter's Thin Binary script consumes the app Info.plist. Xcode processes
# that plist after embedded extensions, so placing the copy after the script
# creates a dependency cycle. Keep the copy before Thin Binary, even on reruns.
runner.build_phases.delete(embed)
thin_index = runner.build_phases.index { |phase| phase.respond_to?(:name) && phase.name == 'Thin Binary' }
abort 'Flutter Thin Binary phase missing' unless thin_index
runner.build_phases.insert(thin_index, embed)
unless embed.files_references.include?(extension.product_reference)
  embed.add_file_reference(extension.product_reference).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end
# DynamicLibrary.process() needs all C ABI roots retained, not just a .a in a folder.
symbols = File.read(root.join('../../../crates/platform_bridge/src/lib.rs')).scan(/pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+(refract_\w+)/).flatten.uniq
abort 'C ABI exports missing' if symbols.empty?
runner.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle
  # Xcode's debug executable/dylib split applies linker roots to the stub as
  # well as the dylib, leaving the stub's -u references unresolved. Keep the
  # Rust archive and its exported C ABI together in the Runner executable.
  config.build_settings['ENABLE_DEBUG_DYLIB'] = 'NO' if config.name == 'Debug'
  { 'iphoneos*' => 'aarch64-apple-ios', 'iphonesimulator*' => 'ios-simulator-universal' }.each do |sdk, triple|
    config.build_settings["OTHER_LDFLAGS[sdk=#{sdk}]"] = ['$(inherited)', '-force_load', "\"$(PROJECT_DIR)/../../../target/#{triple}/release/librefract.a\"",
      '-Wl,-export_dynamic', '-framework', 'Security', '-framework', 'SystemConfiguration', '-lc++', '-lz', '-liconv'] + symbols.map { |name| "-Wl,-u,_#{name}" }
  end
end
project.save
plist = root.join('Runner/Info.plist')
info = Xcodeproj::Plist.read_from_path(plist); info['RefractAppGroup'] = '$(REFRACT_APP_GROUP_IDENTIFIER)'; Xcodeproj::Plist.write_to_path(info, plist)
puts "Configured embedded ShareExtension, shared group #{group_id}, retained #{symbols.length} Rust ABI symbols"
