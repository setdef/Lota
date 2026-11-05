// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: MIT-0
//
// The iOS kit's touch and rotation check, which only CI builds, in a copy
// of the kit's project, never the one in the zip, as Fledge's
// examples/sdl_phone/host/ios/UITests/TapTest.m taps its game. XCTest
// does not launch the app: ipad/simulator.rb does, with simctl and the
// game's settings, once this test writes the file KIT_READY, so the app's
// output reaches the log the harness reads (XCTest's own launch sets
// OS_ACTIVITY_DT_MODE, which keeps it out; Host/main.m). The test finds
// the app by KIT_APP, its bundle identifier, and waits for it.
//
// In portrait it taps three known points, then a grid; turns the device
// to landscape and taps two known points and the grid again; and turns
// it back. The known points are fractions of the screen, so a game that
// prints its touches shows where each landed. Each stage's screenshot goes
// to KIT_SHOTS (the Simulator's processes share the Mac's files).
@import XCTest;

@interface TouchTest : XCTestCase
@end

@implementation TouchTest

- (void)shot:(NSString *)name {
    NSString *folder = NSProcessInfo.processInfo.environment[@"KIT_SHOTS"];
    XCUIScreenshot *screenshot = XCUIScreen.mainScreen.screenshot;
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:screenshot];
    attachment.name = name;
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
    if (folder.length > 0) {
        [screenshot.PNGRepresentation writeToFile:[folder stringByAppendingPathComponent:[name stringByAppendingString:@".png"]]
                                       atomically:YES];
    }
}

- (void)tap:(XCUIApplication *)app x:(double)x y:(double)y label:(NSString *)label {
    NSLog(@"kit touch: %@ tap at %.2f, %.2f of the screen", label, x, y);
    [[app coordinateWithNormalizedOffset:CGVectorMake(x, y)] tap];
    [NSThread sleepForTimeInterval:0.5];
}

- (void)tapGrid:(XCUIApplication *)app {
    for (double y = 0.25; y < 0.95; y += 0.15) {
        for (double x = 0.1; x < 0.95; x += 0.2) {
            [[app coordinateWithNormalizedOffset:CGVectorMake(x, y)] tap];
        }
    }
}

- (void)testTouchAndRotation {
    self.continueAfterFailure = YES;
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationPortrait;
    [NSThread sleepForTimeInterval:2];
    [@"ready\n" writeToFile:env[@"KIT_READY"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:env[@"KIT_APP"]];
    XCTAssertTrue([app waitForState:XCUIApplicationStateRunningForeground timeout:120], @"the app never came to the foreground");
    [NSThread sleepForTimeInterval:env[@"KIT_SETTLE_SECONDS"].length > 0 ? env[@"KIT_SETTLE_SECONDS"].doubleValue : 8];
    [self shot:@"touch-1-portrait-start"];
    [self tap:app x:0.25 y:0.25 label:@"portrait"];
    [self tap:app x:0.75 y:0.5 label:@"portrait"];
    [self tap:app x:0.5 y:0.75 label:@"portrait"];
    [NSThread sleepForTimeInterval:1];
    [self shot:@"touch-2-portrait-after-known-taps"];
    [self tapGrid:app];
    [self shot:@"touch-3-portrait-after-grid"];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    [NSThread sleepForTimeInterval:4];
    [self shot:@"touch-4-landscape"];
    [self tap:app x:0.25 y:0.25 label:@"landscape"];
    [self tap:app x:0.75 y:0.5 label:@"landscape"];
    [self tapGrid:app];
    [self shot:@"touch-5-landscape-after-taps"];
    [NSThread sleepForTimeInterval:10];
    [self shot:@"touch-6-landscape-later"];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationPortrait;
    [NSThread sleepForTimeInterval:4];
    [self shot:@"touch-7-portrait-again"];
    XCTAssertEqual(app.state, XCUIApplicationStateRunningForeground, @"the app is no longer running in the foreground");
}

@end
