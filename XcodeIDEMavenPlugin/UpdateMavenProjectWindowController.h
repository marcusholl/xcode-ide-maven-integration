//
//  UpdateMavenProjectWindowController.h
//  XcodeIDEMavenPlugin
//
//  Created by Holl, Marcus on 10/29/12.
//  Copyright (c) 2012 SAP AG. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface UpdateMavenProjectWindowController : NSWindowController
@property (copy) void (^cancel)(void);

@end
