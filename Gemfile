source "https://rubygems.org"

# 맥에서 아무것도 실행하지 않는다. 이 Gemfile 은 GitHub Actions 러너 전용이다.
gem "fastlane", "~> 2.220"
gem "xcodeproj", "~> 1.24"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
