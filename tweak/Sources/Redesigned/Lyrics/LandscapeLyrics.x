// Landscape lyrics (LandscapeLyrics.h). Spotify is portrait only; turning is allowed in three places and only while
// the full screen lyrics page is in a window:
//   - the app delegate's application:supportedInterfaceOrientationsForWindow:, which the system asks before anything
//     else and which overrides the Info.plist. Spotify's delegate may or may not answer it (Firebase's swizzler sits in
//     between), so the method is wrapped when it is there and added when it is not;
//   - -[UIViewController supportedInterfaceOrientations] and -shouldAutorotate, which the system asks of the top
//     controller (the page is presented over the player, so which one is asked is the system's to say);
//   - the scene itself, asked for portrait again when the page closes, so the phone does not stay on its side.
// The page is Spotify's (Lyrics_FullscreenElementPageImpl); the karaoke view over its lyrics part relays out by width.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "LandscapeLyrics.h"

static BOOL sg_pageOnScreen;

static BOOL landscapeNow(void) { return sg_pageOnScreen && SGFlag(SGRKeyLyricsLandscape, NO); }

// What the Info.plist allows, for an app delegate with no answer of its own.
static UIInterfaceOrientationMask plistMask(void) {
    NSArray *names = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UISupportedInterfaceOrientations"];
    UIInterfaceOrientationMask mask = 0;
    for (NSString *name in [names isKindOfClass:NSArray.class] ? names : @[]) {
        if ([name isEqual:@"UIInterfaceOrientationPortrait"]) mask |= UIInterfaceOrientationMaskPortrait;
        else if ([name isEqual:@"UIInterfaceOrientationPortraitUpsideDown"]) mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
        else if ([name isEqual:@"UIInterfaceOrientationLandscapeLeft"]) mask |= UIInterfaceOrientationMaskLandscapeLeft;
        else if ([name isEqual:@"UIInterfaceOrientationLandscapeRight"]) mask |= UIInterfaceOrientationMaskLandscapeRight;
    }
    return mask ?: UIInterfaceOrientationMaskPortrait;
}

static UIInterfaceOrientationMask (*sg_originalDelegate)(id, SEL, UIApplication *, UIWindow *);
static UIInterfaceOrientationMask delegateMask(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (landscapeNow()) return UIInterfaceOrientationMaskAllButUpsideDown;
    return sg_originalDelegate ? sg_originalDelegate(self, _cmd, application, window) : plistMask();
}

static UIWindowScene *activeScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    return nil;
}

// The page came or went: the controllers are asked again, and on the way out the scene is put back upright.
static void pageChanged(BOOL onScreen) {
    if (onScreen == sg_pageOnScreen) return;
    sg_pageOnScreen = onScreen;
    if (!SGFlag(SGRKeyLyricsLandscape, NO) && onScreen) return;
    UIWindowScene *scene = activeScene();
    for (UIWindow *window in scene.windows) [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    if (!onScreen && scene && UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) {
        UIWindowSceneGeometryPreferencesIOS *upright =
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [scene requestGeometryUpdateWithPreferences:upright errorHandler:^(NSError *error) {
            SGLog(@"landscape lyrics: could not turn back upright: %@", error.localizedDescription);
        }];
    }
}

%hook _TtC32Lyrics_FullscreenElementPageImpl14FullscreenView
- (void)didMoveToWindow {
    %orig;
    BOOL here = ((UIView *)self).window != nil;
    dispatch_async(dispatch_get_main_queue(), ^{ pageChanged(here); });
}
%end

%hook UIViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return landscapeNow() ? UIInterfaceOrientationMaskAllButUpsideDown : %orig;
}
- (BOOL)shouldAutorotate {
    return landscapeNow() ? YES : %orig;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]);
    Class delegate = NSClassFromString(@"_TtC24MusicApp_ContainerWiring18SpotifyAppDelegate");
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    if (!delegate) return;
    Method existing = class_getInstanceMethod(delegate, selector);
    if (existing) {
        sg_originalDelegate = (UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))method_getImplementation(existing);
        method_setImplementation(existing, (IMP)delegateMask);
    } else {
        class_addMethod(delegate, selector, (IMP)delegateMask, "Q@:@@");
    }
    SGLog(@"landscape lyrics: delegate %@", existing ? @"wrapped" : @"answers now");
}
