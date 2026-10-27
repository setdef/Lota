// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_loopback: the parity harness's audio device (native_test/
// CMakeLists.txt). The harness loads it into both engines' processes, the
// reference love's and Lota's, with DYLD_INSERT_LIBRARIES, and it changes
// one thing there: the device OpenAL Soft gives LÖVE's audio module.
//
// LÖVE opens the system's default playback device with
// alcOpenDevice(nullptr) and a context on it with alcCreateContext
// (vendor/love/src/modules/audio/openal/Audio.cpp:131-146). A playback
// device mixes on a clock of its own: OpenAL Soft's wave file writer, which
// the rest of the tests play into (test/alsoft.conf), mixes whenever the
// wall clock says another 20 milliseconds have gone by (OpenAL Soft 1.24.3,
// alc/backends/wave.cpp, WaveBackend::mixerProc), so where a sound starts in
// its file depends on how fast the engine ran. This library interposes both
// calls (dyld's __interpose section), so that LÖVE gets an OpenAL Soft
// loopback device instead (ALC_SOFT_loopback), which mixes only when told
// to, and lota_loopback_render tells it to once a frame, from each side of
// the harness, for the frame's fixed dt. LÖVE's own code, and OpenAL Soft's
// mixer (DeviceBase::renderSamples, which the wave writer's thread and
// alcRenderSamplesSOFT both call), are the same as in any run; what changes
// is only when the mixer runs, which is now on game time.

#include <OpenAL-Soft/alc.h>
#include <OpenAL-Soft/alext.h>

#include <cmath>
#include <cstddef>
#include <cstdio>
#include <span>
#include <utility>
#include <vector>

namespace {

// The loopback device's format, which a loopback context must be given
// (alc.cpp, UpdateDeviceParams): OpenAL Soft's defaults for a playback
// device, and so the format of the wave writer's file, 32-bit float stereo
// (core/devformat.h:66 and 80) at 48 kHz (core/device.h:43).
constexpr ALCint rate = 48000;
constexpr int channels = 2;

// The loopback device this library opened in place of the playback device
// LÖVE asked for, or nullptr before LÖVE has opened one.
ALCdevice *&device() {
  static ALCdevice *opened = nullptr;
  return opened;
}

// The seconds of game time asked for so far, and the sample frames
// rendered for them.
double &seconds() {
  static double total = 0;
  return total;
}

long &rendered() {
  static long total = 0;
  return total;
}

// The file the mixed samples go to, +path+, opened at the first render;
// nullptr when it cannot be.
std::FILE *output(const char *path) {
  static std::FILE *file = path == nullptr ? nullptr : std::fopen(path, "wb");
  return file;
}

// alcOpenDevice, interposed: a loopback device, whatever device was asked
// for, as LÖVE asks for the default one.
ALCdevice *open_loopback(const ALCchar * /*name*/) noexcept {
  device() = alcLoopbackOpenDeviceSOFT(nullptr);
  return device();
}

// The attribute list +list+, a key and a value at a time up to the zero
// that ends it, as OpenAL takes one (alc.h, alcCreateContext).
std::span<const ALCint> attributes_of(const ALCint *list) {
  std::size_t length = 0;
  // NOLINTNEXTLINE(cppcoreguidelines-pro-bounds-pointer-arithmetic)
  while (list != nullptr && list[length] != 0) {
    length += 2;
  }
  return {list, length};
}

// alcCreateContext, interposed: the attributes LÖVE asks for
// (Audio::computeContextAttribs), with the loopback device's format added
// before the list's terminating zero, on the loopback device. Fails, as
// alcCreateContext fails, with nullptr, if the list cannot be copied.
ALCcontext *create_context(ALCdevice *target, const ALCint *attributes) noexcept {
  if (target == nullptr || target != device()) {
    return alcCreateContext(target, attributes);
  }
  try {
    const std::span<const ALCint> given = attributes_of(attributes);
    std::vector<ALCint> list(given.begin(), given.end());
    list.insert(list.end(), {
                                ALC_FORMAT_CHANNELS_SOFT,
                                ALC_STEREO_SOFT,
                                ALC_FORMAT_TYPE_SOFT,
                                ALC_FLOAT_SOFT,
                                ALC_FREQUENCY,
                                rate,
                                0,
                            });
    return alcCreateContext(target, list.data());
  } catch (...) {
    return nullptr;
  }
}

// One of dyld's interpose tuples (mach-o/dyld-interposing.h): where calls
// to the second function go instead.
template <typename Function> struct Interpose {
  Function *replacement;
  Function *replacee;
};

[[gnu::used,
  gnu::section("__DATA,__interpose")]] const Interpose<decltype(alcOpenDevice)> interpose_open{
    .replacement = &open_loopback,
    .replacee = &alcOpenDevice,
};
[[gnu::used,
  gnu::section("__DATA,__interpose")]] const Interpose<decltype(alcCreateContext)> interpose_create{
    .replacement = &create_context,
    .replacee = &alcCreateContext,
};

} // namespace

// Mixes +dt+ more seconds of game time on the loopback device and appends
// the samples to the file +path+, which the first call opens, as 32-bit
// float stereo frames at 48 kHz in the machine's byte order: as many
// sample frames as bring the total to the seconds asked for so far,
// rounded, so frames whose dt is not a whole number of samples still add
// up. The harness calls it once a frame, after the game's love.update,
// with the run's LOTA_LOOPBACK_FILE, through LuaJIT's FFI in LÖVE
// (test/parity/lua/conf.lua) and LotaNativeTest.render_loopback in Lota
// (test/parity/probe.rb). Returns how many sample frames it mixed, or -1
// when no loopback device is open, as when LÖVE's audio module is not, or
// the file cannot be written.
extern "C" __attribute__((visibility("default"))) long lota_loopback_render(const char *path,
                                                                            double dt) {
  std::FILE *file = output(path);
  if (device() == nullptr || file == nullptr) {
    return -1;
  }
  seconds() += dt;
  const long target = std::lround(seconds() * rate);
  const long count = target - rendered();
  if (count <= 0) {
    return 0;
  }
  try {
    std::vector<float> samples(static_cast<std::size_t>(count) * channels);
    alcRenderSamplesSOFT(device(), samples.data(), static_cast<ALCsizei>(count));
    rendered() = target;
    const std::size_t written = std::fwrite(samples.data(), sizeof(float) * channels,
                                            static_cast<std::size_t>(count), file);
    if (std::cmp_not_equal(written, count) || std::fflush(file) != 0) {
      return -1;
    }
  } catch (...) {
    return -1;
  }
  return count;
}
