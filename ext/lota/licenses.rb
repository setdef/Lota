# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
# `pending` names licensing the maintainer has yet to decide, for a work
# LÖVE compiles but the bundle does not carry yet. Should the bundle come
# to carry one, the gem records its copyright, names it in a comment, and
# leaves its license out until the decision is made.
#
# The bundle matches its files against these entries in order, so a
# library comes before LÖVE, whose own sources surround it.

# Lota's own C++ (LICENSE). Its ports of LÖVE's code are Zlib snippets,
# which LÖVE's entry covers.
work "Lota",
  sources: ["ext/lota/**"],
  copyright: ["2026 Kerrick Long <me@kerricklong.com>"],
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
  license: ["Zlib"]

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

# Wuff, the WAVE reader love.sound's WaveDecoder compiles in
# (src/modules/sound/lullaby/WaveDecoder.h). None of its files states a
# license or a notice of copyright (vendor/love/src/libraries/Wuff: wuff.h
# names it, "Wuff - A very basic WAVE reader", and nothing more), and
# LÖVE's license.txt, which lists the libraries LÖVE bundles, does not list
# it, so who wrote it and under which license is the maintainer's to find
# out.
work "Wuff",
  sources: ["vendor/love/src/libraries/Wuff/**"],
  copyright: [],
  pending: "no license or notice of copyright in its files, and none in LÖVE's license.txt"

# Noise1234, which LÖVE compiles but the bundle does not link yet: the
# bundle reads only its headers' declarations, so the gem does not carry
# it (noise1234/simplexnoise1234.h:1-12).
work "Noise1234",
  sources: ["vendor/love/src/libraries/noise1234/**"],
  copyright: ["2003-2011, Stefan Gustavson"],
  pending: "a dedication to the public domain (noise1234.h:4-7), which no SPDX identifier names"

# LÖVE's default font, Noto Sans 2.001, which
# vendor/love/src/modules/font/NotoSans-Regular.ttf.gzip.h embeds; the
# copyright and license are in the font's own name table (name IDs 0 and
# 13), and LÖVE's license.txt does not list it.
work "Noto Sans",
  sources: ["vendor/love/src/modules/font/NotoSans-Regular.ttf.gzip.h"],
  copyright: ["2019 Google Inc. All Rights Reserved."],
  license: ["OFL-1.1"]

# LÖVE's own sources (vendor/love/license.txt:6-9). Its bundled libraries
# in src/libraries are works of their own, above; one the list lacks
# stops the build.
work "LÖVE",
  sources: ["vendor/love/src/common/**", "vendor/love/src/modules/**"],
  copyright: ["2006-2026 LOVE Development Team"],
  license: ["Zlib"]

# SDL 3.4.10 (the framework's Resources/Info.plist): its own license,
# Resources/License.txt:1-17, and the only others SDL's source tree at
# release-3.4.10 carries: yuv2rgb's (src/video/yuv2rgb/LICENSE), and
# HIDAPI's, which offers GPL-3.0, a BSD-style license, or its original
# license, at the user's choice (src/hidapi/LICENSE.txt). Lota uses
# HIDAPI under the BSD-style one, src/hidapi/LICENSE-bsd.txt, whose text
# is BSD-3-Clause.
framework "SDL3.framework",
  copyright: [
    "1997-2026 Sam Lantinga <slouken@libsdl.org>",
    "2016, Adrien Descamps",
    "2010, Alan Ott, Signal 11 Software",
  ],
  license: ["Zlib", "BSD-3-Clause"]

