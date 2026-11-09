# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Who wrote what Lota's precompiled gem carries, and under which licenses
# (tasks/licensing.rb).
#
# `work` records code the bundle compiles in: Lota's own, LÖVE's, and each
# library LÖVE bundles, with the files it comes from. `framework` records
# a framework the gem ships in lib/lota/frameworks. NativeGem writes each
# one the gem carries into the gem's REUSE.toml, and stops the build on a
# framework, or a file the bundle compiled, that no entry here covers.
# Each license is one REUSE records: its text is in LICENSES/, or in
# ext/lota/licenses as LICENSE-<identifier>.txt when only the
# precompiled gem uses it. Each work's notices of copyright come from
# its own files, cited beside it.
#
# A framework's `source` is the archive of the source code it was built
# from, which the gem carries where the framework's license asks for its
# source with its object code (NativeGem).
#
# `pending` names licensing the maintainer has yet to decide, for a work
# LÖVE compiles but the bundle does not carry yet. Should the bundle come
# to carry one, the gem records its copyright, names it in a comment, and
# leaves its license out until the decision is made.
#
# The bundle matches its files against these entries in order, so a
# library comes before LÖVE, whose own sources surround it.
#
# An app that lota fuse builds names what its gem carries in its notices
# (Lota::Notices), from the manifest NativeGem writes into the gem from
# these entries (Licensing#notices): each by its `title`, where the
# record's name is not what the notices call it, with its `version` where
# it is known, and with the `credit` its license asks a product's
# documentation to carry.

# The version of LÖVE at the pinned commit
# (vendor/love/src/common/version.h:28), which an app's notices give for
# LÖVE's own code and Lota's patches of it. It is written here and not read
# from that file, because the jobs that deliver a gem check out no
# submodule; test/tasks/licensing_test.rb holds it equal to the file.
love_version = "12.0"

# Lota's own C++ (LICENSE). Its ports of LÖVE's code are Zlib snippets,
# which LÖVE's entry covers.
work "Lota",
  # With the list of DLLs that ext/lota/preload/CMakeLists.txt writes into
  # the build for Windows' preloader.
  sources: ["ext/lota/**", "tmp/engine/build/preload/libraries.inc"],
  copyright: ["2026 setdef <kerrick@setdef.com>"],
  license: ["AGPL-3.0-or-later"]

# Rice's headers, which the bindings compile in (COPYING:1-25 in the rice
# gem).
work "Rice",
  gem: "rice",
  sources: ["include/**"],
  copyright: ["2025 Jason Roelofs <jasongroelofs@gmail.com>, Paul Brannan <curlypaul924@gmail.com>, Charlie Savage"],
  license: ["BSD-2-Clause"]

# vendor/love/src/libraries/ddsparse/ddsparse.h:1-21.
work "ddsparse",
  sources: ["vendor/love/src/libraries/ddsparse/**"],
  copyright: ["2013-2024 Sasha Szpakowski"],
  license: ["Zlib"]

# vendor/love/src/libraries/glad/glad.hpp:2-22.
work "GLAD",
  sources: ["vendor/love/src/libraries/glad/**"],
  copyright: ["2013 David Herberth, modified by Sasha Szpakowski"],
  license: ["MIT"]

# vendor/love/src/libraries/lodepng/lodepng.h:1-23.
work "LodePNG",
  sources: ["vendor/love/src/libraries/lodepng/**"],
  copyright: ["2005-2021 Lode Vandevenne"],
  license: ["Zlib"]

# vendor/love/src/libraries/lz4/lz4.h:1-33 and lz4opt.h:1-6.
work "LZ4",
  sources: ["vendor/love/src/libraries/lz4/**"],
  copyright: ["2011-2017, Yann Collet", "2015-2017, Przemyslaw Skibinski <inikep@gmail.com>"],
  license: ["BSD-2-Clause"]

# vendor/love/src/libraries/xxHash/xxhash.h:1-33.
work "xxHash",
  sources: ["vendor/love/src/libraries/xxHash/**"],
  copyright: ["2012-2016, Yann Collet"],
  license: ["BSD-2-Clause"]

# vendor/love/src/libraries/qoi/qoi.h:1-4.
work "QOI",
  sources: ["vendor/love/src/libraries/qoi/**"],
  copyright: ["2021, Dominic Szablewski - https://phoboslab.org"],
  license: ["MIT"]

# vendor/love/src/libraries/stb/stb_image.h:7949-7988, which offers the
# MIT License or the Unlicense, the choice of whoever uses it.
work "stb_image",
  sources: ["vendor/love/src/libraries/stb/**"],
  copyright: ["2017 Sean Barrett"],
  license: ["MIT OR Unlicense"]

# vendor/love/src/libraries/simplewebp/simplewebp.h:5610-5649, BSD-3-Clause
# with Google's grant of the WebM patents, which asks nothing of whoever
# redistributes it.
work "simplewebp",
  sources: ["vendor/love/src/libraries/simplewebp/**"],
  copyright: ["2010 Google Inc., 2023 Miku AuahDark"],
  license: ["BSD-3-Clause"]

# vendor/love/src/libraries/tinyexr/tinyexr.h:1-24, with OpenEXR's code
# under the same license (lines 30-57 and 7882-7888). LÖVE compiles it
# without the miniz it embeds (TINYEXR_USE_MINIZ 0,
# src/modules/image/magpie/EXRHandler.cpp:31).
work "TinyEXR",
  sources: ["vendor/love/src/libraries/tinyexr/**"],
  copyright: [
    "2014 - 2019, Syoyo Fujita and many contributors",
    "2002, Industrial Light & Magic, a division of Lucas Digital Ltd. LLC",
    "2004, Industrial Light & Magic, a division of Lucas Digital Ltd. LLC",
  ],
  license: ["BSD-3-Clause"]

# vendor/love/src/libraries/utf8/utf8.h:1-23, the Boost Software License's
# text.
work "UTF8-CPP",
  sources: ["vendor/love/src/libraries/utf8/**"],
  copyright: ["2006 Nemanja Trifunovic"],
  license: ["BSL-1.0"]

# glslang, in vendor/love/src/libraries/glslang, by the license each
# file's own header states. The entries for its exceptions come first,
# so each file goes to the narrowest one that covers it.

# SPIRV/hex_float.h:1-12 and SPIRV/bitutils.h:1-12.
work "glslang's Apache-2.0 headers",
  sources: [
    "vendor/love/src/libraries/glslang/SPIRV/hex_float.h",
    "vendor/love/src/libraries/glslang/SPIRV/bitutils.h",
  ],
  copyright: ["2015-2016 The Khronos Group Inc."],
  license: ["Apache-2.0"]

# Bison's parser skeleton, MachineIndependent/glslang_tab.cpp:1-32 and
# glslang_tab.cpp.h:1-32, GPL-3.0-or-later with the exception Bison 2.2
# added, whose text lines 21-32 give word for word.
work "glslang's Bison parser",
  sources: [
    "vendor/love/src/libraries/glslang/glslang/MachineIndependent/glslang_tab.cpp",
    "vendor/love/src/libraries/glslang/glslang/MachineIndependent/glslang_tab.cpp.h",
  ],
  copyright: ["1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation, Inc."],
  license: ["GPL-3.0-or-later WITH Bison-exception-2.2"]

# The Khronos Group's headers in SPIRV, each with the MIT-Khronos-old
# text (SPIRV/GLSL.std.450.h:1-25, and the same in the rest).
work "glslang's Khronos headers",
  sources: [
    "vendor/love/src/libraries/glslang/SPIRV/spirv.hpp11",
    "vendor/love/src/libraries/glslang/SPIRV/GLSL.*.h",
    "vendor/love/src/libraries/glslang/SPIRV/NonSemantic*.h",
  ],
  copyright: [
    "2014-2016 The Khronos Group Inc.",
    "2014-2017 The Khronos Group Inc.",
    "2014-2020 The Khronos Group Inc.",
    "2014-2024 The Khronos Group Inc.",
    "2018 The Khronos Group Inc.",
    "2020 The Khronos Group Inc.",
    "2021 The Khronos Group Inc.",
    "2022-2024 Arm Limited.",
    "2022, 2025 ARM Limited",
    "2020 Advanced Micro Devices, Inc. All rights reserved.",
  ],
  license: ["MIT-Khronos-old"]

# MachineIndependent/gl_types.h:1-22: the Khronos Group's license
# without MIT-Khronos-old's paragraph on modifications, which no SPDX
# identifier names, so its text is recorded as LicenseRef-Khronos-Materials.
work "glslang's gl_types.h",
  sources: ["vendor/love/src/libraries/glslang/glslang/MachineIndependent/gl_types.h"],
  copyright: ["2013 The Khronos Group Inc."],
  license: ["LicenseRef-Khronos-Materials"]

# The preprocessor's files carry BSD-3-Clause and, after it, NVIDIA's
# own notice of 2002 (MachineIndependent/preprocessor/PpAtom.cpp:1-73,
# and the same in each), which no SPDX identifier names and glslang's
# LICENSE.txt does not list, so its text is recorded as
# LicenseRef-NVIDIA-Software-2002.
work "glslang's preprocessor",
  sources: ["vendor/love/src/libraries/glslang/glslang/MachineIndependent/preprocessor/**"],
  copyright: [
    "2002-2005 3Dlabs Inc. Ltd.",
    "2013 LunarG, Inc.",
    "2015-2018 Google, Inc.",
    "2017 ARM Limited.",
    "2023, Mobica Limited",
    "2002, NVIDIA Corporation.",
  ],
  license: ["BSD-3-Clause", "LicenseRef-NVIDIA-Software-2002"]

# The rest of glslang: BSD-3-Clause (glslang/Include/Common.h:1-34, and
# the same in each).
work "glslang",
  sources: ["vendor/love/src/libraries/glslang/**"],
  copyright: [
    "2002-2005 3Dlabs Inc. Ltd.",
    "2002-2010 The ANGLE Project Authors.",
    "2012-2013 LunarG, Inc.",
    "2012-2015 LunarG, Inc.",
    "2012-2016 LunarG, Inc.",
    "2013 LunarG, Inc.",
    "2013-2016 LunarG, Inc.",
    "2014 LunarG, Inc.",
    "2014-2015 LunarG, Inc.",
    "2014-2016 LunarG, Inc.",
    "2016 LunarG, Inc.",
    "2016-2017 LunarG, Inc.",
    "2017 LunarG, Inc.",
    "2023 LunarG, Inc.",
    "2015-2016 Google, Inc.",
    "2015-2018 Google, Inc.",
    "2015-2020 Google, Inc.",
    "2016 Google, Inc.",
    "2018 Google, Inc.",
    "2018-2020 Google, Inc.",
    "2020 Google, Inc.",
    "2017 ARM Limited.",
    "2017, 2019 ARM Limited.",
    "2017, 2022-2024 Arm Limited.",
    "2017, 2022-2025 Arm Limited.",
    "2020 The Khronos Group Inc.",
    "2021 Advanced Micro Devices, Inc.",
    "2020 Advanced Micro Devices, Inc. All rights reserved.",
    "2020-2021 Advanced Micro Devices, Inc. All rights reserved.",
    "2024 Ravi Prakash Singh.",
    "2024 Valve Corporation.",
    "2025 Jan Kelemen",
  ],
  license: ["BSD-3-Clause"]

