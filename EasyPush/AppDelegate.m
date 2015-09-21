//
//  AppDelegate.m
//  EasyPush
//
//  Created by Haven on 9/16/15.
//  Copyright (c) 2015 Haven. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (weak) IBOutlet NSMenu *theMenu;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
//    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
//    _statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
//    _statusItem.image = [NSImage imageNamed:@"switchIcon.png"];
//    [_statusItem.image setTemplate:YES];
//    
//    _statusItem.highlightMode = YES;
//    _statusItem.toolTip = @"command-click to quit";
//    [_statusItem setMenu:_theMenu];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
    return YES;
}

@end
