// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_offline on macOS: what offline_linux.cpp does on Linux, through
// dyld's interposing. The harness loads it with DYLD_INSERT_LIBRARIES
// (test/parity/parity_helper.rb, Parity.loopback), and dyld sends every
// other image's calls to connect and getaddrinfo to the replacements its
// __DATA,__interpose section names, while this library's own calls reach
// the system's. A connection to an Internet address is refused at once
// (ECONNREFUSED), and a name is looked up only when it is written as an
// address (AI_NUMERICHOST).

#include <cerrno>

#include <netdb.h>
#include <sys/socket.h>

namespace {

// connect, refused for an Internet address. No address at all fails as
// the kernel fails it, with EFAULT, rather than reaching ::connect, whose
// address the system declares never null.
int offline_connect(int socket, const sockaddr *address, socklen_t length) {
  if (address == nullptr) {
    errno = EFAULT;
    return -1;
  }
  if (address->sa_family == AF_INET || address->sa_family == AF_INET6) {
    errno = ECONNREFUSED;
    return -1;
  }
  return ::connect(socket, address, length);
}

// getaddrinfo, for a name written as an address alone.
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
int offline_getaddrinfo(const char *node, const char *service, const addrinfo *hints,
                        addrinfo **result) {
  addrinfo numeric{};
  if (hints != nullptr) {
    numeric = *hints;
  }
  numeric.ai_flags = static_cast<int>(static_cast<unsigned int>(numeric.ai_flags) |
                                      static_cast<unsigned int>(AI_NUMERICHOST));
  return ::getaddrinfo(node, service, &numeric, result);
}

// dyld's interposing tuple: the replacement, then the function replaced
// (mach-o/dyld-interposing.h), each a pointer to a function of type
// +Function+.
template <typename Function> struct Interpose {
  Function *replacement;
  Function *replaced;
};

__attribute__((used, section("__DATA,__interpose"))) const Interpose<decltype(::connect)>
    interposed_connect{.replacement = &offline_connect, .replaced = &::connect};
__attribute__((used, section("__DATA,__interpose"))) const Interpose<decltype(::getaddrinfo)>
    interposed_getaddrinfo{.replacement = &offline_getaddrinfo, .replaced = &::getaddrinfo};

} // namespace