# NonSemanticShaderDebugInfo100.h:1-25 in vendor/love/src/libraries/spirv_cross,
# the Khronos Group's header with the MIT-Khronos-old text.
work "SPIRV-Cross's Khronos header",
  sources: ["vendor/love/src/libraries/spirv_cross/NonSemanticShaderDebugInfo100.h"],
  copyright: ["2018-2024 The Khronos Group Inc."],
  license: ["MIT-Khronos-old"]

# The rest of vendor/love/src/libraries/spirv_cross. Each spirv_*.cpp and
# .hpp offers Apache-2.0 or MIT (spirv_cross.cpp:1-21), and Lota uses it
# under MIT; spirv.hpp:1-7 and GLSL.std.450.h:1-3 state MIT alone.
work "SPIRV-Cross",
  sources: ["vendor/love/src/libraries/spirv_cross/**"],
  copyright: [
    "2015-2021 Arm Limited",
    "2016-2021 Arm Limited",
    "2018-2021 Arm Limited",
    "2016-2021 The Brenwill Workshop Ltd.",
    "2019-2021 Hans-Kristian Arntzen",
    "2018-2021 Bradley Austin Davis",
    "2014-2016,2021 The Khronos Group, Inc.",
    "2014-2024 The Khronos Group Inc.",
  ],
  license: ["MIT"]

# PhysicsFS's copy of miniz's inflater, under the Unlicense
# (vendor/love/src/libraries/physfs/physfs_miniz.h:1-3 and 685-708), which
# the zip archiver compiles in (physfs_archiver_zip.c:23).
work "PhysicsFS's miniz",
  sources: ["vendor/love/src/libraries/physfs/physfs_miniz.h"],
  copyright: ["2011 Rich Geldreich <richgel99@gmail.com>"],
  license: ["Unlicense"]

# PhysicsFS's copy of the LZMA SDK, which the 7z archiver compiles in
# (physfs_archiver_7z.c:14). Its header puts it in the public domain
# (vendor/love/src/libraries/physfs/physfs_lzmasdk.h:4-7), which no SPDX
# identifier names, so the dedication's text, copied from those lines, is
# recorded as LicenseRef-LZMA-SDK-Public-Domain. The file holds no notice
# of copyright; its sections name their author and date ("2009-05-26 :
# Igor Pavlov : Public domain" through 2016-06-09), so the record names
# him with those years.
work "PhysicsFS's LZMA SDK",
  sources: ["vendor/love/src/libraries/physfs/physfs_lzmasdk.h"],
  copyright: ["2009-2016 Igor Pavlov"],
  license: ["LicenseRef-LZMA-SDK-Public-Domain"]

# PhysicsFS 3.2.0 (vendor/love/src/libraries/physfs/physfs.h:437-439),
# which the bundle links since Lota::Boot opens LÖVE's filesystem. LÖVE's
# copy has no license text: physfs.c:1-9 points to a LICENSE.txt in the
# source's root, which LÖVE leaves out. Its copyright and license come
# from that file in PhysicsFS's own release, LICENSE.txt:1-17 at the
# release-3.2.0 tag (https://github.com/icculus/physfs, commit
# eb3383b532c5f74bfeb42ec306ba2cf80eed988c), whose text is the zlib
# License's. Every other file of LÖVE's copy points to that LICENSE.txt
# (physfs.c:6, physfs.h:210-211) or states no license of its own
# (physfs_archiver_vdf.c, physfs_platforms.h, physfs_unicode.c), except
# miniz and the LZMA SDK, recorded above.
work "PhysicsFS",
  sources: ["vendor/love/src/libraries/physfs/**"],
  copyright: ["2001-2022 Ryan C. Gordon <icculus@icculus.org> and others"],
  license: ["Zlib"],
  version: "3.2.0"

# dr_flac and dr_mp3, which love.sound's FLAC and MP3 decoders compile in
# (src/modules/sound/lullaby/FLACDecoder.h and MP3Decoder.h). Each offers
# the Unlicense or MIT No Attribution, at the user's choice
# (vendor/love/src/libraries/dr/dr_flac.h:1-2 and its license section at
# the end of the file, "ALTERNATIVE 1" and "ALTERNATIVE 2", and
# dr_mp3.h:2 and 4749-4800, the same), and MIT No Attribution names its
# author (dr_mp3.h:4780).
work "dr_libs",
  sources: ["vendor/love/src/libraries/dr/**"],
  copyright: ["2020 David Reid"],
  license: ["Unlicense OR MIT-0"]

# Wuff 0.0.0.2 (vendor/love/src/libraries/Wuff/wuff.h:13-16), the WAVE
# reader love.sound's WaveDecoder compiles in
# (src/modules/sound/lullaby/WaveDecoder.h). LÖVE's copy holds no license
# or notice of copyright, and LÖVE's license.txt does not list it. LÖVE
# took it from its author, Boolsheet, in its commit e5adc4e5f ("Fixed
# wave sound playback by using a different wave reader library (thanks
# Boolsheet!)", 2013-10-23). Its repository,
# https://bitbucket.org/Boolsheet/wuff, is gone from Bitbucket; the
# Internet Archive keeps its tag "Wuff 0.0.0.2" as the archive Bitbucket
# served (web.archive.org/web/20200622091454/https://bitbucket.org/
# Boolsheet/wuff/get/Wuff%200.0.0.2.tar.bz2, SHA-256
# db22ea7bcf55929df8581b173328899d28f563ace9b4d503f1de457c554d1213, node
# 3acfc2e7d42fa5f2f7b1fe73d7c04b1089c2807e in its .hg_archival.txt), whose
# every source file is byte for byte LÖVE's. Its unlicense.txt dedicates
# it to the public domain with the Unlicense's text, and its news.txt
# dates its releases from 2012-07-25 to 2013-10-20. It holds no notice of
# copyright, so the record names its author with those years.
work "Wuff",
  sources: ["vendor/love/src/libraries/Wuff/**"],
  copyright: ["2012-2013 Boolsheet"],
  license: ["Unlicense"],
  version: "0.0.0.2"

# Noise1234, which the bundle links for Lota::Math's Perlin and simplex
# noise. Its author put it in the public domain (noise1234.h:4-7, and the
# same sentences in simplexnoise1234.h:6-9), in words no SPDX identifier
# names, so the dedication's text, copied from those lines, is recorded as
# LicenseRef-Noise1234-Public-Domain. simplexnoise1234.h:2 holds its
# notice of copyright, and noise1234.h:2 names the same author.
work "Noise1234",
  sources: ["vendor/love/src/libraries/noise1234/**"],
  copyright: ["2003-2011, Stefan Gustavson"],
  license: ["LicenseRef-Noise1234-Public-Domain"]

# LÖVE's default font, Noto Sans 2.001, which
# vendor/love/src/modules/font/NotoSans-Regular.ttf.gzip.h embeds; the
# copyright and license are in the font's own name table (name IDs 0 and
# 13), and LÖVE's license.txt does not list it.
work "Noto Sans",
  sources: ["vendor/love/src/modules/font/NotoSans-Regular.ttf.gzip.h"],
  copyright: ["2019 Google Inc. All Rights Reserved."],
  license: ["OFL-1.1"],
  version: "2.001"

# The Vulkan renderer LÖVE builds everywhere but on Apple's systems
# (vendor/love/CMakeLists.txt:656-709), which the bundle carries on Linux,
# and the libraries it compiles in:

# The Khronos Group's Vulkan headers, and the video codec headers they
# include, each under Apache-2.0
# (vendor/love/src/libraries/vulkanheaders/vulkan_core.h:4-8 and
# vk_video/vulkan_video_codecs_common.h:4-8, and the same in each).
work "Vulkan-Headers",
  sources: ["vendor/love/src/libraries/vulkanheaders/**", "vendor/love/src/libraries/vk_video/**"],
  copyright: ["2014-2025 The Khronos Group Inc.", "2015-2025 The Khronos Group Inc."],
  license: ["Apache-2.0"]

# volk, the Vulkan loader the renderer calls through
# (vendor/love/src/libraries/volk/volk.h:2188-2208; volk.c:1 points to it).
work "volk",
  sources: ["vendor/love/src/libraries/volk/**"],
  copyright: ["2018-2025 Arseny Kapoulkine"],
  license: ["MIT"]

# The Vulkan Memory Allocator (vendor/love/src/libraries/vma/
# vk_mem_alloc.h:1-21).
work "Vulkan Memory Allocator",
  sources: ["vendor/love/src/libraries/vma/**"],
  copyright: ["2017-2025 Advanced Micro Devices, Inc. All rights reserved."],
  license: ["MIT"]

# Box2D 2.4.0 (vendor/love/src/libraries/box2d/common/b2_settings.cpp:32),
# which the bundle links since Lota binds love.physics. Every file but one
# carries the MIT License with "Copyright (c) 2019 Erin Catto"
# (dynamics/b2_world.cpp:1-21, and the same in each); b2_types.h:1-3 says
# 2020. Its README.MODIFIED says the LÖVE Development Team changed it, but
# names no license of theirs, and the bundle compiles nothing from that
# file.
work "Box2D",
  sources: ["vendor/love/src/libraries/box2d/**"],
  copyright: ["2019 Erin Catto", "2020 Erin Catto"],
  license: ["MIT"],
  version: "2.4.0"

# LÖVE's physics module as Lota's physics patch changes it
# (ext/lota/engine/physics.patch), which CMake writes into the build tree
# and the bundle compiles in place of vendor/love's (ADR 005).
# The patched files are LÖVE's, under LÖVE's license, with changes the
# patch's own header puts under the same license.
work "LÖVE's patched physics module",
  sources: ["tmp/*/build/patched/love/src/modules/physics/**"],
  copyright: ["2006-2026 LOVE Development Team", "2026 setdef <kerrick@setdef.com>"],
  license: ["Zlib"],
  title: "LÖVE #{love_version}'s physics module, as Lota's physics patch changes it"

# LÖVE's graphics/Mesh.cpp as Lota's Mesh patch changes it
# (ext/lota/engine/mesh.patch), which CMake writes into the build tree and
# the bundle compiles in place of vendor/love's. It is LÖVE's file, under
# LÖVE's license, with a change the patch's own header puts under the same
# license.
work "LÖVE's patched Mesh",
  sources: ["tmp/*/build/patched/love/src/modules/graphics/Mesh.cpp"],
  copyright: ["2006-2026 LOVE Development Team", "2026 setdef <kerrick@setdef.com>"],
  license: ["Zlib"],
  title: "LÖVE #{love_version}'s graphics/Mesh.cpp, as Lota's Mesh patch changes it"

