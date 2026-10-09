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
static Class sg_hookedDelegateClass;

static UIInterfaceOrientationMask delegateMask(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (landscapeNow()) return UIInterfaceOrientationMaskAllButUpsideDown;
    return sg_originalDelegate ? sg_originalDelegate(self, _cmd, application, window) : plistMask();
}

// Spotify's delegate class name changes between app builds. Hook the live delegate instance instead
// of depending on one private, version-specific class name. If the method is inherited, add an
// override to the concrete class so we don't accidentally replace a superclass implementation.
static void installDelegateOrientationHook(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    Class cls = delegate ? object_getClass(delegate) : Nil;
    if (!cls || cls == sg_hookedDelegateClass) return;

    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method ? method_getImplementation(method) : NULL;
    if (original == (IMP)delegateMask) {
        sg_hookedDelegateClass = cls;
        return;
    }

    sg_originalDelegate = (UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))original;
    const char *types = method ? method_getTypeEncoding(method) : "Q@:@@";
    if (!class_addMethod(cls, selector, (IMP)delegateMask, types)) {
        Method own = class_getInstanceMethod(cls, selector);
        if (own) method_setImplementation(own, (IMP)delegateMask);
    }
    sg_hookedDelegateClass = cls;
    SGLog(@"landscape lyrics: orientation delegate hooked on %@", NSStringFromClass(cls));
}

static UIWindowScene *activeScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    return nil;
}

static void invalidateOrientation(UIViewController *controller) {
    if (!controller) return;
    if (@available(iOS 16.0, *)) [controller setNeedsUpdateOfSupportedInterfaceOrientations];
    for (UIViewController *child in controller.childViewControllers) invalidateOrientation(child);
    invalidateOrientation(controller.presentedViewController);
}

static UIInterfaceOrientationMask maskForDeviceOrientation(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (orientation == UIDeviceOrientationLandscapeLeft) return UIInterfaceOrientationMaskLandscapeRight;
    if (orientation == UIDeviceOrientationLandscapeRight) return UIInterfaceOrientationMaskLandscapeLeft;
    if (orientation == UIDeviceOrientationPortrait || orientation == UIDeviceOrientationPortraitUpsideDown)
        return UIInterfaceOrientationMaskPortrait;
    return 0;
}

static void requestMask(UIWindowScene *scene, UIInterfaceOrientationMask mask) {
    if (!scene || !mask) return;
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"landscape lyrics: geometry request failed (mask %lu): %@", (unsigned long)mask, error.localizedDescription);
        }];
    }
}

static void deviceOrientationChanged(NSNotification *note) {
    (void)note;
    if (!landscapeNow()) return;
    UIInterfaceOrientationMask mask = maskForDeviceOrientation();
    if (!mask) return;
    UIWindowScene *scene = activeScene();
    for (UIWindow *window in scene.windows) invalidateOrientation(window.rootViewController);
    requestMask(scene, mask);
}

// The page came or went: refresh the whole controller chain and follow the device while it is visible.
static void pageChanged(BOOL onScreen) {
    sg_pageOnScreen = onScreen;
    installDelegateOrientationHook();
    UIWindowScene *scene = activeScene();
    for (UIWindow *window in scene.windows) invalidateOrientation(window.rootViewController);
    if (!scene) return;
    if (!onScreen) {
        requestMask(scene, UIInterfaceOrientationMaskPortrait);
        return;
    }
    if (!SGFlag(SGRKeyLyricsLandscape, NO)) return;
    UIInterfaceOrientationMask mask = maskForDeviceOrientation();
    if (!mask && UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) mask = UIInterfaceOrientationMaskLandscape;
    if (mask) requestMask(scene, mask);
}

static BOOL containsLyricsFullscreenView(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]) return YES;
    for (UIView *child in view.subviews) if (containsLyricsFullscreenView(child)) return YES;
    return NO;
}

%hook _TtC32Lyrics_FullscreenElementPageImpl14FullscreenView
- (void)didMoveToWindow {
    %orig;
    BOOL here = ((UIView *)self).window != nil;
    dispatch_async(dispatch_get_main_queue(), ^{ pageChanged(here); });
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (containsLyricsFullscreenView(self.view)) dispatch_async(dispatch_get_main_queue(), ^{ pageChanged(YES); });
}
- (void)viewDidDisappear:(BOOL)animated {
    BOOL wasLyrics = containsLyricsFullscreenView(self.view);
    %orig;
    if (wasLyrics) dispatch_async(dispatch_get_main_queue(), ^{ pageChanged(NO); });
}
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
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { deviceOrientationChanged(note); }];
    dispatch_async(dispatch_get_main_queue(), ^{ installDelegateOrientationHook(); });
}
