/*
 * #%L
 * xcode-maven-plugin
 * %%
 * Copyright (C) 2012 SAP AG
 * %%
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * #L%
 */

#import "SAPXcodeMavenPlugin.h"
#import <objc/runtime.h>
#import "MyMenuItem.h"
#import "InitializeWindowController.h"
#import "UpdateMavenProjectWindowController.h"
#import "RunInitializeOperation.h"

@interface SAPXcodeMavenPlugin ()

@property (retain) NSOperationQueue *initializeQueue;

@property (retain) id activeWorkspace;
@property (retain) NSMenuItem *xcodeMavenPluginSeparatorItem;
@property (retain) NSMenuItem *xcodeMavenPluginItem;


@property (retain) InitializeWindowController *initializeWindowController;
@property (retain) UpdateMavenProjectWindowController *updateMavenProjectWindowController;

@end


@implementation SAPXcodeMavenPlugin

static SAPXcodeMavenPlugin *plugin;

+ (id)sharedSAPXcodeMavenPlugin {
	return plugin;
}

+ (void)pluginDidLoad:(NSBundle *)bundle {
	plugin = [[self alloc] initWithBundle:bundle];
}

- (id)initWithBundle:(NSBundle *)bundle {
    self = [super init];
	if (self) {
        self.initializeQueue = [[NSOperationQueue alloc] init];
        self.initializeQueue.maxConcurrentOperationCount = 1;

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(buildProductsLocationDidChange:)
                                                   name:@"IDEWorkspaceBuildProductsLocationDidChangeNotification"
                                                 object:nil];

        [NSApplication.sharedApplication addObserver:self
                                          forKeyPath:@"mainWindow"
                                             options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionOld
                                             context:NULL];
	}
	return self;
}

- (void)buildProductsLocationDidChange:(NSNotification *)notification {
    [self updateMainMenu];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    @try {
        if ([object isKindOfClass:NSApplication.class] && [keyPath isEqualToString:@"mainWindow"] && change[NSKeyValueChangeOldKey] != NSApplication.sharedApplication.mainWindow && NSApplication.sharedApplication.mainWindow) {
            [self updateActiveWorkspace];
        } else if ([keyPath isEqualToString:@"activeRunContext"]) {
            [self updateMainMenu];
        }
    }
    @catch (NSException *exception) {
        // TODO log
    }
}

- (void)updateActiveWorkspace {
    id newWorkspace = [self workspaceFromWindow:NSApplication.sharedApplication.keyWindow];
    if (newWorkspace != self.activeWorkspace) {
        if (self.activeWorkspace) {
            id runContextManager = [self.activeWorkspace valueForKey:@"runContextManager"];
            @try {
                [runContextManager removeObserver:self forKeyPath:@"activeRunContext"];
            }
            @catch (NSException *exception) {
                // do nothing
            }
        }

        self.activeWorkspace = newWorkspace;

        if (self.activeWorkspace) {
            id runContextManager = [self.activeWorkspace valueForKey:@"runContextManager"];
            if (runContextManager) {
                [runContextManager addObserver:self forKeyPath:@"activeRunContext" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionOld context:NULL];
            }
        }
    }
}

- (id)workspaceFromWindow:(NSWindow *)window {
	if ([window isKindOfClass:objc_getClass("IDEWorkspaceWindow")]) {
        if ([window.windowController isKindOfClass:NSClassFromString(@"IDEWorkspaceWindowController")]) {
            return [window.windowController valueForKey:@"workspace"];
        }
    }
    return nil;
}

