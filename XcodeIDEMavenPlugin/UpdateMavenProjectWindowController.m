//
//  UpdateMavenProjectWindowController.m
//  XcodeIDEMavenPlugin
//
//  Created by Holl, Marcus on 10/29/12.
//  Copyright (c) 2012 SAP AG. All rights reserved.
//

#import "UpdateMavenProjectWindowController.h"

@interface UpdateMavenProjectWindowController ()
@property (retain)IBOutlet NSTextField *version;
@end

@implementation UpdateMavenProjectWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    NSButton *closeButton = [self.window standardWindowButton:NSWindowCloseButton];
    closeButton.target = self;
    closeButton.action = @selector(closeButtonClicked);
    
    self.version.stringValue = @"This is the version";
}

- (void)closeButtonClicked {
    [self.window close];
    if (self.cancel) {
        self.cancel();
    }
}


@end
