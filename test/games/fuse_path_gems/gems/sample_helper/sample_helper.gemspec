# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

Gem::Specification.new do |spec|
  spec.name = "sample_helper"
  spec.version = "0.1.0"
  spec.summary = "A gem of pure Ruby that lives in a game's own folder."
  spec.authors = ["setdef"]
  spec.licenses = ["AGPL-3.0-or-later"]
  spec.files = ["lib/sample_helper.rb", "lib/sample_helper/shout.rb"]
  spec.require_paths = ["lib"]
end