- (void)updateMainMenu {
    NSMenu *menu = [NSApp mainMenu];
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:@"Product"]) {
            NSMenu *productMenu = item.submenu;
            if (self.xcodeMavenPluginItem) {
                [productMenu removeItem:self.xcodeMavenPluginSeparatorItem];
                self.xcodeMavenPluginSeparatorItem = nil;
                [productMenu removeItem:self.xcodeMavenPluginItem];
                self.xcodeMavenPluginItem = nil;
            }

            NSArray *activeProjects = self.activeWorkspace ? [self activeProjectsFromWorkspace:self.activeWorkspace] : nil;
            self.xcodeMavenPluginSeparatorItem = NSMenuItem.separatorItem;
            [productMenu addItem:self.xcodeMavenPluginSeparatorItem];
            self.xcodeMavenPluginItem = [[NSMenuItem alloc] initWithTitle:@"Xcode Maven Plugin"
                                                                   action:nil
                                                            keyEquivalent:@""];
            [productMenu addItem:self.xcodeMavenPluginItem];

            self.xcodeMavenPluginItem.submenu = [[NSMenu alloc] initWithTitle:@""];

            MyMenuItem *initializeItem = [[MyMenuItem alloc] initWithTitle:@"Initialize"
                                                                    action:nil
                                                             keyEquivalent:@""];
            [self.xcodeMavenPluginItem.submenu addItem:initializeItem];

            
            if (activeProjects.count == 1) {
                id project = activeProjects[0];
                initializeItem.title = [NSString stringWithFormat:@"Initialize %@", [project name]];
                initializeItem.keyEquivalent = @"i";
                initializeItem.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask;
                initializeItem.target = self;
                initializeItem.action = @selector(initialize:);
                initializeItem.xcode3Projects = @[project];

                MyMenuItem *initializeItemAdvanced = [[MyMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Initialize %@...", [project name]]
                                                                                action:nil
                                                                         keyEquivalent:@""];
                initializeItemAdvanced.keyEquivalent = @"i";
                initializeItemAdvanced.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask;
                initializeItemAdvanced.target = self;
                initializeItemAdvanced.action = @selector(initializeAdvanced:);
                initializeItemAdvanced.alternate = YES;
                initializeItemAdvanced.xcode3Projects = @[project];
                [self.xcodeMavenPluginItem.submenu addItem:initializeItemAdvanced];

            } else {
                MyMenuItem *initializeAllItem = [[MyMenuItem alloc] initWithTitle:@"Initialize All"
                                                                           action:@selector(initializeAll:)
                                                                    keyEquivalent:@""];
                initializeAllItem.keyEquivalent = @"a";
                initializeAllItem.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask;
                initializeAllItem.target = self;
                initializeAllItem.xcode3Projects = activeProjects;
                [self.xcodeMavenPluginItem.submenu addItem:initializeAllItem];

                MyMenuItem *initializeAllItemAdvanced = [[MyMenuItem alloc] initWithTitle:@"Initialize All..."
                                                                                   action:@selector(initializeAllAdvanced:)
                                                                            keyEquivalent:@""];
                initializeAllItemAdvanced.keyEquivalent = @"a";
                initializeAllItemAdvanced.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask;
                initializeAllItemAdvanced.alternate = YES;
                initializeAllItemAdvanced.target = self;
                initializeAllItemAdvanced.xcode3Projects = activeProjects;
                [self.xcodeMavenPluginItem.submenu addItem:initializeAllItemAdvanced];

                initializeItem.submenu = [[NSMenu alloc] initWithTitle:@""];

                [activeProjects enumerateObjectsUsingBlock:^(id project, NSUInteger idx, BOOL *stop) {
                    MyMenuItem *initializeProjectItem = [[MyMenuItem alloc] initWithTitle:[project name]
                                                                                   action:@selector(initialize:)
                                                                            keyEquivalent:@""];
                    [initializeItem.submenu addItem:initializeProjectItem];
                    if (idx == activeProjects.count-1) {
                        initializeProjectItem.keyEquivalent = @"i";
                        initializeProjectItem.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask;

                        MyMenuItem *initializeProjectItemAdvanced = [[MyMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@...", [project name]]
                                                                                               action:@selector(initializeAdvanced:)
                                                                                        keyEquivalent:@""];
                        initializeProjectItemAdvanced.keyEquivalent = @"i";
                        initializeProjectItemAdvanced.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask | NSShiftKeyMask | NSAlternateKeyMask;
                        initializeProjectItemAdvanced.alternate = YES;
                        initializeProjectItemAdvanced.target = self;
                        initializeProjectItemAdvanced.xcode3Projects = @[project];
                        [initializeItem.submenu addItem:initializeProjectItemAdvanced];
                    }
                    initializeProjectItem.target = self;
                    initializeProjectItem.xcode3Projects = @[project];
                }];
            }
            MyMenuItem *updateMavenProjectItem = [[MyMenuItem alloc] initWithTitle:@"Update Version in Pom..."
                                                                            action:nil
                                                                     keyEquivalent:@""];
            [self.xcodeMavenPluginItem.submenu addItem:updateMavenProjectItem];

            updateMavenProjectItem.target = self;
            updateMavenProjectItem.action = @selector(updatePom:);            
        }
    }
}

