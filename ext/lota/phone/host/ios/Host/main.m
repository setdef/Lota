// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0
//
// The app's entry point when SDL3 owns the screen (Fledge's ADR 025), in
// place of the Host/main.m fledge build writes. SDL_RunApp starts UIKit
// with SDL's own delegates (src/video/uikit/SDL_uikitappdelegate.m at
// release-3.4.10, lines 43 to 64), and once the scene connects calls
// run_ruby on the main thread, inside the run loop (lines 354 to 420 and
// 481 to 489), where SDL's video must run. run_ruby runs the app's Ruby
// program there, with FledgeRuby's fledge_ruby_run_app, as Fledge's host
// does on a thread of its own, so Ruby can call SDL directly. The main
// thread's stack is the one the executable asks for, with -Wl,-stack_size
// in OTHER_LDFLAGS. Info.plist names SDLUIKitSceneDelegate as the scene's
// delegate, and LotaApplication, below, as the app's UIApplication.
@import FledgeRuby;
@import AVFoundation;
@import Foundation;
@import UIKit;

#include <errno.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>

// SDL_main.h's SDL_main_func and SDL_RunApp, from SDL3, which the app's
// gem links in; declared here so the host needs no SDL headers.
typedef int (*SDL_main_func)(int argc, char *argv[]);
extern int SDL_RunApp(int argc, char *argv[], SDL_main_func main_function, void *reserved);

static os_log_t app_log;

// The app's UIApplication, which Info.plist names as NSPrincipalClass, so
// that UIApplicationMain, called by SDL_RunApp with no class of its own,
// makes one. SDL 3.4.10 reads the screen's orientation only from
// statusBarOrientation (SDL_uikitvideo.m, line 240; SDL_uikitmodes.m,
// lines 333, 487, and 521), and iOS 27 makes that a no-op that answers
// Unknown, which SDL takes for portrait: a game launched in landscape got
// a portrait window, cut off at the bottom and black on the right
// (doc/contributors/upstream/019.md). Where UIKit still answers, its
// answer stands; where it answers Unknown, the app's window scene says,
// as Apple's deprecation of statusBarOrientation directs and as SDL 3.4.20
// does (UIKit_GetInterfaceOrientation, SDL_uikitvideo.m).
@interface LotaApplication : UIApplication
@end

@implementation LotaApplication

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (UIInterfaceOrientation)statusBarOrientation {
  UIInterfaceOrientation orientation = [super statusBarOrientation];
  if (orientation != UIInterfaceOrientationUnknown)
    return orientation;
  if (@available(iOS 16.0, *)) {
    for (UIScene *scene in self.connectedScenes) {
      if ([scene isKindOfClass:UIWindowScene.class] &&
          [scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication])
        return ((UIWindowScene *)scene).effectiveGeometry.interfaceOrientation;
    }
  }
  return orientation;
}
#pragma clang diagnostic pop

@end

static NSString *AppName(void) {
  NSDictionary *info = NSBundle.mainBundle.infoDictionary;
  return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
}

// SDL's main function: runs the app's Ruby program on the calling thread,
// the main thread, and logs its exit status.
static int run_ruby(int argc, char *argv[]) {
  NSString *root = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"fledge"];
  int status = fledge_ruby_run_app(root.fileSystemRepresentation, 0, NULL);
  os_log(app_log, "%{public}@ exited with status %d", AppName(), status);
  return status;
}

// The audio session's category, from Info.plist's LotaAudioSessionCategory:
// ambient mixes with other apps' audio and the silent switch mutes it,
// soloAmbient (the system's default) stops other apps' audio and the
// switch mutes it, playback stops other apps' audio and plays through
// the switch. Empty or missing leaves the system's default.
static AVAudioSessionCategory AudioCategory(void) {
  NSString *name = NSBundle.mainBundle.infoDictionary[@"LotaAudioSessionCategory"];
  if ([name isEqualToString:@"ambient"])
    return AVAudioSessionCategoryAmbient;
  if ([name isEqualToString:@"soloAmbient"])
    return AVAudioSessionCategorySoloAmbient;
  if ([name isEqualToString:@"playback"])
    return AVAudioSessionCategoryPlayback;
  if (name.length > 0)
    os_log_error(app_log, "unknown LotaAudioSessionCategory %{public}@, kept the default", name);
  return nil;
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    app_log = os_log_create(identifier.UTF8String, "app");
    // The unified log copies every entry to standard error when the
    // environment holds OS_ACTIVITY_DT_MODE, whatever its value, as
    // Xcode's console and XCTest set it. Forwarding standard error to
    // the log would then loop on the app's own output and freeze it,
    // so the streams stay with the tool that launched the app, whose
    // console shows them. Fledge's fledge_ruby_forward_output makes the
    // same check since 0.5.0 (its runtime/mobile/apple.c); the host
    // says so in the log, where the app's lines would otherwise be.
    if (getenv("OS_ACTIVITY_DT_MODE") != NULL) {
      os_log(app_log, "OS_ACTIVITY_DT_MODE is set, so the app's output stays on its own streams");
    } else if (fledge_ruby_forward_output(identifier.UTF8String) != 0) {
      os_log_error(app_log, "could not send the app's output to the log: %{public}s",
                   strerror(errno));
    }
    // A guard, not LÖVE's behavior: on iOS SDL makes the accelerometer
    // a joystick by default (SDL_HINT_ACCELEROMETER_AS_JOYSTICK, which
    // SDL also reads from this environment variable), and LÖVE leaves
    // it so. An early Lota crashed in the iPad Simulator while a game
    // read that joystick every frame, so the host hides it: a game reads
    // the accelerometer through Lota::Sensor, and a paired controller
    // is still a joystick. The environment wins, so a scheme's
    // SDL_ACCELEROMETER_AS_JOYSTICK=1 brings the joystick back.
    setenv("SDL_ACCELEROMETER_AS_JOYSTICK", "0", 0);
    AVAudioSessionCategory category = AudioCategory();
    NSError *error = nil;
    if (category != nil && ![AVAudioSession.sharedInstance setCategory:category error:&error]) {
      os_log_error(app_log, "could not set the audio session's category: %{public}@", error);
    }
  }
  return SDL_RunApp(argc, argv, run_ruby, NULL);
}
