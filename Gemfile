# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

source "https://rubygems.org"

# Specify your gem's dependencies in lota.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"
gem "rake-compiler", "~> 1.3"

gem "minitest", "~> 6.0"

gem "rubocop", "~> 1.21"
gem "rubycritic", "~> 4.11"
gem "ostruct", "~> 0.6.3"
gem "inch", "~> 0.4"
gem "flog", "4.8.0"
gem "steep"
gem "rdoc", "~> 7.0"

# Lota's raw pointers are Fiddle's (Lota::Data#pointer), which a game adds
# to its own Gemfile when it wants them; Lota's tests use them.
group :development, :test do
  gem "fiddle"
end

gem "desktop_input_lock", git: "https://github.com/setdef/DesktopInputLock.git", tag: "v0.2.0"
