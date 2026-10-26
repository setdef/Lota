# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bindings/generator"
require_relative "bindings/report"

# The binding generator (Plan 001, story 2): Lota::Native's bindings,
# written from LÖVE's wrap functions by ADR 001's rules, the functions
# ext/lota/bindings.rb lists, and the names binding_exceptions.rb records.
def bindings_generator
  Bindings::Generator.new(
    root: ".", love: "vendor/love", style: "ext/.clang-format",
    list: Bindings::BindingList.load("ext/lota/bindings.rb"),
    exceptions: Bindings::BindingExceptions.load("binding_exceptions.rb"),
    label: "vendor/love #{`git -C vendor/love rev-parse HEAD`.strip}"
  )
end

namespace :bindings do
  desc "Write Lota::Native's generated bindings from vendor/love's wrap functions"
  task :generate do
    generator = bindings_generator
    generator.write
    puts "✅ Wrote #{generator.files.size} generated files"
  end

  desc "Fail if the generated bindings differ from what the generator writes"
  task :check do
    problems = bindings_generator.problems
    abort <<~ERROR if problems.any?
      ❌ The generated bindings do not match what the generator writes:
      #{problems.map { |line| "  #{line}" }.join("\n")}

      Review the change, then run `bundle exec rake bindings:generate` to regenerate them.
    ERROR

    puts "✅ The generated bindings match the generator"
  end

  desc "List every LÖVE function the translation rules cannot translate alone (to FILE, or stdout)"
  task :report, [:file] do |_task, args|
    report = Bindings::Report.new(Bindings::Survey.load("vendor/love")).to_s
    if args[:file]
      File.write(args[:file], report)
      puts "✅ Wrote the binding report to #{args[:file]}"
    else
      puts report
    end
  end
end