- (void)updatePom:(MyMenuItem *)menuItem {
    self.updateMavenProjectWindowController = [[UpdateMavenProjectWindowController alloc] initWithWindowNibName:@"UpdateMavenProjectWindowController"];

    self.updateMavenProjectWindowController.cancel = ^{
        [NSApp abortModal];
        self.updateMavenProjectWindowController = nil;
    };

    [NSApp runModalForWindow:self.updateMavenProjectWindowController.window];
}

- (NSArray *)activeProjectsFromWorkspace:(id)workspace {
    NSArray *targets = [self activeTargetsFromWorkspace:workspace];
    NSMutableArray *projects = [NSMutableArray array];
    for (id target in targets) {
        id xcode3Project = [target valueForKey:@"referencedContainer"];
        if ([xcode3Project isKindOfClass:objc_getClass("Xcode3Project")] && ![projects containsObject:xcode3Project]) {
            [projects addObject:xcode3Project];
        }
    }
    return projects;
}

- (NSArray *)activeTargetsFromWorkspace:(id)workspace {
    id runContextManager = [workspace valueForKey:@"runContextManager"];
    id activeScheme = [runContextManager valueForKey:@"activeRunContext"];
    id buildSchemaAction = [activeScheme valueForKey:@"buildSchemeAction"];
    id buildActionEntries = [buildSchemaAction valueForKey:@"buildActionEntries"];
    NSMutableArray *targets = [NSMutableArray array];
    for (id buildActionEntry in buildActionEntries) {
        id buildableReference = [buildActionEntry valueForKey:@"buildableReference"];
        if (/*[buildableReference isKindOfClass:objc_getClass("Xcode3Target")] &&  */ ![targets containsObject:buildableReference]) {
            [targets addObject:buildableReference];
        }
    }
    return targets;
}

- (void)initializeAdvanced:(MyMenuItem *)menuItem {
    [self defineConfigurationAndRunInitializeForProjects:menuItem.xcode3Projects];
}

- (void)defineConfigurationAndRunInitializeForProjects:(NSArray *)xcode3Projects {
    self.initializeWindowController = [[InitializeWindowController alloc] initWithWindowNibName:@"InitializeWindowController"];
    self.initializeWindowController.xcode3Projects = xcode3Projects;
    self.initializeWindowController.run = ^(InitializeConfiguration *configuration) {
        [self.initializeWindowController close];
        self.initializeWindowController = nil;
        [self runInitializeForProjects:xcode3Projects configuration:configuration];
    };
    self.initializeWindowController.cancel = ^{
        [NSApp abortModal];
        self.initializeWindowController = nil;
    };
    
    [NSApp runModalForWindow:self.initializeWindowController.window];
}

