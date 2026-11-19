# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A failed Gradle build's log, as GitHub's logs API returns it, for the
# tests of what TrunkWatch and AutoRevert make of a Maven repository that
# did not answer. It is recorded from the "Phones / Android, built" job of
# full run 44470744879 on 2026-11-19 and trimmed to four of its 49 missing
# modules: Maven Central answered that it held none of the modules the
# Android Gradle plugin's own metadata names, though they are published
# there, and the build stopped in 10 seconds. Each part can be swapped for
# another, to make the log of a failure that is the code's.
module GradleLogs
  STAMP = "2026-11-19T06:27:24.7342697Z"

  # The repositories the build searched, Google's Maven and Maven Central.
  REPOSITORIES = ["https://dl.google.com/dl/android/maven2/", "https://repo.maven.apache.org/maven2/"].freeze

  # The path by which the build asked for the Android Gradle plugin.
  PLUGIN = "buildscript of root project 'PhoneCheck' > com.android.application:com.android.application.gradle.plugin:9.4.1 " \
    "> com.android.tools.build:gradle:9.4.1"

  # Gradle's entry for the module +coordinates+ it could not find in any of
  # the +repositories+, which the +paths+ required.
  def self.missing(coordinates, paths, repositories: REPOSITORIES)
    group, name, version = coordinates.split(":")
    file = "#{group.tr('.', '/')}/#{name}/#{version}/#{name}-#{version}.pom"
    [
      "   > Could not find #{coordinates}.",
      "     Searched in the following locations:",
      *repositories.map { |repository| "       - #{repository}#{file}" },
      "     Required by:",
      *paths.map { |path| "         #{path}" },
    ]
  end

  # The four modules kept from the recorded log, each a dependency of a
  # module of the Android Gradle plugin, in four groups.
  def self.unanswered(repositories: REPOSITORIES)
    UNANSWERED_MODULES.map do |coordinates, requirers|
      missing(coordinates, requirers.map { |requirer| "#{PLUGIN} > #{requirer}" }, repositories:)
    end
  end

  # Each module kept from the recorded log, with the path from the
  # Android Gradle plugin to each module that required it.
  UNANSWERED_MODULES = {
    "org.jetbrains.kotlin:kotlin-stdlib:2.2.10" => [
      "com.android.tools.build:gradle-settings-api:9.4.1",
      "com.android.tools.build:gradle-settings-api:9.4.1 > com.android.tools.build:gradle-common-api:9.4.1",
    ],
    "com.google.guava:guava:33.4.0-jre" => ["com.android.tools.build:gradle-api:9.4.1", "com.android.tools.build:builder-test-api:9.4.1"],
    "org.jetbrains:annotations:23.0.0" => ["com.android.tools.ddms:ddmlib:32.4.1", "com.android.tools.layoutlib:layoutlib-api:32.4.1"],
    "com.google.code.findbugs:jsr305:3.0.2" => ["com.android.tools.build:builder:9.4.1 > com.android.tools.build:apkzlib:9.4.1"],
  }.freeze

  # One failure of Gradle's report, a configuration it could not resolve
  # for want of the +missing+ modules.
  def self.resolution(missing = unanswered)
    [
      "* What went wrong:",
      "A problem occurred configuring root project 'PhoneCheck'.",
      "> Could not resolve all artifacts for configuration 'classpath'.",
      *missing.flatten,
      "",
    ]
  end

  # A failure of Gradle's report that is no resolution's.
  COMPILE = [
    "* What went wrong:",
    "Execution failed for task ':compileDebugJavaWithJavac'.",
    "> Compilation failed; see the compiler error output for details.",
    "",
  ].freeze

  # The job's log, from the failures of Gradle's report in +failures+,
  # with +also+ printed after them: every line stamped, and the step's
  # exit status after them.
  def self.log(failures: [resolution], also: [])
    lines = [
      "time ./gradlew --no-daemon --quiet assembleDebug assembleRelease bundleRelease",
      "",
      "FAILURE: Build failed with an exception.",
      "",
      *failures.flatten,
      "* Try:",
      "> Run with --stacktrace option to get the stack trace.",
      "> Run with --info or --debug option to get more log output.",
      "> Run with --scan to get full insights from a Build Scan (powered by Develocity).",
      "> Get more help at https://help.gradle.org.",
      "",
      "BUILD FAILED in 10s",
      *also,
      "##[error]Process completed with exit code 1.",
    ]
    lines.map { |line| "#{STAMP} #{line}\n" }.join
  end

  # The recorded log itself.
  UNANSWERED = log
end