# FreeType 2.11.1 (Headers/freetype.h:4741-4743), which offers the FreeType
# License or GPL-2.0; Lota uses it under the FreeType License (FreeType's
# LICENSE.TXT and docs/FTL.TXT at VER-2-11-1). The framework builds the
# BDF and PCF drivers, under MIT (src/bdf/README, src/pcf/README, and
# src/base/fthash.c), and links the system's zlib rather than the copy in
# src/gzip.
framework "freetype.framework",
  copyright: [
    "1996-2021 David Turner, Robert Wilhelm, and Werner Lemberg",
    "2000 Computing Research Labs, New Mexico State University",
    "2000 Francesco Zappa Nardelli",
    "2001-2002, 2011 Francesco Zappa Nardelli",
    "2001-2015 Francesco Zappa Nardelli",
  ],
  license: ["FTL", "MIT"]

# HarfBuzz 6.0.0 (Resources/Info.plist), COPYING:1-34 at its 6.0.0 tag, and
# src/ms-use/COPYING, which covers the Universal Shaping Engine's data the
# library compiles in.
framework "harfbuzz.framework",
  copyright: [
    "2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020 Google, Inc.",
    "2018,2019,2020 Ebrahim Byagowi",
    "2019,2020 Facebook, Inc.",
    "2012 Mozilla Foundation",
    "2011 Codethink Limited",
    "2008,2010 Nokia Corporation and/or its subsidiary(-ies)",
    "2009 Keith Stribley",
    "2009 Martin Hosken and SIL International",
    "2007 Chris Wilson",
    "2005,2006,2020,2021 Behdad Esfahbod",
    "2005 David Turner",
    "2004,2007,2008,2009,2010 Red Hat, Inc.",
    "1998-2004 David Turner and Werner Lemberg",
    "Microsoft Corporation",
  ],
  license: ["MIT-Modern-Variant", "MIT"]

# libvorbis 1.3.7 (Resources/Info.plist), which love.sound's Ogg Vorbis
# decoder links (src/modules/sound/lullaby/VorbisDecoder.h): its COPYING at
# the v1.3.7 tag (https://github.com/xiph/vorbis), the BSD-3-Clause text
# its headers point to (Headers/codec.h:1-10).
framework "vorbis.framework",
  copyright: ["2002-2020 Xiph.org Foundation"],
  license: ["BSD-3-Clause"]

# libogg 1.1.4 (Resources/Info.plist, whose NSHumanReadableCopyright gives
# its notice), which libvorbis loads: its COPYING at the v1.1.4 tag
# (https://github.com/xiph/ogg), the BSD-3-Clause text its headers point
# to (Headers/ogg.h:1-10).
framework "ogg.framework",
  copyright: ["1994-2009 Xiph.Org Foundation", "2002, Xiph.org Foundation"],
  license: ["BSD-3-Clause"]

# libmodplug, which love.sound's tracker module decoder links
# (src/modules/sound/lullaby/ModPlugDecoder.h). The framework names no
# version (Resources/Info.plist gives 1.0); its header dedicates it to the
# public domain (Headers/modplug.h:1-5), as libmodplug's COPYING does
# (https://github.com/Konstanty/libmodplug, master), which no SPDX
# identifier names, so the two sentences are recorded as
# LicenseRef-libmodplug-Public-Domain. Its files hold no notice of
# copyright; the record names its authors as its AUTHORS file lists them.
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
  ],
  license: ["LicenseRef-libmodplug-Public-Domain"]

# OpenAL Soft 1.24.3 (the version string in its binary; Resources/
# Info.plist says 1.19.1), which love.audio plays through
# (src/modules/audio/openal), is not here: the precompiled gem carries no
# copy of it, and Lota's bundle links it weakly, so that a bundle without
# it falls back to LÖVE's silent audio module, as LÖVE does when OpenAL
# cannot open a device (ext/lota/engine/CMakeLists.txt). Its license, the
# GNU Library General Public License 2.0 or later (COPYING and
# alc/alc.cpp:1-19 at its 1.24.3 tag, https://github.com/kcat/openal-soft),
# lets object code of the library be copied only with its complete
# corresponding source code, or with an offer to copy the source from the
# same place (section 4), and how the gem meets that is the maintainer's
# to decide.