- (void)initialize:(MyMenuItem *)menuItem {
    XcodeConsole *console = [[XcodeConsole alloc] initWithConsole:[self findConsoleAndActivate]];
    @try {
    //
    id executionEnvironment = [self.activeWorkspace valueForKey:@"executionEnvironment"];
    id currentBuildOperation = [executionEnvironment valueForKey:@"currentBuildOperation"];
    
    [console appendText:@"initialize called ...\n"];
    [console appendText:[executionEnvironment description]];

    
    id runContextManager = [self.activeWorkspace valueForKey:@"runContextManager"];
    id activeScheme = [runContextManager valueForKey:@"activeRunContext"];
        
        
        
//    id parameters = [activeScheme buildParametersForSchemeCommand:0 destination:[runContextManager valueForKey:@"activeRunDestination"]];
        
        NSArray *projects = [self activeProjectsFromWorkspace:self.activeWorkspace];
        
        if(projects.count == 1) {
            
            [console appendText:@"We have one project.\n"];
            [console appendText: [projects[0] description]];
            
            unsigned int count;
            Method *methods = class_copyMethodList(objc_getClass("NSPathStore2"), &count);
            
            for(int i = 0; i < count; i++) {
                [console appendText:NSStringFromSelector(method_getName(methods[i]))];
                [console appendText:@"\n"];
            }
            
            id targetProxies = [projects[0] valueForKey:@"targetProxies"];
            
            [console appendText:[targetProxies description]];
            
            [console appendText:[[targetProxies class] description]];
            
            NSArray *tProxies = targetProxies;
            
            //[console appendText:@"xxxxxxxxxxxxxxxxxxxx\n"];
            //[console appendText:[tProxies[0] description]];
            
            //methods = class_copyMethodList(objc_getClass("Xcode3Target"), &count);

            for(int i = 0; i < count; i++) {
                //[console appendText:NSStringFromSelector(method_getName(methods[i]))];
                //[console appendText:@"\n"];
            }

            NSArray *targets = [self activeTargetsFromWorkspace:[self activeWorkspace]];
            
            [console appendText:targets.description];
            
            [console appendText:@"\nzzzzzzzzzzzzzzzzzzzzz\n"];
            
            [console appendText:[targets[0] valueForKey:@"resolvedBuildable"] ];
            [console appendText:[targets[0] valueForKey:@"resolvedBlueprint"] ];
              
            id infoPListPath = [targets[0] valueForKey:@"infoPlistFilePath"];
            
            [console appendText:[[infoPListPath class] description ]];
            
            NSString *iplp = infoPListPath;
            
            [console appendText:infoPListPath];
            
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:iplp];
            
            NSString *version = plist[@"CFBundleShortVersionString"];
            
            [console appendText:version];
            
            [console appendText:[plist description] ];
            
            [console appendText:@"aaaaaaaaaaaaaaaaaaaaaaaaaa\n"];
            [console appendText:version];
            
//            
//            SEL sel = @selector(stringsByEvaluatingPropertyString:inAllConfigurationsForWorkspaceArenaSnapshot:);
//            NSMethodSignature *sig = [tProxies[0] methodSignatureForSelector:sel];
//            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
//        
//            int yes = 1;
//            
//            [inv setArgument:@"INFOPLIST_FILE" atIndex:2];
//            [inv setArgument:&yes atIndex:3];
//            [inv invoke];
//            [console appendText:@"After invoke"];
//            CFTypeRef buffer;
//            [inv getReturnValue:&buffer];
//            id s = (id)buffer;
//            [console appendText:[s description]];
            
        } else {
            [console appendText:@"We have zero or more than one projects.\n"];
        }
        
        SEL sel = @selector(buildParametersForSchemeCommand:destination:);
        NSMethodSignature *sig = [activeScheme methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        //[console appendText:sig.];
        inv.selector = sel;
        inv.target = activeScheme;
        int command = 1;
        [inv setArgument:&command atIndex:2];
        
        
        id activeRunDestination = [runContextManager valueForKey:@"activeRunDestination"];
//        
//        if(!activeRunDestination) {
//            [console appendText:@"ActiveRunDestination not found.\n"];
//        } else {
//            [console appendText:@"ActiveRunDestination found.\n"];
//        }
//        
        [inv setArgument:activeRunDestination atIndex:3];
        // GEHT NICHT
        //[console appendText:@"1\n"];
        //[console appendText:[inv getArgument:<#(void *)#> atIndex:1]];
        //[inv invoke];
        //[console appendText:@"2\n"];
        
        
//        CFTypeRef buffer;
//        [inv getReturnValue:&buffer];
//        id s = (id)buffer;
//        [console appendText:[s description]];
        
    //[console appendText:[parameters description]];
    /*id buildSchemaAction = [activeScheme valueForKey:@"buildSchemeAction"];
    id buildActionEntries = [buildSchemaAction valueForKey:@"buildActionEntries"];

    for (id buildActionEntry in buildActionEntries) {
        id buildableReference = [buildActionEntry valueForKey:@"buildableReference"];
        id resolvedBuildable = [buildableReference valueForKey:@"resolvedBuildable"];
        id xxx = [resolvedBuildable performSelector:@selector(valueForBuildSetting:withBuildParameters:) withObject:@"PRODUCT_NAME" withObject:nil];
        [console appendText:[xxx description]];
    }

    
    unsigned int count;
//        Method *methods = class_copyMethodList(objc_getClass("IDESchemeBuildableReference"), &count);
    Method *methods = class_copyMethodList(objc_getClass("IDEBuildable"), &count);
    
    for(int i = 0; i < count; i++) {
        [console appendText:NSStringFromSelector(method_getName(methods[i]))];
        [console appendText:@"\n"];
    }
    
    if(!currentBuildOperation) {
      [console appendText:@"CurrentBuildOperation not found."];
    }

    [console appendText:[currentBuildOperation description]];
    [console appendText:@"\n\n"];
    //
    
    
    //[self runInitializeForProjects:menuItem.xcode3Projects configuration:nil];*/
    }
    @catch (NSException *exception) {
        [console appendText:exception.description];
    }
}

