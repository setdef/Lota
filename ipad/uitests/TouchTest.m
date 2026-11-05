// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: MIT-0
//
// The iPad kit's touch and rotation check, which only CI builds (in a copy
// of the kit's project, never the one in the zip): XCTest, Apple's own UI
// testing, launches Dot Popper without autoplay, so every touch is one
// this test makes, as Fledge's examples/sdl_phone/host/ios/UITests/TapTest.m
// taps its game. It taps a grid of points in portrait, turns the iPad to
// landscape and taps again, and turns it back, writing a screenshot of
// each stage to KIT_SHOTS (the Simulator's processes share the Mac's files).
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

- (void)tapGrid:(XCUIApplication *)app rounds:(int)rounds {
    for (int round = 0; round < rounds; round++) {
        for (double y = 0.25; y < 0.95; y += 0.15) {
            for (double x = 0.1; x < 0.95; x += 0.2) {
                [[app coordinateWithNormalizedOffset:CGVectorMake(x, y)] tap];
            }
        }
    }
}

- (void)testTouchAndRotation {
    self.continueAfterFailure = YES;
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationPortrait;
    XCUIApplication *app = [XCUIApplication new];
    app.launchEnvironment = @{@"DOT_POPPER_SEED": @"7"};
    [app launch];
    [NSThread sleepForTimeInterval:10];
    [self shot:@"touch-1-portrait-title"];
    [[app coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)] tap];
    [NSThread sleepForTimeInterval:2];
    [self shot:@"touch-2-portrait-after-first-tap"];
    [self tapGrid:app rounds:2];
    [self shot:@"touch-3-portrait-after-taps"];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
    [NSThread sleepForTimeInterval:4];
    [self shot:@"touch-4-landscape"];
    [self tapGrid:app rounds:2];
    [self shot:@"touch-5-landscape-after-taps"];
    [NSThread sleepForTimeInterval:30];
    [self shot:@"touch-6-landscape-later"];
    XCUIDevice.sharedDevice.orientation = UIDeviceOrientationPortrait;
    [NSThread sleepForTimeInterval:4];
    [self shot:@"touch-7-portrait-again"];
    XCTAssertEqual(app.state, XCUIApplicationStateRunningForeground, @"Dot Popper is no longer running");
}

@end
