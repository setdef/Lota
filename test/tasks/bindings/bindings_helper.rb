# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

  # A generator over the repository at +root+: for the repository and its
  # own list, the same one every time, since it only reads.
  def self.generator(root: TreeHelper::ROOT, list: self.list)
    return @generator ||= new_generator(root, list) if root == TreeHelper::ROOT && list.equal?(self.list)

    new_generator(root, list)
  end

  # A Generator of its own, for +root+ and +list+, reading vendor/love
  # through the survey and the headers' types every test shares, which
  # are what a generator would read itself: root's vendor/love is
  # vendor/love, or a link to it.
  def self.new_generator(root, list)
    Bindings::Generator.new(root:, love: "vendor/love", list:, exceptions:, style: "ext/.clang-format",
      label: "vendor/love #{`git -C #{LOVE} rev-parse HEAD`.strip}", survey:, types:)
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
