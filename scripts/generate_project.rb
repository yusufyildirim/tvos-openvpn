#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

project_path = "TVOpenVPNClient.xcodeproj"
FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)

deployment_target = "17.0"
bundle_prefix = "gs.tinythin.TVOpenVPNClient"
app_group = "group.gs.tinythin.TVOpenVPNClient"

project.build_configurations.each do |config|
  config.build_settings["SWIFT_VERSION"] = "6.0"
  config.build_settings["CLANG_ENABLE_MODULES"] = "YES"
end

app = project.new_target(:application, "TVOpenVPNClient", :tvos, deployment_target)
tunnel = project.new_target(:app_extension, "PacketTunnel", :tvos, deployment_target)
app.add_dependency(tunnel)

partout_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
partout_package.repositoryURL = "https://github.com/partout-io/partout"
partout_package.requirement = {
  "kind" => "branch",
  "branch" => "master"
}
project.root_object.package_references << partout_package

def add_swift_package_product(project, target, package, product_name)
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.package = package
  product.product_name = product_name
  target.package_product_dependencies << product

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product
  target.frameworks_build_phase.files << build_file
end

add_swift_package_product(project, app, partout_package, "partout")
add_swift_package_product(project, tunnel, partout_package, "partout")

def set_common_settings(target, bundle_id, plist, entitlements, app_group)
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id
    settings["INFOPLIST_FILE"] = plist
    settings["CODE_SIGN_ENTITLEMENTS"] = entitlements
    settings["CURRENT_PROJECT_VERSION"] = "1"
    settings["MARKETING_VERSION"] = "1.0"
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["SWIFT_VERSION"] = "6.0"
    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
    settings["DEVELOPMENT_TEAM"] = ""
    settings["TVOS_DEPLOYMENT_TARGET"] = "17.0"
    settings["APPLICATION_GROUP_IDENTIFIER"] = app_group
    settings["EXCLUDED_ARCHS[sdk=appletvsimulator*]"] = "x86_64"
  end
end

set_common_settings(
  app,
  bundle_prefix,
  "TVOpenVPNClient/App/Info.plist",
  "TVOpenVPNClient/App/TVOpenVPNClient.entitlements",
  app_group
)

set_common_settings(
  tunnel,
  "#{bundle_prefix}.PacketTunnel",
  "PacketTunnel/Info.plist",
  "PacketTunnel/PacketTunnel.entitlements",
  app_group
)

tunnel.build_configurations.each do |config|
  config.build_settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"
end

app.build_configurations.each do |config|
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks"
end

project.main_group.new_group("TVOpenVPNClient")
project.main_group.new_group("PacketTunnel")
project.main_group.new_group("Shared")

def group_named(project, name)
  project.main_group.groups.find { |group| group.display_name == name }
end

app_group_ref = group_named(project, "TVOpenVPNClient")
tunnel_group_ref = group_named(project, "PacketTunnel")
shared_group_ref = group_named(project, "Shared")

app_sources = Dir["TVOpenVPNClient/App/**/*.swift"]
tunnel_sources = Dir["PacketTunnel/**/*.swift"]
shared_sources = Dir["Shared/**/*.swift"]

app_sources.each { |path| app.add_file_references([app_group_ref.new_file(path)]); }
tunnel_sources.each { |path| tunnel.add_file_references([tunnel_group_ref.new_file(path)]); }
shared_sources.each do |path|
  file = shared_group_ref.new_file(path)
  app.add_file_references([file])
  tunnel.add_file_references([file])
end

["TVOpenVPNClient/App/Info.plist", "TVOpenVPNClient/App/TVOpenVPNClient.entitlements"].each do |path|
  app_group_ref.new_file(path)
end

["PacketTunnel/Info.plist", "PacketTunnel/PacketTunnel.entitlements"].each do |path|
  tunnel_group_ref.new_file(path)
end

embed_phase = app.new_copy_files_build_phase("Embed App Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_phase.add_file_reference(tunnel.product_reference)
build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project_path, "TVOpenVPNClient", true)

project.save