# LÖVE's graphics/vulkan/Graphics.cpp as Lota's Vulkan patches change it
# (ext/lota/engine/vulkan_semaphores.patch and vulkan_submit.patch, and on
# Android vulkan_present.patch), which CMake writes into the build tree
# and the bundle compiles in place of vendor/love's wherever LÖVE builds
# its Vulkan renderer. It is LÖVE's file, under LÖVE's license, with
# changes the patches' own headers put under the same license.
work "LÖVE's patched Vulkan renderer",
  sources: ["tmp/*/build/patched/love/src/modules/graphics/vulkan/Graphics.cpp"],
  copyright: ["2006-2026 LOVE Development Team", "2026 setdef <kerrick@setdef.com>"],
  license: ["Zlib"],
  title: "LÖVE #{love_version}'s graphics/vulkan/Graphics.cpp, as Lota's Vulkan patches change it"

# The lz4.c of the LZ4 1.8.0 LÖVE bundles as Lota's LZ4 patch changes it
# (ext/lota/engine/lz4.patch), which CMake writes into the build tree and
# the bundle compiles in place of vendor/love's. It is LZ4's file, under
# LZ4's license (vendor/love/src/libraries/lz4/lz4.c:1-33), with two
# statements of LZ4's own later releases, whose authors the patch's
# header names, under the same license.
work "LÖVE's patched LZ4",
  sources: ["tmp/*/build/patched/love/src/libraries/lz4/lz4.c"],
  copyright: [
    "2011-2017, Yann Collet",
    "2018 Yann Collet",
    "2020 Alexander Gallego <alex@vectorized.io>",
    "2026 setdef <kerrick@setdef.com>",
  ],
  license: ["BSD-2-Clause"],
  title: "LZ4 1.8.0's lz4.c, as Lota's LZ4 patch changes it"

# LÖVE's own sources (vendor/love/license.txt:6-9). Its bundled libraries
# in src/libraries are works of their own, above; one the list lacks
# stops the build.
work "LÖVE",
  sources: ["vendor/love/src/common/**", "vendor/love/src/modules/**"],
  copyright: ["2006-2026 LOVE Development Team"],
  license: ["Zlib"],
  version: love_version

# FreeType's license asks a product that uses it to credit it in its
# documentation (LICENSE-FTL.txt, "Introduction", lines 35-56: the words
# it encourages, with <year> the year of the FreeType version used; and
# section 2, lines 116-120: a disclaimer "that the software is based in
# part of the work of the FreeType Team"), so an app's notices carry these
# words, with the year of the release each platform's FreeType is.
freetype_credit = lambda do |year|
  "Portions of this software are copyright © #{year} The FreeType Project (www.freetype.org). All rights reserved. " \
    "This software is based in part of the work of the FreeType Team."
end

# macOS. The frameworks the gem carries in lib/lota/frameworks come
# prebuilt from love-apple-dependencies, whose history holds the binaries
# and no build scripts but LuaJIT's. Each one's licensing comes from the
# files it was compiled from, found without a build log: its exact
# upstream release, from its headers (byte for byte a tag's) and version
# strings; how it was built, from its Info.plist and what it links; the
# sources that build compiles, from the build files of that release; the
# files those sources include, followed from each #include; and, where a
# file's inclusion was uncertain, the symbols and strings in the binary.
# Every license and notice of copyright those files state is recorded.

# SDL 3.4.10 (Resources/Info.plist; its 75 headers are byte for byte
# include/SDL3 at release-3.4.10, commit
# 8e37db5e797b6167f3a00d697d816a684bd259c7), built by the SDL3 framework
# target of SDL's own Xcode project, Xcode/SDL/SDL.xcodeproj, whose
# Info-Framework.plist the framework's is (its CFBundleSignature SDLX and
# CFBundleGetInfoString). The target's Sources phase compiles 233 files,
# which with what they include are 599, read for their licenses with
# include/build_config/SDL_build_config_macos.h's configuration. Under its
# own license, LICENSE.txt:1-17, which every file of SDL's own states
# (src/SDL.c:1-20), with the code of others it compiles in, each under the
# license its files state:
#
# - BSD-3-Clause: yuv2rgb (src/video/yuv2rgb/LICENSE), and HIDAPI, whose
#   macOS backend, src/hidapi/mac/hid.c (lines 1-18; its IOHIDDevice
#   strings are in the binary), offers GPL-3.0, a BSD-style license, or
#   its original license, at the user's choice (src/hidapi/LICENSE.txt);
#   Lota uses it under the BSD-style one, src/hidapi/LICENSE-bsd.txt.
#   include/SDL3/SDL_hidapi.h:29-42 quotes HIDAPI's original notice for
#   the interface it adapts, which the same choice covers.
# - MIT: include/SDL3/SDL_opengl.h (Mesa's, lines 36-58),
#   SDL_opengl_glext.h, SDL_egl.h, SDL_opengles2_khrplatform.h,
#   SDL_opengles2_gl2.h, and SDL_opengles2_gl2ext.h (the Khronos Group's),
#   which the OpenGL, OpenGL ES 2, and EGL code compiles in.
# - Apache-2.0: the Khronos Group's Vulkan headers, src/video/khronos/
#   vulkan and vk_video (vulkan/vulkan_core.h:4-8), which SDL_VIDEO_VULKAN
#   and SDL_GPU_VULKAN (SDL_build_config_macos.h:236-237) compile in for
#   MoltenVK; SDL_opengles2_gl2platform.h:5-6; and the EGL sections of
#   SDL_egl.h (lines 360-361, 535-536, and 879-880).
# - MIT OR Unlicense: stb_image, src/video/stb_image.h, which offers
#   either, recorded as LÖVE's own copy is, and which src/video/SDL_stb.c:65
#   compiles in for PNG and JPEG (its "Corrupt PNG" and "Corrupt JPEG" are
#   in the binary).
# - Unlicense: miniz, src/video/miniz.h:1-3 and 5074-5099, which
#   SDL_stb.c:80 compiles in.
#
# What the Linux build adds is not compiled here: SDL's libm (macOS's is
# used, and the Xcode project compiles none of src/libm), X11 and
# Wayland. src/stdlib/SDL_malloc.c and SDL_strtokr.c are compiled, but
# the dlmalloc and PDCLib code they hold under CC0 is not, since
# SDL_build_config_macos.h:52 and 71 define HAVE_MALLOC and
# HAVE_STRTOK_R. Its other files without a notice of their own, such as
# the Metal shaders SDL generates (src/render/metal, src/gpu/metal), are
# SDL's, under its license.
framework "SDL3.framework",
  copyright: [
    "1997-2026 Sam Lantinga <slouken@libsdl.org>",
    "1998-2021 Gareth McCaughan",
    "2001-2011 Andreas Schiffler",
    "2017, Mark Callow",
    "2023 Collabora Ltd.",
    "2020 Valve Corporation",
    "2021 Valve Corporation",
    "Valve Corporation",
    "2023 Max Maisel <max.maisel@posteo.de>",
    "2025 Bernat Arlandis <berarma@hotmail.com>",
    "2025 Katharine Chui <katharine.chui@gmail.com>",
    "2025 Michal Malý <madcatxster@devoid-pointer.net>",
    "2025 Mitchell Cairns <mitch.cairns@handheldlegend.com>",
    "2025 Simon Wood <simon@mungewell.org>",
    "2025 Zuiki Inc.",
    "2016, Adrien Descamps",
    "2009, Alan Ott, Signal 11 Software",
    "2010, Alan Ott, Signal 11 Software",
    "2022-2023 Alan Ott, Signal 11 Software, and the libusb/hidapi Team",
    "1999-2006 Brian Paul",
    "2009 VMware, Inc.",
    "2007-2020 The Khronos Group Inc.",
    "2008-2018 The Khronos Group Inc.",
    "2013-2020 The Khronos Group Inc.",
    "2017-2020 The Khronos Group Inc.",
    "2014-2024 The Khronos Group Inc.",
    "2015-2024 The Khronos Group Inc.",
    "2017 Sean Barrett",
    "2010-2013 Rich Geldreich <richgel99@gmail.com>",
  ],
  license: ["Zlib", "BSD-3-Clause", "MIT", "Apache-2.0", "MIT OR Unlicense", "Unlicense"],
  title: "SDL",
  version: "3.4.10"

# FreeType 2.11.1 (Headers/freetype.h:4741-4743; every header is byte for
# byte the VER-2-11-1 tag's), built by its CMakeLists.txt with
# BUILD_FRAMEWORK, whose builds/mac/freetype-Info.plist gives the
# framework's "FreeType " (the version it leaves empty). That build
# compiles CMakeLists.txt:367-429's sources, every module its ftmodule.h
# registers, with builds/unix/ftsystem.c and src/base/ftdebug.c, and the
# files each includes. It offers the FreeType License or GPL-2.0
# (LICENSE.TXT); Lota uses it under the FreeType License (docs/FTL.TXT),
# Adobe's CFF engine in src/psaux included (src/psaux/psft.c:1-36, which
# puts it under the FreeType License). The BDF and PCF drivers and
# src/base/fthash.c are under MIT (src/bdf/README:96-117,
# src/pcf/README:67-88, and fthash.c:9-31), and src/pcf/pcfutil.c, which
# src/pcf/pcf.c includes, under the Open Group's license (lines 1-25,
# MIT-open-group). It links the system's zlib and libbzip2, whose inflate
# and BZ2_ functions it imports, so neither the zlib in src/gzip nor any
# bzip2 is compiled in, and the gem carries neither. src/base/ftobjs.c
# includes src/base/md5.c, but its only caller is under
# FT_DEBUG_LEVEL_TRACE (ftobjs.c:4730), and none of its functions is in
# the binary. The notices are each one these files hold.
framework "freetype.framework",
  copyright: [
    "1996-2021 David Turner, Robert Wilhelm, and Werner Lemberg",
    "1996-2021 Just van Rossum, David Turner, Robert Wilhelm, and Werner Lemberg",
    "2004-2021 David Turner, Robert Wilhelm, Werner Lemberg, and George Williams",
    "2008-2021 David Turner, Robert Wilhelm, Werner Lemberg, and suzuki toshiya",
    "2018-2021 Armin Hasitzka, David Turner, Robert Wilhelm, and Werner Lemberg",
    "2018-2021 David Turner, Robert Wilhelm, Dominik Röttsches, and Werner Lemberg",
    "2019-2021 Nikhil Ramakrishnan, David Turner, Robert Wilhelm, and Werner Lemberg",
    "2005-2021 David Turner",
    "2007-2021 David Turner",
    "2002-2021 Roberto Alameda",
    "2003-2021 Masatake YAMATO, Red Hat K.K., David Turner, Robert Wilhelm, and Werner Lemberg",
    "2004-2021 Masatake YAMATO and Redhat K.K.",
    "2004-2021 Masatake YAMATO, Redhat K.K., David Turner, Robert Wilhelm, and Werner Lemberg",
    "2004-2021 Albert Chin-A-Young",
    "2007-2021 Derek Clegg and Michael Toftdal",
    "2007-2021 Rahul Bhalerao <rahul.bhalerao@redhat.com>, <b.rahul.pm@gmail.com>",
    "2009-2021 Oran Agra and Mickey Gabel",
    "2010-2021 Joel Klinghed",
    "2013 Google, Inc.",
    "2013-2021 Google, Inc.",
    "2006-2014 Adobe Systems Incorporated",
    "2003 Huw D M Davies for Codeweavers",
    "2007 Dmitry Timoshkov for Codeweavers",
    "2000 Computing Research Labs, New Mexico State University",
    "2000-2014 Francesco Zappa Nardelli",
    "2001-2015 Francesco Zappa Nardelli",
    "1990, 1994, 1998 The Open Group",
  ],
  license: ["FTL", "MIT", "MIT-open-group"],
  title: "FreeType",
  version: "2.11.1",
  credit: freetype_credit.call(2021)

