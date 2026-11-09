// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Rice roots the Ruby value each Rice::Object holds with Ruby's
// rb_gc_register_address, and lets it go with rb_gc_unregister_address
// (Rice 4.12.0, rice/rice.hpp:1675-1699, Anchor, its only calls to either).
// Ruby 4.0, to 4.0.9 at least, keeps those addresses in one linked list
// the whole VM shares, which both change without a lock (gc.c:3444-3488),
// so two Ractors that call into Lota::Native at once corrupt it: Ruby then
// crashes in rb_gc_unregister_address, in rb_vm_mark as it walks the list
// (vm.c:3313-3315), or freeing a node twice (test/native/ractor_test.rb).
// Ruby 4.1 locks the list (954094a910, "Take VM Lock during
// rb_gc_{un}register_address", written for Rice's Anchor) and keeps one
// for each Ractor (2ad6b99a98, Feature #22277); neither is in 4.0.
//
// A lock of Lota's own around Ruby's could not help: rb_gc_register_address
// allocates Ruby's memory, so a collection could start while one Ractor
// held the lock, and wait for another Ractor, which would wait for the lock
// with its GVL held. So the native target's compile definitions
// (native/CMakeLists.txt) rename every call the bundle makes, Rice's among
// them, to the two functions here, which on Ruby 4.0 keep the addresses in
// a set of Lota's, under a lock that guards only C++, and mark them from
// one hidden object, as Ruby marks its own list; on Ruby 4.1 they call
// Ruby's. This file, its header, the call in Init_native, and the
// definitions go when Lota requires Ruby 4.1.
//
// Every value Lota and Rice root this way is one of the rooting Ractor's
// own or a shareable one, as Ruby 4.1 asks (Feature #22277): a
// Rice::Object holds a value its Ractor passed or got back, and a
// ruby::Root a value the Ractor gave the engine, which no other Ractor
// reaches, since its owner is not shareable.

#include "native/rice_roots.hpp"

#include "native/binding.hpp"

#include <mutex>
#include <unordered_set>

#if RUBY_API_VERSION_CODE >= 40100

namespace lota::native {

void install_rice_roots() {}

} // namespace lota::native

#undef rb_gc_register_address
#undef rb_gc_unregister_address
extern "C" void rb_gc_register_address(VALUE *address);
extern "C" void rb_gc_unregister_address(VALUE *address);

extern "C" void lota_gc_register_address(VALUE *address) { rb_gc_register_address(address); }

extern "C" void lota_gc_unregister_address(VALUE *address) { rb_gc_unregister_address(address); }

#else

namespace lota::native {

namespace {

// The addresses rooted, and the hidden object that marks what they hold.
class RiceRoots {
public:
  // It is never destroyed, so a root that one of Rice's statics lets go of
  // as the process exits still finds it.
  static RiceRoots &instance() {
    static auto *const roots = new RiceRoots;
    return *roots;
  }

  RiceRoots(const RiceRoots &) = delete;
  RiceRoots(RiceRoots &&) = delete;
  RiceRoots &operator=(const RiceRoots &) = delete;
  RiceRoots &operator=(RiceRoots &&) = delete;
  ~RiceRoots() = default;

  void install() {
    if (installed_) {
      return;
    }
    rb_gc_register_mark_object(rb_data_typed_object_wrap(0, this, &TYPE));
    installed_ = true;
  }

  void root(const VALUE *address) {
    const std::scoped_lock lock(mutex_);
    addresses_.insert(address);
  }

  // Undoes one root(address). It allocates nothing, so it may run while
  // Ruby collects an object whose release lets a Rice::Object go.
  void forget(const VALUE *address) noexcept {
    const std::scoped_lock lock(mutex_);
    const auto found = addresses_.find(address);
    if (found != addresses_.end()) {
      addresses_.erase(found);
    }
  }

private:
  RiceRoots() = default;

  // Marks what each address holds, as Ruby marks the addresses
  // rb_gc_register_address roots, with rb_gc_mark_maybe (vm.c:3313-3315),
  // since Rice roots an address before it stores the value there.
  static void mark(void *data) {
    const auto *roots = static_cast<RiceRoots *>(data);
    const std::scoped_lock lock(roots->mutex_);
    for (const VALUE *address : roots->addresses_) {
      rb_gc_mark_maybe(*address);
    }
  }

  static constexpr rb_data_type_t TYPE = {
      .wrap_struct_name = "Lota::Native Rice roots",
      .function =
          {
              .dmark = &mark,
              .dfree = nullptr,
              .dsize = nullptr,
              .dcompact = nullptr,
              .reserved = {},
          },
      .parent = nullptr,
      .data = nullptr,
      .flags = 0,
  };

  mutable std::mutex mutex_;
  std::unordered_multiset<const VALUE *> addresses_;
  bool installed_ = false;
};

} // namespace

void install_rice_roots() { RiceRoots::instance().install(); }

} // namespace lota::native

extern "C" void lota_gc_register_address(VALUE *address) {
  lota::native::RiceRoots::instance().root(address);
}

extern "C" void lota_gc_unregister_address(VALUE *address) {
  lota::native::RiceRoots::instance().forget(address);
}

#endif
