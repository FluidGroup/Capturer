Pod::Spec.new do |spec|
  spec.name = "Capturer"
  spec.version = "0.0.1"
  spec.summary = "Component oriented capturing library"
  spec.description = <<-DESC
  Component oriented capturing library
                   DESC

  spec.homepage = "https://github.com/muukii/Capturer"
  spec.license = "MIT"
  spec.author = { "Muukii" => "muukii.app@gmail.com" }
  spec.social_media_url = "https://twitter.com/muukii_app"

  spec.ios.deployment_target = "12.0"

  spec.source = { :git => "https://github.com/muukii/Capturer.git", :tag => "#{spec.version}" }

  spec.framework = "AVFoundation"
  spec.requires_arc = true

  spec.swift_versions = ["5.5"]

  spec.default_subspec = "Basic"

  spec.subspec "Basic" do |ss|
    ss.source_files = "Capturer/Basic/**/*.swift"
  end

  spec.subspec "Extended" do |ss|
    ss.source_files = "Capturer/Extended/**/*.swift"
    ss.dependency "Capturer/Basic"
  end
end