# HarfBuzz 6.0.0 (Resources/Info.plist; its headers are byte for byte the
# 6.0.0 tag's, commit afcae83a064843d71d47624bc162e121cc56c08b), built by
# its CMakeLists.txt with BUILD_FRAMEWORK (lines 670-680 give the
# Info.plist's versions), with the FreeType and CoreText backends it
# links. That build compiles one file, src/harfbuzz.cc (CMakeLists.txt:190),
# which includes every other, 301 files in all with what they include:
# COPYING:1-38, the "Old MIT" text (MIT-Modern-Variant), which its files
# state (src/hb.hh:1-27, and the same in each); src/ms-use/COPYING, which
# covers the Universal Shaping Engine's data the library compiles in
# (src/hb-ot-shaper-use-table.hh and hb-ot-shaper-vowel-constraints.cc),
# MIT; src/hb-ucd.cc:1-15, whose Unicode functions the binary carries,
# under ISC; and the Unicode Character Database's data, Unicode 15.0.0,
# its tables are generated from (src/hb-ucd-table.hh:1-8 and
# hb-unicode-emoji-table.hh:1-19), under the terms of use that table
# points to, which in 2022 were Unicode's Data Files and Software license
# (https://www.unicode.org/license.txt, as the Internet Archive kept it on
# 2022-11-04), Unicode-DFS-2016. Its FreeType headers are FreeType's,
# recorded with it, and its other backends (DirectWrite, GDI, GLib,
# Graphite2, Uniscribe) compile to nothing on macOS.
framework "harfbuzz.framework",
  copyright: [
    "2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022 Google, Inc.",
    "2015-2020 Ebrahim Byagowi",
    "2019,2020 Facebook, Inc.",
    "2012,2013,2015 Mozilla Foundation",
    "2011 Codethink Limited",
    "2008,2010 Nokia Corporation and/or its subsidiary(-ies)",
    "2009 Keith Stribley",
    "2009 Martin Hosken and SIL International",
    "2011 Martin Hosken",
    "2011 SIL International",
    "2007 Chris Wilson",
    "2005,2006,2020,2021,2022 Behdad Esfahbod",
    "2005 David Turner",
    "2004,2007,2008,2009,2010,2013 Red Hat, Inc.",
    "1998-2004 David Turner and Werner Lemberg",
    "2016 Igalia S.L.",
    "2016 Elie Roux <elie.roux@telecom-bretagne.eu>",
    "2018,2019 Adobe Inc.",
    "2018,2021 Khaled Hosny",
    "2012 Grigori Goronzy <greg@kinoho.net>",
    "Microsoft Corporation",
    "2022 Unicode, Inc.",
  ],
  license: ["MIT-Modern-Variant", "MIT", "ISC", "Unicode-DFS-2016"],
  title: "HarfBuzz",
  version: "6.0.0"

# libvorbis 1.3.7 (Resources/Info.plist; its headers are byte for byte
# the v1.3.7 tag's, https://github.com/xiph/vorbis), which love.sound's Ogg
# Vorbis decoder links (src/modules/sound/lullaby/VorbisDecoder.h), built
# by its own Xcode project, macosx/Vorbis.xcodeproj, whose framework target
# compiles every file of lib but the tools barkmel.c, misc.c, psytune.c,
# and tone.c: libvorbis, libvorbisenc, and libvorbisfile in one, from the
# files the Linux libraries are built from, so it is recorded as they
# are. Each file points to COPYING, BSD-3-Clause (lib/vorbisfile.c:1-11,
# and the same in each), and lib/lpc.c, whose vorbis_lpc_from_data the
# binary exports, keeps Jutta Degener's and Carsten Bormann's notice and
# terms for the code it derives from theirs (lines 17-43), the text of
# TU-Berlin-1.0.
framework "vorbis.framework",
  copyright: [
    "2002-2020 Xiph.org Foundation",
    "1994-2015 by the Xiph.Org Foundation",
    "1992, 1993, 1994 by Jutta Degener and Carsten Bormann, Technische Universitaet Berlin",
  ],
  license: ["BSD-3-Clause", "TU-Berlin-1.0"],
  title: "libvorbis",
  version: "1.3.7"

# libogg 1.3.4, which libvorbis loads. Its Resources/Info.plist says 1.1.4,
# as the macosx/Info.plist of libogg's own Xcode project said in every
# release from 1.1.4 to 1.3.4, the last that had it (commit b661e50
# removed it before 1.3.5). The library is no older: its slicing-by-8 CRC
# table (crc_lookup, 8 by 256 entries, and _os_update_crc), which commit
# bc82844 brought in 1.3.4, is in the binary, and Headers/ogg.h is byte
# for byte v1.3.4's; Headers/os_types.h is v1.3.4's but for including
# <stdint.h> where it included <sys/types.h> (line 73). That project's
# framework target compiles src/bitwise.c and src/framing.c, which with
# src/crctable.h and include/ogg point to the BSD-3-Clause text of COPYING
# (src/framing.c:1-11, and the same in each). framing.c:16-18 says its CRC
# code comes from Ross Williams's, in the public domain. The notice its
# Info.plist gives, which the gem carries, is recorded too.
framework "ogg.framework",
  copyright: ["2002, Xiph.org Foundation", "1994-2018 by the Xiph.Org Foundation", "1994-2009 Xiph.Org Foundation"],
  license: ["BSD-3-Clause"],
  title: "libogg",
  version: "1.3.4"

# libtheora 1.1, which love.video's Theora decoder links
# (src/modules/video/theora/TheoraVideoStream.h) and which loads libogg.
# Its binary names itself "Xiph.Org libtheora 1.1 20090822 (Thusnelda)",
# the vendor string of the 1.1.0 and 1.1.1 releases (lib/internal.h:75 in
# each), and its Headers are byte for byte both releases' include/theora;
# its Resources/Info.plist says 1.1alpha1svn, as macosx/Info.plist of
# libtheora's own Xcode project says in both. That project's framework
# target, Theora (macosx/Theora.xcodeproj), compiles every file of lib and
# lib/x86, the decoder and the encoder, which with include/theora point
# to COPYING, BSD-3-Clause with the Xiph.org Foundation's notice
# (lib/decode.c:1-11, and the same in each); lib/x86/mmxfdct.c and
# sse2fdct.c keep a notice of 1999-2006, and lib/bitpack.c and bitpack.h
# one of 1994-2009. Both releases' files state the same notices, read
# file by file in 1.1.1. Its LICENSE adds On2 Technologies' promise not
# to assert its VP3 patents against the software, which asks nothing of
# whoever redistributes it.
framework "theora.framework",
  copyright: [
    "2002-2009 Xiph.org Foundation",
    "2002-2009 by the Xiph.Org Foundation and contributors",
    "2002-2009 by the Xiph.Org Foundation",
    "1994-2009 by the Xiph.Org Foundation and contributors",
    "1999-2006 by the Xiph.Org Foundation",
  ],
  license: ["BSD-3-Clause"],
  title: "libtheora",
  version: "1.1"

# libmodplug, which love.sound's tracker module decoder links
# (src/modules/sound/lullaby/ModPlugDecoder.h), from no release: its
# Resources/Info.plist gives 1.0, an Xcode project's from 2011, but its
# Headers/modplug.h is byte for byte src/modplug.h as it was in
# https://github.com/Konstanty/libmodplug from commit d38e532 (2017-10-23)
# to commit e0ffc77 (2022-01-29), after 0.8.9.0, and love-apple-dependencies
# added the framework on 2021-05-30 (commit 687b788). Through those years
# no file's license or authors changed (the last commit before that day,
# e451f94, read for them), so it is recorded from them: its COPYING and
# each of its own files put it in the public domain (src/modplug.h:1-5),
# which no SPDX identifier names, so the two sentences are recorded as
# LicenseRef-libmodplug-Public-Domain; the authors its AUTHORS file lists
# and its files name (src/libmodplug/stdafx.h:1-7, and the UMX loader,
# src/load_umx.cpp:1-10, rewritten after 0.8.8.5); and the ABC, MIDI, and
# PAT loaders it took from the MikMod Sound System (src/load_abc.cpp:1-25,
# and the same in load_mid.cpp and load_pat.cpp; the binary carries
# their code, its "abc-include" strings and PAT_Load_Instruments), recorded
# as LicenseRef-libmodplug-MikMod, as on Linux.
framework "libmodplug.framework",
  copyright: [
    "Olivier Lapicque <olivierl@jps.net>",
    "Kenton Varda <temporal@gauge3d.org>",
    "Konstanty Bialkowski <konstanty@ieee.org>",
    "Colin DeVilbiss <crdevilb@mtu.edu>",
    "Markus Fick <marf@gmx.net>",
    "Adam Goode <adam@evdebs.org>",
    "Marco Trillo <toad@arsystel.com>",
    "Alistair John Strachan <s0348365@sms.ed.ac.uk>",
    "Tyler Montbriand <tsm@accesscomm.ca>",
    "Rani Assaf <rani@magic.metawire.com>",
    "O. Sezer <sezero@users.sourceforge.net>",
    "Andy Ward <wardwh@swbell.net>",
    "1996-2000 Jake Stine of Divine Entertainment",
    "2006 Peter Grootswagers <pgrootswagers@planet.nl>",
  ],
  license: ["LicenseRef-libmodplug-Public-Domain", "LicenseRef-libmodplug-MikMod"],
  title: "libmodplug"

