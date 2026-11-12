// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_offline on Linux: no network for a program the parity harness
// runs (native_test/CMakeLists.txt). The harness loads it into the
// reference love and into Lota with LD_PRELOAD (test/parity/
// parity_helper.rb, Parity.loopback), which puts its connect and
// getaddrinfo ahead of the C library's, so a game that asks a server for
// something, as FLASH-BLIP asks one on the local network for a newer
// version at every start, reaches none, and both engines get the same
// answer whatever network the machine is on. offline.mm does the
// same on macOS.
//
// A connection to an Internet address is refused at once, as by a server
// that is there and refuses it: connect fails with ECONNREFUSED, which
// LuaSocket reports as "connection refused" and Ruby raises as
// Errno::ECONNREFUSED. A name is looked up only when it is written as an
// address (AI_NUMERICHOST), so no lookup reaches a resolver, on the
// network or one on the machine that would ask the network; any other
// name is unknown (EAI_NONAME). Sockets of other families, such as the
// Unix sockets the X display and D-Bus listen on, connect as before.

#include <cerrno>

#include <dlfcn.h>
#include <netdb.h>
#include <sys/socket.h>

namespace {

// The C library's definition of +name+: the next after this library's
// (dlsym's RTLD_NEXT), which dlsym hands back as a void *.
template <typename Function> Function *next_definition(const char *name) {
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
  return reinterpret_cast<Function *>(dlsym(RTLD_NEXT, name));
}

} // namespace

// The replacements, which take the C library's names in the symbol table
// (an asm label) and names of their own in C++, since a C++ definition of
// ::connect or ::getaddrinfo would have to name its parameters as the C
// library's headers do, with names reserved to the implementation.
extern "C" {

__attribute__((visibility("default"))) int lota_offline_refuse(int socket, const sockaddr *address,
                                                               socklen_t length) __asm__("connect");

// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
__attribute__((visibility("default"))) int
lota_offline_look_up(const char *node, const char *service, const addrinfo *hints,
                     addrinfo **result) __asm__("getaddrinfo");

// connect, refused for an Internet address.
int lota_offline_refuse(int socket, const sockaddr *address, socklen_t length) {
  if (address != nullptr && (address->sa_family == AF_INET || address->sa_family == AF_INET6)) {
    errno = ECONNREFUSED;
    return -1;
  }
  static auto *const connect_next = next_definition<decltype(::connect)>("connect");
  return connect_next(socket, address, length);
}

// getaddrinfo, for a name written as an address alone.
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
int lota_offline_look_up(const char *node, const char *service, const addrinfo *hints,
                         addrinfo **result) {
  addrinfo numeric{};
  if (hints != nullptr) {
    numeric = *hints;
  }
  numeric.ai_flags = static_cast<int>(static_cast<unsigned int>(numeric.ai_flags) |
                                      static_cast<unsigned int>(AI_NUMERICHOST));
  static auto *const getaddrinfo_next = next_definition<decltype(::getaddrinfo)>("getaddrinfo");
  return getaddrinfo_next(node, service, &numeric, result);
}

} // extern "C"
