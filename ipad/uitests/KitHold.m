// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: MIT-0
//
// Turns the Simulator and holds it turned while ipad/simulator.rb launches
// the app with simctl, which has no way to turn a device itself; only CI
// builds it, in a copy of the kit's project. The app is never launched by
// XCTest, which would set OS_ACTIVITY_DT_MODE in its environment and so
// keep its output out of the log the harness reads (Host/main.m).
//
// KIT_ORIENTATION is portrait or landscape. Once turned, the test writes
// the file KIT_READY, then waits until the file KIT_DONE exists, or
// KIT_HOLD_SECONDS (900 by default) pass. The Simulator's processes share
// the Mac's files.
@import XCTest;

@interface KitHold : XCTestCase
@end

@implementation KitHold

- (void)testHold {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    BOOL landscape = [env[@"KIT_ORIENTATION"] isEqualToString:@"landscape"];
    XCUIDevice.sharedDevice.orientation = landscape ? UIDeviceOrientationLandscapeLeft : UIDeviceOrientationPortrait;
    [NSThread sleepForTimeInterval:3];
    NSString *ready = env[@"KIT_READY"];
    NSString *done = env[@"KIT_DONE"];
    if (ready.length > 0) [@"ready\n" writeToFile:ready atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    double seconds = env[@"KIT_HOLD_SECONDS"].length > 0 ? env[@"KIT_HOLD_SECONDS"].doubleValue : 900;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0 && !(done.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:done])) {
        [NSThread sleepForTimeInterval:1];
    }
}

@end