# The release archive of OpenAL Soft 1.24.3, which the gem carries beside
# its library on every platform (the record's `source`, below and in the
# Linux section).
openal_soft_source = {
  url: "https://openal-soft.org/openal-releases/openal-soft-1.24.3.tar.bz2",
  sha256: "cb5e6197a1c0da0edcf2a81024953cc8fa8545c3b9474e48c852af709d587892",
  path: "vendor/sources/openal-soft-1.24.3.tar.bz2",
  copyright: [
    "1999-2000 by authors.",
    "1999-2007 by authors.",
    "1999-2010 by authors.",
    "2005 Boris Mikhaylov",
    "2006, Matthias Kretz, <kretz@kde.org>",
    "2008, Alexander Neundorf, <neundorf@kde.org>",
    "2008-2017 by Chris Robinson and Christopher Fitzgerald.",
    "2009 Lennart Poettering",
    "2009 by Chris Robinson.",
    "2009 by Konstantinos Natsakis <konstantinos.natsakis@gmail.com>",
    "2009-2011 Kitware, Inc.",
    "2009-2011 Philip Lowman <philip@yhbt.com>",
    "2010 David Henningsson <diwic@ubuntu.com>",
    "2010 by Chris Robinson",
    "2010 by Chris Robinson <chris.kcat@gmail.com>",
    "2011 The Android Open Source Project",
    "2011 by Chris Robinson",
    "2011 by Chris Robinson <chris.kcat@gmail.com>",
    "2011 by Chris Robinson.",
    "2011 by authors.",
    "2011, Michael Jansen, <kde@michael-jansen.biz>",
    "2011-2019 Christopher Fitzgerald",
    "2012 - 2016, Victor Zverovich",
    "2012 - present, Victor Zverovich",
    "2012 - present, Victor Zverovich and fmt contributors",
    "2012 - present, Victor Zverovich and {fmt} contributors",
    "2012 by Chris Robinson <chris.kcat@gmail.com>",
    "2013 Julien Pommier ( pommier@modartt.com )",
    "2013 Vladimir Keleshev, vladimir@keleshev.com",
    "2013 by Anis A. Hireche",
    "2013 by Chris Robinson <chris.kcat@gmail.com>",
    "2013 by Mike Gorchak",
    "2014 by Timothy Arceri <t_arceri@yahoo.com.au>.",
    "2015 by Chris Robinson <chris.kcat@gmail.com>",
    "2015, Archontis Politis",
    "2017 by Chris Robinson <chris.kcat@gmail.com>",
    "2018 - present, Victor Zverovich and fmt contributors",
    "2018 by Chris Robinson <chris.kcat@gmail.com>",
    "2018 by Raul Herraiz.",
    "2018 by authors.",
    "2018, Steffen Schümann <s.schuemann@pobox.com>",
    "2018-2019 Christopher Fitzgerald",
    "2019 Christopher Robinson",
    "2019 by Anis A. Hireche",
    "2019, Anis A. Hireche",
    "2019, Christopher Robinson",
    "2020 Jan Tojnar",
    "2020 by Chris Robinson <chris.kcat@gmail.com>",
    "2021 Chris Robinson",
    "2023 Christopher Robinson",
    "2024 by Chris Robinson <chris.kcat@gmail.com>",
    "2024 by authors.",
    "2004 the University Corporation for Atmospheric Research (\"UCAR\")",
    "2001-2012 Python Software Foundation",
    "1995-2001 Corporation for National Research Initiatives",
    "1991 - 1995, Stichting Mathematisch Centrum Amsterdam",
  ],
  license: [
    "LGPL-2.0-or-later",
    "GPL-2.0-or-later",
    "Apache-2.0",
    "BSD-3-Clause",
    "MIT",
    "LicenseRef-PFFFT",
    "Python-2.0",
  ],
}.freeze

# OpenAL Soft 1.24.3, which love.audio plays through
# (src/modules/audio/openal). Its binary names the version (the string
# "1.24.3" it reports, where Resources/Info.plist still says 1.19.1),
# love-apple-dependencies' commit 62a2b23 updated it to that release, and
# its headers are byte for byte the release's include/AL. Its licensing
# comes from the release's own files: COPYING, the GNU Library General
# Public License version 2, which the headers of the library's own files
# take "or (at your option) any later version" (alc/alc.cpp:1-19), and
# the files under other licenses that the macOS library compiles in:
# BSD-3-Clause for the parts BSD-3Clause names and for
# alc/effects/compressor.cpp and vmorpher.cpp (their lines 1-29); MIT for
# core/bs2b.cpp (lines 1-22), ghc::filesystem (common/filesystem.cpp and
# filesystem.h, lines 1-27), and the {fmt} library it links (fmt-11.1.1/
# LICENSE); and LICENSE-pffft for common/pffft.cpp, which no SPDX
# identifier names, so its text is recorded as LicenseRef-PFFFT. The
# backends for other systems (alc/backends/opensl.cpp, under Apache-2.0)
# and RTKit (core/rtkit.cpp, which needs D-Bus) are not compiled on macOS.
# What is compiled is CMakeLists.txt:609-916's sources, but for RTKit's
# and EAX's (ALSOFT_EAX is on only for Windows, line 122), with the only
# backends the binary names, CoreAudio and the wave writer, and {fmt}'s
# src/format.cc and os.cc; core/helpers.cpp includes core/rtkit.h only
# where HAVE_RTKIT (line 221), which macOS lacks. LÖVE's
# license.txt:124-157 lists this mixed licensing for an older release,
# from Debian's record. The notices are each one these files hold.
#
# Its license lets object code of the library be copied only with its
# complete corresponding source code (section 4), so the precompiled gem
# carries the release's own source archive beside it, as `source` records:
# where it comes from, its SHA-256, which the release's asset on GitHub
# also gives, and where `rake sources:fetch` keeps it (vendor/sources,
# which git ignores), from which the gem build copies it into the gem's
# sources/, after checking it. The archive holds more than the library
# compiles: utilities under GPL-2.0-or-later (utils/makemhr and
# utils/sofa-*.cpp), the Android backend under Apache-2.0, examples and
# CMake modules under MIT and BSD-3-Clause, and {fmt}'s documentation of
# Python's license (fmt-11.1.1/doc/python-license.txt, Python-2.0), so
# its record names every license and notice in it. The bundle links the
# framework as LÖVE's own macOS build does, a library apart, which a
# player can replace.
framework "OpenAL-Soft.framework",
  copyright: [
    "1999-2000 by authors.",
    "1999-2007 by authors.",
    "1999-2010 by authors.",
    "2005 Boris Mikhaylov",
    "2008-2017 by Chris Robinson and Christopher Fitzgerald.",
    "2009 by Chris Robinson.",
    "2010 by Chris Robinson",
    "2011 by Chris Robinson",
    "2011 by Chris Robinson.",
    "2012 - 2016, Victor Zverovich",
    "2012 - present, Victor Zverovich",
    "2012 - present, Victor Zverovich and fmt contributors",
    "2012 - present, Victor Zverovich and {fmt} contributors",
    "2013 Julien Pommier ( pommier@modartt.com )",
    "2013 by Anis A. Hireche",
    "2013 by Mike Gorchak",
    "2014 by Timothy Arceri <t_arceri@yahoo.com.au>.",
    "2015, Archontis Politis",
    "2018 - present, Victor Zverovich and fmt contributors",
    "2018 by Raul Herraiz.",
    "2018, Steffen Schümann <s.schuemann@pobox.com>",
    "2019 by Anis A. Hireche",
    "2019, Christopher Robinson",
    "2023 Christopher Robinson",
    "2004 the University Corporation for Atmospheric Research (\"UCAR\")",
  ],
  license: ["LGPL-2.0-or-later", "BSD-3-Clause", "MIT", "LicenseRef-PFFFT"],
  source: openal_soft_source,
  title: "OpenAL Soft",
  version: "1.24.3"

# Linux. The libraries the gem carries in lib/lota/libraries, which
# love-appimage-source's Makefile builds from each release's source, at
# the versions it names (vendor/love-appimage-source/Makefile:17-30), as
# LÖVE's own Linux CI builds them (tasks/linux_build.rb). Each one's
# licensing comes from the files it compiles, as its build's dependency
# files list them (the CMake builds' .o.d and the Autotools builds' .Plo),
# read for every license and notice of copyright they state, and from the
# license files at the root of its source.

# SDL 3.4.10 (the Makefile's SDL3_BRANCH, tag release-3.4.10, commit
# 8e37db5e797b6167f3a00d697d816a684bd259c7), under its own license,
# LICENSE.txt:1-17, which every file of SDL's own states (src/SDL.c:1-20),
# with the code of others that the Linux build compiles in, each under the
# license its files state:
#
# - BSD-3-Clause: yuv2rgb (src/video/yuv2rgb/LICENSE), and HIDAPI, which
#   offers GPL-3.0, a BSD-style license, or its original license, at the
#   user's choice (src/hidapi/LICENSE.txt and src/hidapi/linux/hid.c:1-21);
#   Lota uses it under the BSD-style one, src/hidapi/LICENSE-bsd.txt, as
#   on macOS.
# - MIT: the Wayland protocols, as wayland-scanner copies each protocol's
#   notice into the code it generates from SDL's wayland-protocols/*.xml;
#   src/events/imKStoUCS.c:1-25 (from X.Org); src/video/x11/edid-parse.c:1-21
#   and src/filesystem/unix/SDL_sysfilesystem.c:338-364 (Red Hat's);
#   include/SDL3/SDL_opengl.h (Mesa's); and include/SDL3/SDL_opengl_glext.h
#   and SDL_egl.h (the Khronos Group's).
# - MIT OR Unlicense: stb_image, src/video/stb_image.h, which offers either,
#   recorded as LÖVE's own copy is.
# - HPND-sell-variant: src/video/x11/xsettings-client.c:1-23, and the
#   text-input-unstable-v3 protocol (wayland-protocols/
#   text-input-unstable-v3.xml:4-30).
# - SunPro: src/libm (src/libm/e_atan2.c:2-11, and the same in each).
# - Apache-2.0: the Khronos Group's Vulkan headers, src/video/khronos/
#   vulkan and vk_video, each of which names Apache-2.0 in its SPDX tag
#   (vulkan/vulkan_core.h:4-8).
# - Unlicense: miniz, src/video/miniz.h:1-3 and 5074-5099.
# - LicenseRef-SDL-libm-Public-Domain: src/libm/s_isinf.c and s_isinff.c,
#   whose header puts them in the public domain in a sentence no SPDX
#   identifier names, recorded with its authors.
#
# src/stdlib/SDL_malloc.c and SDL_strtokr.c are compiled, but the dlmalloc
# and PDCLib code they hold under CC0 is not, since the build's
# SDL_build_config.h defines HAVE_MALLOC and HAVE_STRTOK_R (lines 74 and
# 107), as on macOS. Nor are SDL's own OpenGL ES headers:
# include/SDL3/SDL_opengles2.h:34-36 includes the system's instead. Its
# other files without a notice of their own, such as the shaders SDL
# generates (src/render/vulkan) and the pointer-gestures protocol, are
# SDL's, under its license, as Collabora's are: the function
# src/video/SDL_surface.c:2759 contributes under it, and
# src/core/linux/SDL_evdev_capabilities.c, whose header (lines 1-21) is
# SDL's with Collabora's notice added.
library "libSDL3.so.0",
  copyright: [
    "1997-2026 Sam Lantinga <slouken@libsdl.org>",
    "1998-2021 Gareth McCaughan",
    "2001-2011 Andreas Schiffler",
    "2017, Mark Callow",
    "2020 Collabora Ltd.",
    "2023 Collabora Ltd.",
    "2020 Valve Corporation",
    "2021 Valve Corporation",
    "Valve Corporation",
    "2021 NVIDIA Corporation",
    "2023 Max Maisel <max.maisel@posteo.de>",
    "2024 Igalia S.L.",
    "2024 Wim Taymans <wtaymans@redhat.com>",
    "2025 Bernat Arlandis <berarma@hotmail.com>",
    "2025 Katharine Chui <katharine.chui@gmail.com>",
    "2025 Michal Malý <madcatxster@devoid-pointer.net>",
    "2025 Mitchell Cairns <mitch.cairns@handheldlegend.com>",
    "2025 Simon Wood <simon@mungewell.org>",
    "2025 Zuiki Inc.",
    "2016, Adrien Descamps",
    "2009, Alan Ott, Signal 11 Software",
    "2010, Alan Ott, Signal 11 Software",
    "2022-2023 Alan Ott, Signal 11 Software, and the libusb/hidapi Team",
    "2003-2006,2008 Jamey Sharp, Josh Triplett",
    "2009 Red Hat, Inc.",
    "1990-1992,1999,2000,2004,2009,2010 Oracle and/or its affiliates.",
    "2007 Red Hat, Inc.",
    "2001, 2007 Red Hat, Inc.",
    "1999-2006 Brian Paul",
    "2009 VMware, Inc.",
    "2007-2020 The Khronos Group Inc.",
    "2008-2018 The Khronos Group Inc.",
    "2013-2020 The Khronos Group Inc.",
    "2014-2024 The Khronos Group Inc.",
    "2015-2024 The Khronos Group Inc.",
    "2017 Sean Barrett",
    "1993 by Sun Microsystems, Inc.",
    "2010-2013 Rich Geldreich <richgel99@gmail.com>",
    "J.T. Conklin <jtc@netbsd.org>",
    "Ulrich Drepper <drepper@cygnus.com>",
    "2008-2011 Kristian Høgsberg",
    "2008-2013 Kristian Høgsberg",
    "2010-2011 Intel Corporation",
    "2010-2013 Intel Corporation",
    "2012, 2013 Intel Corporation",
    "2012-2013 Collabora, Ltd.",
    "2013-2016 Collabora, Ltd.",
    "2017 Collabora, Ltd.",
    "2020-2024 Collabora, Ltd.",
    "2013 Jasper St. Pierre",
    "2013 Rafael Antognolli",
    "2014 Jonas Ådahl",
    "2014 Stephen \"Lyude\" Chandler Paul",
    "2015, 2016 Jan Arne Petersen",
    "2015, 2016 Red Hat",
    "2015 Red Hat Inc.",
    "2015-2016 Red Hat Inc.",
    "2015-2016 Red Hat, Inc.",
    "2015-2017 Red Hat Inc.",
    "2017 Red Hat Inc.",
    "2017, 2018 Red Hat, Inc.",
    "2022-2025 Red Hat, Inc.",
    "2015 Samsung Electronics Co., Ltd",
    "2015-2017 Samsung Electronics Co., Ltd",
    "2018 Purism SPC",
    "2018 Simon Ser",
    "2023 Simon Ser",
    "2018 The Chromium Authors",
    "2019 Erwin Burema",
    "2019 Sebastian Wick",
    "2020 AMD",
    "2020 Aleix Pol Gonzalez <aleixpol@kde.org>",
    "2020 Carlos Garnacho <carlosg@gnome.org>",
    "2023 Carlos Garnacho",
    "2022 Kenny Levinsen",
    "2023 Joshua Ashton for Valve Software",
    "2023 Xaver Hugl",
    "2024 Xaver Hugl",
    "2023-2024 Matthias Klumpp",
    "2024 Matthias Klumpp",
    "2024 David Edmundson",
    "2024 Neal Gompa",
    "2024 Vlad Zahorodnii",
  ],
  license: [
    "Zlib",
    "BSD-3-Clause",
    "MIT",
    "HPND-sell-variant",
    "SunPro",
    "Apache-2.0",
    "Unlicense",
    "MIT OR Unlicense",
    "LicenseRef-SDL-libm-Public-Domain",
  ],
  title: "SDL",
  version: "3.4.10"