- (void)initializeAllAdvanced:(MyMenuItem *)menuItem {
    [self defineConfigurationAndRunInitializeForProjects:menuItem.xcode3Projects];
}

- (void)initializeAll:(MyMenuItem *)menuItem {
    [self runInitializeForProjects:menuItem.xcode3Projects configuration:nil];
}

- (void)runInitializeForProjects:(NSArray *)xcode3Projects configuration:(InitializeConfiguration *)configuration {
    for (id xcode3Project in xcode3Projects) {
        RunInitializeOperation *operation = [[RunInitializeOperation alloc] initWithProject:xcode3Project configuration:configuration];
        operation.xcodeConsole = [[XcodeConsole alloc] initWithConsole:[self findConsoleAndActivate]];
        [self.initializeQueue addOperation:operation];
    }
}

- (NSTextView *)findConsoleAndActivate {
    Class consoleTextViewClass = objc_getClass("IDEConsoleTextView");
    NSTextView *console = (NSTextView *)[self findView:consoleTextViewClass inView:NSApplication.sharedApplication.mainWindow.contentView];

    if (console) {
        NSWindow *window = NSApplication.sharedApplication.keyWindow;
        if ([window isKindOfClass:objc_getClass("IDEWorkspaceWindow")]) {
            if ([window.windowController isKindOfClass:NSClassFromString(@"IDEWorkspaceWindowController")]) {
                id editorArea = [window.windowController valueForKey:@"editorArea"];
                [editorArea performSelector:@selector(activateConsole:) withObject:self];
            }
        }
    }
    
    return console;
}

- (NSView *)findView:(Class)consoleClass inView:(NSView *)view {
    if ([view isKindOfClass:consoleClass]) {
        return view;
    }

    for (NSView *v in view.subviews) {
        NSView *result = [self findView:consoleClass inView:v];
        if (result) {
            return result;
        }
    }
    return nil;
}

@end
