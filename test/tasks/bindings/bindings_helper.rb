# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../tree_helper"
require_relative "../../../tasks/bindings/generator"
require_relative "../../../tasks/bindings/report"

# The binding generator's tests read LÖVE's real wrap files at the pinned
# commit, never excerpts written for the test, so a pattern the parser
# misreads in LÖVE fails here. Reading all of them takes seconds, so the
# survey is read once per process.
module BindingsHelper
  LOVE = File.join(TreeHelper::ROOT, "vendor/love")

  # The survey of every wrap file.
  def self.survey
    @survey ||= Bindings::Survey.load(LOVE)
  end

  # The header declarations of LÖVE's classes.
  def self.types
    @types ||= Bindings::CppTypes.load(LOVE)
  end

  # The repository's own binding list and exceptions.
  def self.list
    @list ||= Bindings::BindingList.load(File.join(TreeHelper::ROOT, "ext/lota/bindings.rb"))
  end

  def self.exceptions
    @exceptions ||= Bindings::BindingExceptions.load(File.join(TreeHelper::ROOT, "binding_exceptions.rb"))
  end

  # A generator over the repository at +root+.
  def self.generator(root: TreeHelper::ROOT, list: self.list)
    Bindings::Generator.new(root:, love: "vendor/love", list:, exceptions:, style: "ext/.clang-format",
      label: "vendor/love #{`git -C #{LOVE} rev-parse HEAD`.strip}")
  end

  def survey
    BindingsHelper.survey
  end

  # The Survey::Entry of +love_name+.
  def entry(love_name)
    survey[love_name]
  end

  # The Analysis of +love_name+.
  def analysis(love_name)
    entry(love_name).analysis
  end

  # The Translation of +love_name+.
  def translation(love_name)
    entry(love_name).translation
  end
end