# FreeType 2.13.3 (the Makefile's FT_VERSION), which offers the FreeType
# License or GPL-2.0 (LICENSE.TXT); Lota uses it under the FreeType License
# (docs/FTL.TXT), as on macOS, Adobe's CFF engine in src/psaux included
# (src/psaux/psft.c:1-36, which puts it under the FreeType License). The
# build compiles every module (its ftmodule.h): the BDF and PCF drivers
# and src/base/fthash.c under MIT (src/bdf/README, src/pcf/README, and
# fthash.c:9-31), src/pcf/pcfutil.c under the Open Group's license (lines
# 1-25, MIT-open-group), and src/autofit/ft-hb.c under HarfBuzz's
# (lines 1-25, MIT-Modern-Variant). It links the zlib the gem carries
# (FT_CONFIG_OPTION_SYSTEM_ZLIB in its ftoption.h), and libbz2 1.0.8, the
# Makefile's BZIP2_VERSION, which it compiles in: bzip2's LICENSE:1-42,
# whose text is bzip2-1.0.6's. src/base/ftobjs.c includes src/base/md5.c
# only under FT_DEBUG_LEVEL_TRACE (lines 50-77), and src/dlg/dlgwrap.c
# includes dlg.c only under FT_DEBUG_LOGGING (lines 23-27), neither of
# which the build's ftoption.h defines (lines 434 and 451), so neither
# file is compiled in.
library "libfreetype.so.6",
  copyright: [
    "1996-2024 David Turner, Robert Wilhelm, and Werner Lemberg",
    "2006-2014 Adobe Systems Incorporated",
    "2003 Huw D M Davies for Codeweavers",
    "2007 Dmitry Timoshkov for Codeweavers",
    "2000 Computing Research Labs, New Mexico State University",
    "2000 Francesco Zappa Nardelli",
    "2001-2002, 2011 Francesco Zappa Nardelli",
    "2001-2015 Francesco Zappa Nardelli",
    "1990, 1994, 1998 The Open Group",
    "2015 Google, Inc.",
    "2009, 2023 Red Hat, Inc.",
    "1996-2019 Julian Seward <jseward@acm.org>",
  ],
  license: ["FTL", "MIT", "MIT-open-group", "MIT-Modern-Variant", "bzip2-1.0.6"],
  title: "FreeType",
  version: "2.13.3",
  credit: freetype_credit.call(2024)

# HarfBuzz 10.1.0 (the Makefile's HARFBUZZ_BRANCH, tag 10.1.0, commit
# 9ef44a2d67ac870c1f7f671f6dc98d08a2579865), which compiles everything in
# one file, src/harfbuzz.cc: COPYING:1-42, the "Old MIT" text
# (MIT-Modern-Variant), which its files state (src/hb.hh:1-27, and the
# same in each); src/ms-use/COPYING, which covers the Universal Shaping
# Engine's data the library compiles in, MIT; the fasthash it borrows,
# MIT (src/hb-algs.hh:261-284); src/hb-ucd.cc:1-15, under ISC; and the
# Unicode Character Database's data its tables are generated from
# (src/hb-unicode-emoji-table.hh:8-19), under the Unicode License v3. The
# FreeType headers it includes are FreeType's, recorded with it.
library "libharfbuzz.so",
  copyright: [
    "2010-2022 Google, Inc.",
    "2015-2020 Ebrahim Byagowi",
    "2019,2020 Facebook, Inc.",
    "2012,2015 Mozilla Foundation",
    "2011 Codethink Limited",
    "2008,2010 Nokia Corporation and/or its subsidiary(-ies)",
    "2009 Keith Stribley",
    "2011 Martin Hosken and SIL International",
    "2007 Chris Wilson",
    "2005,2006,2020,2021,2022,2023 Behdad Esfahbod",
    "2004,2007,2008,2009,2010,2013,2021,2022,2023 Red Hat, Inc.",
    "1998-2005 David Turner and Werner Lemberg",
    "2016 Igalia S.L.",
    "2022 Matthias Clasen",
    "2018,2021 Khaled Hosny",
    "2018,2019,2020 Adobe, Inc",
    "2013-2015 Alexei Podtelezhnikov",
    "2016 Elie Roux <elie.roux@telecom-bretagne.eu>",
    "2012 Grigori Goronzy <greg@kinoho.net>",
    "2012 Zilong Tan (eric.zltan@gmail.com)",
    "Microsoft Corporation",
    "2024 Unicode, Inc.",
  ],
  license: ["MIT-Modern-Variant", "MIT", "ISC", "Unicode-3.0"],
  title: "HarfBuzz",
  version: "10.1.0"

# OpenAL Soft 1.24.3 (the Makefile's OPENAL_BRANCH, tag 1.24.3, commit
# dc7d7054a5b4f3bec1dc23a42fd616a0847af948, whose files are the release
# archive's, byte for byte), recorded as on macOS, with what the Linux
# build compiles besides: the ALSA, OSS, PulseAudio, PipeWire, and JACK
# backends (alc/backends/pulseaudio.cpp:1-20, the library's own license),
# and RTKit's client, core/rtkit.cpp:1-27, under MIT. Its license, the GNU
# Library General Public License, asks for its source with its object code,
# so the gem carries the release's archive beside it, as on macOS, and the
# bundle links it as LÖVE's Linux build does, a library apart, which a
# player can replace.
library "libopenal.so.1",
  copyright: [
    "1999-2000 by authors.",
    "1999-2007 by authors.",
    "1999-2010 by authors.",
    "2005 Boris Mikhaylov",
    "2008-2017 by Chris Robinson and Christopher Fitzgerald.",
    "2009 by Chris Robinson.",
    "2009 by Konstantinos Natsakis <konstantinos.natsakis@gmail.com>",
    "2009 Lennart Poettering",
    "2010 David Henningsson <diwic@ubuntu.com>",
    "2010 by Chris Robinson",
    "2010 by Chris Robinson <chris.kcat@gmail.com>",
    "2011 by Chris Robinson",
    "2011 by Chris Robinson.",
    "2012 - present, Victor Zverovich",
    "2012 - present, Victor Zverovich and {fmt} contributors",
    "2013 Julien Pommier ( pommier@modartt.com )",
    "2013 by Anis A. Hireche",
    "2013 by Mike Gorchak",
    "2015, Archontis Politis",
    "2018 by Raul Herraiz.",
    "2018, Steffen Schümann <s.schuemann@pobox.com>",
    "2019 by Anis A. Hireche",
    "2019, Christopher Robinson",
    "2021 Chris Robinson",
    "2023 Christopher Robinson",
    "2004 the University Corporation for Atmospheric Research (\"UCAR\")",
  ],
  license: ["LGPL-2.0-or-later", "BSD-3-Clause", "MIT", "LicenseRef-PFFFT"],
  source: openal_soft_source,
  title: "OpenAL Soft",
  version: "1.24.3"

# libmodplug 0.8.8.5 (the Makefile's LIBMODPLUG_VERSION): its COPYING puts
# it in the public domain, as each of its own files does
# (src/modplug.h:1-5), recorded as on macOS; the authors its AUTHORS file
# lists, Tyler Montbriand among them since the macOS framework's; and the
# ABC, MIDI, and PAT loaders it took from the MikMod Sound System
# (src/load_abc.cpp:1-25, and the same in load_mid.cpp and load_pat.cpp),
# whose grant of rights no SPDX identifier names, so its text is recorded
# as LicenseRef-libmodplug-MikMod.
library "libmodplug.so.1",
  copyright: [
    "Olivier Lapicque <olivierl@jps.net>",
    "Kenton Varda <temporal@gauge3d.org>",
    "Konstanty Bialkowski <konstanty@ieee.org>",
    "Colin DeVilbiss <crdevilb@mtu.edu>",
    "Markus Fick <marf@gmx.net>",
    "Adam Goode <adam@evdebs.org>",
    "Marco Trillo <toad@arsystel.com>",
    "Alistair John Strachan <s0348365@sms.ed.ac.uk>",
    "Tyler Montbriand <tsm@accesscomm.ca>",
    "1996-2000 Jake Stine of Divine Entertainment",
    "2006 Peter Grootswagers <pgrootswagers@planet.nl>",
  ],
  license: ["LicenseRef-libmodplug-Public-Domain", "LicenseRef-libmodplug-MikMod"],
  title: "libmodplug",
  version: "0.8.8.5"

# libvorbisfile and libvorbis, from libvorbis 1.3.7 (the Makefile's
# LIBVORBIS_VERSION): its COPYING, BSD-3-Clause, which its files point to
# (lib/vorbisfile.c:1-11, and the same in each). libvorbis also compiles
# lib/lpc.c, which keeps Jutta Degener's and Carsten Bormann's notice and
# terms for the code it derives from theirs (lines 17-43), the text of
# TU-Berlin-1.0.
library "libvorbisfile.so.3",
  copyright: ["2002-2020 Xiph.org Foundation", "1994-2015 by the Xiph.Org Foundation"],
  license: ["BSD-3-Clause"],
  title: "libvorbisfile",
  version: "1.3.7"

library "libvorbis.so.0",
  copyright: [
    "2002-2020 Xiph.org Foundation",
    "1994-2015 by the Xiph.Org Foundation",
    "1992, 1993, 1994 by Jutta Degener and Carsten Bormann, Technische Universitaet Berlin",
  ],
  license: ["BSD-3-Clause", "TU-Berlin-1.0"],
  title: "libvorbis",
  version: "1.3.7"

# libogg 1.3.5 (the Makefile's LIBOGG_VERSION), which libvorbis needs: its
# COPYING, BSD-3-Clause, which the files it compiles point to
# (src/framing.c:1-11, and the same in src/bitwise.c, src/crctable.h,
# include/ogg/ogg.h, and include/ogg/os_types.h), each with its notice.
library "libogg.so.0",
  copyright: [
    "2002, Xiph.org Foundation",
    "1994-2018 by the Xiph.Org Foundation",
    "1994-2014 by the Xiph.Org Foundation",
    "1994-2007 by the Xiph.Org Foundation",
    "1994-2002 by the Xiph.Org Foundation",
  ],
  license: ["BSD-3-Clause"],
  title: "libogg",
  version: "1.3.5"

# libtheoradec, from libtheora 1.2.0 (the Makefile's LIBTHEORA_VERSION),
# which love.video's Theora decoder links, configured with
# --disable-encode, as the Makefile builds it: the decoder's files of lib
# (lib/Makefile.am, decoder_sources), with lib/x86's on x86_64, and the
# headers they include, as their Autotools dependency files list them,
# each pointing to COPYING, BSD-3-Clause with the Xiph.org Foundation's
# notice (lib/decode.c:1-11, and the same in each). lib/bitpack.c and
# bitpack.h keep a notice of 1994-2009, and decode.c, huffdec.c, state.c,
# state.h, and lib/x86's mmxfrag.c, mmxidct.c, and sse2idct.c one of
# 2002-2009,2025. Its LICENSE adds On2 Technologies' promise not to assert
# its VP3 patents against the software, which asks nothing of whoever
# redistributes it.
library "libtheoradec.so.2",
  copyright: [
    "2002-2009 Xiph.org Foundation",
    "2002-2009 by the Xiph.Org Foundation and contributors",
    "2002-2009,2025 by the Xiph.Org Foundation and contributors",
    "2002-2009 by the Xiph.Org Foundation",
    "1994-2009 by the Xiph.Org Foundation and contributors",
  ],
  license: ["BSD-3-Clause"],
  title: "libtheoradec",
  version: "1.2.0"

# zlib 1.3 (the Makefile's ZLIB_BRANCH, tag v1.3, commit
# 09155eaa2f9270dc4ed1fa13e2b4b2613e6e4851), which LÖVE and FreeType link:
# the notice and license of zlib.h:1-29, which every file of it points to
# (adler32.c:1-4, and the same in each), the zlib License's text.
library "libz.so.1",
  copyright: ["1995-2023 Jean-loup Gailly and Mark Adler"],
  license: ["Zlib"],
  title: "zlib",
  version: "1.3"

# Windows. The DLLs the gem carries in lib/lota/libraries, SDL's and
# OpenAL Soft's, which tasks/windows_build.rb builds from each release's
# source archive; every other library LÖVE links compiles into the bundle
# there.
#
# SDL 3.4.10 as SDL3.dll, the DLL LÖVE's Windows build ships, under its
# own license, as on Linux and macOS, with the code of others the Windows
# build compiles in, each under the license its files state:
#
# - BSD-3-Clause: yuv2rgb (src/video/yuv2rgb/LICENSE), and HIDAPI's
#   Windows backend, src/hidapi/windows/hid.c (lines 1-21) and the files
#   beside it, which offer GPL-3.0, a BSD-style license, or HIDAPI's
#   original license, at the user's choice; Lota uses it under the
#   BSD-style one, src/hidapi/LICENSE-bsd.txt, as on Linux and macOS.
# - MIT: Microsoft's Direct3D 12 headers, src/video/directx/d3d12.h and
#   d3d12sdklayers.h (lines 1-6 of each), which the GPU and render
#   modules' Direct3D 12 code compiles in; src/events/imKStoUCS.c:1-25
#   (from X.Org); include/SDL3/SDL_opengl.h (Mesa's); and
#   include/SDL3/SDL_opengl_glext.h, SDL_egl.h, and src/video/khronos/
#   GLES2/gl2.h and gl2ext.h (the Khronos Group's).
# - Apache-2.0: the Khronos Group's EGL and Vulkan headers,
#   src/video/khronos/EGL, vulkan, and vk_video (vulkan/vulkan_core.h:4-8),
#   and GLES2/gl2platform.h.
# - MIT OR Unlicense: stb_image, src/video/stb_image.h, as on Linux.
# - Unlicense: miniz, src/video/miniz.h:5074-5099.
# - SunPro: src/libm (src/libm/e_atan2.c:2-11, and the same in each).
# - LicenseRef-SDL-libm-Public-Domain: src/libm/s_isinf.c and s_isinff.c,
#   as on Linux.
#
# src/stdlib/SDL_malloc.c and SDL_strtokr.c are compiled, but the dlmalloc
# and PDCLib code they hold under CC0 is not, since SDL's CMake finds
# MinGW's malloc and strtok_r (CMakeLists.txt:1078-1097): its
# SDL_malloc.c.obj calls malloc, and its SDL_strtokr.c.obj strtok_r, as
# nm lists them. The Direct3D shaders SDL generates (src/gpu/d3d12 and
# src/render/direct3d*) state no notice of their own, so are SDL's, under
# its license. None of the X11 or Wayland code compiles on Windows, so
# neither their notices nor HPND-sell-variant are recorded. These are the
# files the x64 build compiles; the ARM64 build compiles the same but for
# the SSE code of yuv2rgb, so one record covers both.
library "SDL3.dll",
  copyright: [
    "1997-2026 Sam Lantinga <slouken@libsdl.org>",
    "1998-2021 Gareth McCaughan",
    "2001-2011 Andreas Schiffler",
    "2017, Mark Callow",
    "2023 Collabora Ltd.",
    "2020 Valve Corporation",
    "2021 Valve Corporation",
    "Valve Corporation",
    "2023 Max Maisel <max.maisel@posteo.de>",
    "2025 Bernat Arlandis <berarma@hotmail.com>",
    "2025 Katharine Chui <katharine.chui@gmail.com>",
    "2025 Michal Malý <madcatxster@devoid-pointer.net>",
    "2025 Mitchell Cairns <mitch.cairns@handheldlegend.com>",
    "2025 Simon Wood <simon@mungewell.org>",
    "2025 Zuiki Inc.",
    "2016, Adrien Descamps",
    "2009, Alan Ott, Signal 11 Software",
    "2022-2023 Alan Ott, Signal 11 Software, and the libusb/hidapi Team",
    "Microsoft Corporation",
    "2003-2006,2008 Jamey Sharp, Josh Triplett",
    "1990-1992,1999,2000,2004,2009,2010 Oracle and/or its affiliates.",
    "2009 Red Hat, Inc.",
    "1999-2006 Brian Paul",
    "2009 VMware, Inc.",
    "2007-2020 The Khronos Group Inc.",
    "2008-2018 The Khronos Group Inc.",
    "2013-2020 The Khronos Group Inc.",
    "2014-2024 The Khronos Group Inc.",
    "2015-2024 The Khronos Group Inc.",
    "2017-2020 The Khronos Group Inc.",
    "2017 Sean Barrett",
    "1993 by Sun Microsystems, Inc.",
    "2010-2013 Rich Geldreich <richgel99@gmail.com>",
    "J.T. Conklin <jtc@netbsd.org>",
    "Ulrich Drepper <drepper@cygnus.com>",
  ],
  license: [
    "Zlib",
    "BSD-3-Clause",
    "MIT",
    "Apache-2.0",
    "Unlicense",
    "MIT OR Unlicense",
    "SunPro",
    "LicenseRef-SDL-libm-Public-Domain",
  ],
  title: "SDL",
  version: "3.4.10"

# OpenAL Soft 1.24.3, from the release archive the gem carries as its
# source on every platform (openal_soft_source), recorded as on macOS and
# Linux, from the files the Windows build compiles, as its ninja
# dependency log lists them (the notices step of the windows-build job,
# .github/workflows/ci.yml), read whole for every notice and license they
# state: with the WASAPI, DirectSound, and Windows Multimedia backends
# (alc/backends/wasapi.cpp:1-20, dsound.cpp and winmm.cpp the same), under
# the library's own license, and EAX (al/eax), which ALSOFT_EAX turns on
# for Windows alone (CMakeLists.txt:122) and whose files state no notice of
# their own, so are the library's under its license; and {fmt}'s chrono.h,
# whose safe_duration_cast keeps Paul Dreik's notice (fmt-11.1.1/include/
# fmt/chrono.h:47-53) under {fmt}'s MIT license. None of the Linux
# backends, nor RTKit, compile. It links its compiler's runtime statically
# (ALSOFT_STATIC_LIBGCC, ALSOFT_STATIC_STDCXX, and with GCC
# ALSOFT_STATIC_WINPTHREAD), so with GCC it carries mingw-w64's
# winpthreads, whose COPYING (mingw-w64-libraries/winpthreads/COPYING)
# is the MIT License with the mingw-w64 project's notice and, for the code
# it derives from Lockless Inc.'s, BSD-3-Clause with theirs. The bundle
# links it as LÖVE's Windows build does, a DLL apart, which a player can
# replace.
library "OpenAL32.dll",
  copyright: [
    "1999-2000 by authors.",
    "1999-2007 by authors.",
    "1999-2010 by authors.",
    "2005 Boris Mikhaylov",
    "2008-2017 by Chris Robinson and Christopher Fitzgerald.",
    "2009 by Chris Robinson.",
    "2010 by Chris Robinson",
    "2011 by Chris Robinson",
    "2011 by Chris Robinson.",
    "2011 by authors.",
    "2012 - 2016, Victor Zverovich",
    "2012 - present, Victor Zverovich",
    "2012 - present, Victor Zverovich and {fmt} contributors",
    "Paul Dreik 2019",
    "2013 Julien Pommier ( pommier@modartt.com )",
    "2013 by Anis A. Hireche",
    "2013 by Mike Gorchak",
    "2014 by Timothy Arceri <t_arceri@yahoo.com.au>.",
    "2015, Archontis Politis",
    "2018 by Raul Herraiz.",
    "2018, Steffen Schümann <s.schuemann@pobox.com>",
    "2019 by Anis A. Hireche",
    "2019, Christopher Robinson",
    "2023 Christopher Robinson",
    "2004 the University Corporation for Atmospheric Research (\"UCAR\")",
    "2011 mingw-w64 project",
    "2010 Lockless Inc.",
  ],
  license: ["LGPL-2.0-or-later", "BSD-3-Clause", "MIT", "LicenseRef-PFFFT"],
  source: openal_soft_source,
  title: "OpenAL Soft",
  version: "1.24.3"

# The libraries the Windows bundle links statically: every one LÖVE links
# but SDL and OpenAL Soft, from the archives tasks/windows_build.rb installs, at
# the releases the Linux gem carries, each built from its release's own
# source archive. The bundle takes the members it needs from each archive,
# as the linker's map lists them, so each archive the map names is
# recorded whole, from the files the Windows build compiles into it, as
# its ninja dependency log lists them (Autotools' dependency files for
# libmodplug), read for every license and notice of copyright they state.
windows_dependencies = "tmp/dependencies/installdir/lib"

# zlib, libogg, libtheoradec, libvorbis and libvorbisfile, libmodplug,
# and HarfBuzz compile the same files on Windows as on Linux, so they are
# recorded as there; libtheoradec compiles lib/x86's files on x64 and no
# others of its own on ARM64, which state the same notices. libvorbisenc,
# beside them in libvorbis's build, is not linked.
{
  "zlib" => ["libzlibstatic.a", "libz.so.1"],
  "libogg" => ["libogg.a", "libogg.so.0"],
  "libtheoradec" => ["libtheoradec.a", "libtheoradec.so.2"],
  "libvorbis" => ["libvorbis.a", "libvorbis.so.0"],
  "libvorbisfile" => ["libvorbisfile.a", "libvorbisfile.so.3"],
  "libmodplug" => ["libmodplug.a", "libmodplug.so.1"],
  "HarfBuzz" => ["libharfbuzz.a", "libharfbuzz.so"],
}.each do |name, (archive, linux)|
  recorded = framework_for(linux)
  work "#{name} (Windows)",
    platform: "Windows",
    sources: ["#{windows_dependencies}/#{archive}"],
    copyright: recorded.copyright,
    license: recorded.license,
    title: recorded.notice_name,
    version: recorded.version
end

# FreeType 2.13.3, recorded as on Linux but for bzip2, which
# tasks/windows_build.rb turns off (FT_DISABLE_BZIP2), as megasource's
# FreeType goes without, so src/bzip2/ftbzip2.c compiles to nothing and no
# code of bzip2's is compiled in. It links the zlib above.
work "FreeType (Windows)",
  platform: "Windows",
  sources: ["#{windows_dependencies}/libfreetype.a"],
  copyright: framework_for("libfreetype.so.6").copyright - ["1996-2019 Julian Seward <jseward@acm.org>"],
  license: framework_for("libfreetype.so.6").license - ["bzip2-1.0.6"],
  title: "FreeType",
  version: framework_for("libfreetype.so.6").version,
  credit: framework_for("libfreetype.so.6").credit

# iOS and iPadOS. No gem carries these: an app's extension is linked
# into the app by Fledge (`fledge build ios`, ext/lota/phone/ios.rb),
# with the static archives engine/dependencies_ios.cmake names, each
# thinned to arm64, from which the app's link takes the members it needs,
# as LÖVE's own iOS build links them. So they are recorded here for the app's
# notices, and nothing checks them against a link map yet.
#
# love-apple-dependencies' iOS archives come from the same releases as
# its macOS frameworks above, by their headers and version strings:
# FreeType 2.11 (Headers/freetype/freetype.h), HarfBuzz 6.0.0
# (hb-version.h), libvorbis 1.3.7 and libtheora 1.1 ("Xiph.Org libVorbis
# 1.3.7", "Xiph.Org libtheora 1.1 20090822" in each archive), libmodplug's
# modplug.h byte for byte the framework's, and libogg's ogg.h the
# framework's, with the os_types.h and config_types.h libogg's configure
# writes. So each is recorded as its framework is. Which files each
# archive compiles was not read file by file, as it was for the
# frameworks; FreeType's archive holds ftbzip2.o, whose bzip2 calls go to
# the system's libbz2, as the framework's do. Its libtheoradec.a, the
# decoder alone, is recorded as the framework is, whose decoder and
# encoder state the decoder's notices and one more.
{
  "FreeType" => ["freetype", "freetype.framework"],
  "HarfBuzz" => ["harfbuzz", "harfbuzz.framework"],
  "libvorbis" => ["vorbis", "vorbis.framework"],
  "libogg" => ["ogg", "ogg.framework"],
  "libtheora" => ["theora", "theora.framework"],
  "libmodplug" => ["modplug", "libmodplug.framework"],
}.each do |name, (xcframework, framework)|
  recorded = framework_for(framework)
  work "#{name} (iOS)",
    platform: "iOS",
    sources: ["vendor/love-apple-dependencies/iOS/libraries/#{xcframework}.xcframework/**"],
    copyright: recorded.copyright,
    license: recorded.license,
    title: recorded.notice_name,
    version: recorded.version,
    credit: recorded.credit
end

# SDL 3.4.10, LÖVE's version and the SDL3.framework's above, built static
# for each slice from its release archive by tasks/ios_build.rb, with
# SDL's own CMake build for iOS. It is recorded as the macOS framework
# is: SDL's license with the code of others an Apple build compiles in.
# The iOS build compiles UIKit's video, Core Audio's audio, Metal's GPU
# and renderer, OpenGL ES, and HIDAPI's iOS backend where macOS's compiles
# Cocoa's; their files were not read one by one.
work "SDL (iOS)",
  platform: "iOS",
  sources: ["tmp/ios/sdl3/**"],
  copyright: framework_for("SDL3.framework").copyright,
  license: framework_for("SDL3.framework").license,
  title: "SDL",
  version: "3.4.10"

# Android. No gem carries these yet: Fledge links an app's extension into
# the app's libfledgeext.so for each ABI (`fledge build android`,
# ext/lota/phone/android.rb), with the static archives
# engine/dependencies_android.cmake names, from which the link takes the
# members it needs, and carries the two shared libraries it links,
# libSDL3.so and libopenal.so, beside it, as LÖVE's own Android build
# links them. So they are recorded here for the app's notices, and nothing
# checks them against a link map yet. tasks/android_build.rb builds the
# releases the Windows and Linux gems carry, from the same archives, with
# the options the Windows build gives them (AndroidBuild::ARCHIVES is
# WindowsBuild::ARCHIVES), so each static archive is recorded as the
# Windows one is, with its name, version, and credit; which files each
# Android archive compiles was not read file by file.
android_dependencies = "tmp/android/deps/*/lib"
{
  "zlib" => ["libz.a", "libz.so.1"],
  "libogg" => ["libogg.a", "libogg.so.0"],
  "libtheoradec" => ["libtheoradec.a", "libtheoradec.so.2"],
  "libvorbis" => ["libvorbis.a", "libvorbis.so.0"],
  "libvorbisfile" => ["libvorbisfile.a", "libvorbisfile.so.3"],
  "libmodplug" => ["libmodplug.a", "libmodplug.so.1"],
  "HarfBuzz" => ["libharfbuzz.a", "libharfbuzz.so"],
}.each do |name, (archive, linux)|
  recorded = framework_for(linux)
  work "#{name} (Android)",
    platform: "Android",
    sources: ["#{android_dependencies}/#{archive}"],
    copyright: recorded.copyright,
    license: recorded.license,
    title: recorded.notice_name,
    version: recorded.version
end

# FreeType 2.13.3 without bzip2, as on Windows (FT_DISABLE_BZIP2).
work "FreeType (Android)",
  platform: "Android",
  sources: ["#{android_dependencies}/libfreetype.a"],
  copyright: framework_for("libfreetype.so.6").copyright - ["1996-2019 Julian Seward <jseward@acm.org>"],
  license: framework_for("libfreetype.so.6").license - ["bzip2-1.0.6"],
  title: "FreeType",
  version: framework_for("libfreetype.so.6").version,
  credit: framework_for("libfreetype.so.6").credit

# OpenAL Soft 1.24.3 as libopenal.so, the shared library LÖVE's Android
# build ships, which a player can replace and whose license asks for its
# source with its object code, as on every other platform, so its record
# names the release's archive. It is recorded as the Linux library is,
# with the backend Android compiles and Linux does not: OpenSL ES's,
# alc/backends/opensl.cpp, under the Apache License 2.0 with the Android
# Open Source Project's notice (lines 1-15). The notices of the Linux
# backends the Linux record keeps were not taken out, since the Android
# build's files were not read one by one.
library "libopenal.so",
  copyright: framework_for("libopenal.so.1").copyright + ["2011 The Android Open Source Project"],
  license: framework_for("libopenal.so.1").license + ["Apache-2.0"],
  source: openal_soft_source,
  title: "OpenAL Soft",
  version: "1.24.3"

# SDL as libSDL3.so, which tasks/android_build.rb builds shared from
# SDL 3.4.10's release, LÖVE's version, whose Java classes the Android
# host carries. It is recorded as the Linux library is: SDL's license
# with the code of others SDL compiles in. The Android build compiles
# SDL's Android video, audio, and HIDAPI backend where Linux's compiles
# X11's, Wayland's, and PipeWire's; their files were not read one by one.
library "libSDL3.so",
  copyright: framework_for("libSDL3.so.0").copyright,
  license: framework_for("libSDL3.so.0").license,
  title: "SDL",
  version: "3.4.10"

# What each phone's app links, for the notices rake ios:notices and rake
# android:notices write into a phone project (tasks/phone_notices.rb): the
# works of every platform, less those a phone leaves out, with the works
# recorded for that phone, and the libraries it ships as files of their
# own. No link map is read for a phone yet, so each phone carries what
# its desktop counterpart's bundle carries, as measured in the 0.2.2
# gems' manifests: the engine's source lists differ by one file
# (sources_ios.cmake has src/common/ios.mm where sources_macos.cmake has
# macos.mm; sources_android.cmake is sources_linux.cmake), and LÖVE turns
# Vulkan on for Windows, Linux, and Android and Metal for macOS and iOS
# (vendor/love/src/common/config.h:126-132), so iOS, as macOS, carries no
# Vulkan code, and Android, as Linux, carries all of it.
phone "iOS",
  extension: "the app's executable",
  without: ["Vulkan-Headers", "volk", "Vulkan Memory Allocator"]

phone "Android",
  extension: "libfledgeext.so",
  libraries: ["libopenal.so", "libSDL3.so"]
