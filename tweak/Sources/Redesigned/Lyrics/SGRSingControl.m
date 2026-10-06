// Sing's microphone in the player's lyrics (SGRSingControl.h), the way the Music app has its Sing button: a
// round glass button with a microphone on it, and a capsule of glass growing up out of it that holds the
// vocal volume, filled from the bottom to the level. What Sing is doing shows on the button itself, never in
// words beside it:
//
//   off           glass and a white microphone
//   preparing     a ring turning round the microphone over a faint fill, up to the level it gets ready for
//   on            the fill solid white up to the level and the microphone dark on it; closed, a white disc
//   recovering    on, with the ring turning again, dark on the white, while the original covers a gap
//   turning off   off at once; the original audio still queued plays out behind it
//   stopped       off with the microphone dimmed; a tap says why and offers to try again
//
// The slider has two isolation sections:
//
//   bottom       instrumental isolation
//   middle       original mix
//   top          vocal isolation
//
// At the very top, vocals-only is shown in green and gives a small haptic.
//
// A tap turns Sing on and opens the capsule. Open, a tap turns Sing off; closed while Sing is on, a tap
// opens it again. A drag anywhere on it sets the level, opening it first. The capsule closes by itself
// three seconds after the last touch while Sing is on. Sizes move on the Kit's layout spring and colours
// on its crossfade, so Reduce Motion keeps the fades and drops the movement, and the ring pulses in place
// instead of turning. VoiceOver reads the button and the slider out in full.

#import "Core/SGCore.h"
#import "SGRSingControl.h"
#import "Shared/Sing/SGSingController.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import <objc/runtime.h>

static char kControlKey, kPanelGlass;

static const CGFloat kSide = 44;
static const CGFloat kOpenHeight = 144;
static const CGFloat kRingInset = 3.5, kRingWidth = 2.5;
static const CGFloat kFillWhite = 0.88;
static const CGFloat kPendingAlpha = 0.3;
static const CGFloat kStoppedAlpha = 0.45;
static const NSTimeInterval kCollapseAfter = 3, kBusyRecheck = 0.5;
static const float kSpokenStep = 0.1f;

static UIColor *darkGlyph(void) {
    return [UIColor colorWithWhite:0.12 alpha:1];
}

static UIColor *vocalsOnlyGreen(void) {
    return [UIColor colorWithRed:0.20
                            green:0.85
                             blue:0.35
                            alpha:1];
}

static void singSparkle(CGPoint center, CGFloat radius) {
    UIBezierPath *path = [UIBezierPath bezierPath];

    [path moveToPoint:CGPointMake(center.x, center.y - radius)];
    [path addQuadCurveToPoint:CGPointMake(center.x + radius, center.y)
                controlPoint:CGPointMake(center.x + radius * 0.18,
                                         center.y - radius * 0.18)];

    [path addQuadCurveToPoint:CGPointMake(center.x, center.y + radius)
                controlPoint:CGPointMake(center.x + radius * 0.18,
                                         center.y + radius * 0.18)];

    [path addQuadCurveToPoint:CGPointMake(center.x - radius, center.y)
                controlPoint:CGPointMake(center.x - radius * 0.18,
                                         center.y + radius * 0.18)];

    [path addQuadCurveToPoint:CGPointMake(center.x, center.y - radius)
                controlPoint:CGPointMake(center.x - radius * 0.18,
                                         center.y - radius * 0.18)];

    [path closePath];
    [path fill];
}

static UIImage *singGlyph(void) {
    static UIImage *glyph;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28, 28)];

        glyph = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {

            [UIColor.blackColor setFill];
            [UIColor.blackColor setStroke];

            CGContextRef cg = context.CGContext;

            CGContextSaveGState(cg);
            CGContextTranslateCTM(cg, 11.5, 14.5);
            CGContextRotateCTM(cg, M_PI_4);

            UIBezierPath *handle =
                [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-1.6, -4, 3.2, 14.5)
                                          cornerRadius:1.6];

            handle.lineWidth = 1.5;
            [handle stroke];

            UIBezierPath *tip = [UIBezierPath bezierPath];

            [tip moveToPoint:CGPointMake(0, 10.5)];
            [tip addLineToPoint:CGPointMake(0, 13)];

            tip.lineWidth = 1.8;
            tip.lineCapStyle = kCGLineCapRound;
            [tip stroke];

            UIBezierPath *neck = [UIBezierPath bezierPath];

            [neck moveToPoint:CGPointMake(-3.5, -9)];
            [neck addLineToPoint:CGPointMake(-1.8, -4)];
            [neck addLineToPoint:CGPointMake(1.8, -4)];
            [neck addLineToPoint:CGPointMake(3.5, -9)];
            [neck closePath];
            [neck fill];

            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-4.5, -15.5, 9, 9)] fill];

            CGContextSetBlendMode(cg, kCGBlendModeClear);
            CGContextSetLineWidth(cg, 1.25);

            CGContextMoveToPoint(cg, -5, -11);
            CGContextAddLineToPoint(cg, 5, -11);
            CGContextStrokePath(cg);

            CGContextRestoreGState(cg);

            singSparkle(CGPointMake(4.5, 7.5), 3.3);
            singSparkle(CGPointMake(22.5, 18.7), 4.2);
            singSparkle(CGPointMake(14.5, 24), 2.2);

        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });

    return glyph;
}

// What the button shows, worked out from the controller's state alone.
typedef struct {
    BOOL on;
    BOOL preparing;
    BOOL ring;
    BOOL stopped;
} SGRSingLook;

static SGRSingLook lookOf(SGSingState state) {
    return (SGRSingLook){
        .on = SGSingStateIsOn(state),
        .preparing = state == SGSingPreparing,
        .ring = state == SGSingPreparing || state == SGSingRecovering,
        .stopped = state == SGSingFailed,
    };
}

// A vertical, thumb-free slider inside the glass capsule.
@interface SGRVocalSlider : UIControl
@property (nonatomic) float value;
@end

@implementation SGRVocalSlider

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;

    self.backgroundColor = UIColor.clearColor;

    return self;
}

- (void)setValue:(float)value {
    _value = SGSingClampLevel(value);

    if (_value < 0.005f)
        _value = 0;

    if (_value > 1.095f)
        _value = 1.1f;

    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    // The horizontal line at the physical midpoint separates the two
    // isolation sections. The midpoint represents the original mix.
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context)
        return;

    CGFloat y = CGRectGetMidY(rect);

    CGContextSetStrokeColorWithColor(
        context,
        [UIColor colorWithWhite:1 alpha:0.28].CGColor
    );

    CGContextSetLineWidth(context, 1.0);

    CGContextMoveToPoint(context, 7, y);
    CGContextAddLineToPoint(context, CGRectGetWidth(rect) - 7, y);
    CGContextStrokePath(context);
}

- (void)accessibilityIncrement {
    if (!self.enabled)
        return;

    self.value += kSpokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)accessibilityDecrement {
    if (!self.enabled)
        return;

    self.value -= kSpokenStep;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)moveToTouch:(UITouch *)touch {
    CGFloat height = MAX(1, self.bounds.size.height);

    CGFloat position =
        1.0f - [touch locationInView:self].y / height;

    self.value = SGSingLevelFromPosition(position);

    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch
                     withEvent:(UIEvent *)event {
    [self moveToTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch
                        withEvent:(UIEvent *)event {
    [self moveToTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch
                   withEvent:(UIEvent *)event {
    if (touch)
        [self moveToTouch:touch];
}

@end

// Spotify's player also pans to dismiss. A drag starting inside this control belongs to vocal
// volume, including a drag starting on the microphone, rather than to the enclosing player.
@interface SGRVocalPan : UIPanGestureRecognizer
@end

@implementation SGRVocalPan

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

@end

// The ring round the microphone while Sing gets ready.
@interface SGRSingRing : UIView
@property (nonatomic) BOOL turning;
@end

@implementation SGRSingRing {
    CAShapeLayer *_arc;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame]))
        return nil;

    self.userInteractionEnabled = NO;

    _arc = [CAShapeLayer layer];
    _arc.fillColor = UIColor.clearColor.CGColor;
    _arc.lineWidth = kRingWidth;
    _arc.lineCap = kCALineCapRound;

    [self.layer addSublayer:_arc];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(sgr_animate)
               name:UIAccessibilityReduceMotionStatusDidChangeNotification
             object:nil];

    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.bounds;

    CGFloat radius =
        MIN(bounds.size.width, bounds.size.height) / 2 - kRingInset;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _arc.frame = bounds;

    _arc.path =
        [UIBezierPath
            bezierPathWithArcCenter:
                CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            radius:MAX(0, radius)
            startAngle:-M_PI_2
            endAngle:3 * M_PI_2
            clockwise:YES].CGPath;

    [CATransaction commit];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    _arc.strokeColor = self.tintColor.CGColor;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self sgr_animate];
}

- (void)setTurning:(BOOL)turning {
    if (_turning == turning)
        return;

    _turning = turning;
    [self sgr_animate];
}

- (void)sgr_animate {
    [_arc removeAllAnimations];

    if (!_turning || !self.window)
        return;

    BOOL still = SGRReduceMotion();

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _arc.strokeEnd = still ? 1 : 0.28;

    [CATransaction commit];

    CABasicAnimation *animation;

    if (still) {
        animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @1;
        animation.toValue = @0.3;
        animation.duration = 0.9;
        animation.autoreverses = YES;

        animation.timingFunction =
            [CAMediaTimingFunction
                functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    } else {
        animation =
            [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];

        animation.fromValue = @0;
        animation.toValue = @(2 * M_PI);
        animation.duration = 1;
    }

    animation.repeatCount = HUGE_VALF;

    [_arc addAnimation:animation forKey:@"sgr.ring"];
}

@end

@interface SGRSingControl : UIView <UIGestureRecognizerDelegate>

@property (nonatomic) UIButton *button;
@property (nonatomic) UIImageView *glyph, *glyphOn;
@property (nonatomic) SGRSingRing *ring;

@property (nonatomic) UIView *panel, *fill;
@property (nonatomic) SGRVocalSlider *slider;
@property (nonatomic) SGRVocalPan *pan;
@property (nonatomic) UITapGestureRecognizer *outside;

@property (nonatomic, copy) void (^hold)(BOOL);

@property (nonatomic) CGPoint anchor;
@property (nonatomic) float dragLevel;
@property (nonatomic) float dragPosition;
@property (nonatomic) CGPoint dragStart;
@property (nonatomic) CGFloat stretch;

@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL expanded;
@property (nonatomic) BOOL explaining;
@property (nonatomic) BOOL immersive;
@property (nonatomic) BOOL holding;
@property (nonatomic) BOOL wasOn;

@property (nonatomic) BOOL hapticAtVocalsOnly;

@property (nonatomic) SGSingState shown;
@property (nonatomic) float shownLevel;

@property (nonatomic) CFTimeInterval collapseDeadline;
@property (nonatomic) NSTimer *collapseTimer;

- (void)refresh;
- (void)updateHold;

@end

@implementation SGRSingControl

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame]))
        return nil;

    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _panel = [UIView new];
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel.clipsToBounds = NO;

    [self addSubview:_panel];

    _pan = [[SGRVocalPan alloc]
        initWithTarget:self
                action:@selector(dragged:)];

    _pan.delegate = self;
    _pan.maximumNumberOfTouches = 1;

    [_panel addGestureRecognizer:_pan];

    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    _fill.backgroundColor =
        [UIColor colorWithWhite:1 alpha:kFillWhite];

    _slider = [SGRVocalSlider new];

    _slider.accessibilityLabel = @"Sing isolation";
    _slider.accessibilityHint =
        @"Bottom is instrumental only, middle is the original mix, top is vocals only";
    _slider.accessibilityIdentifier = @"sing.vocalLevel";

    [_slider addTarget:self
                action:@selector(changed)
      forControlEvents:UIControlEventValueChanged];

    _button = [UIButton buttonWithType:UIButtonTypeCustom];

    _button.accessibilityIdentifier = @"sing.microphone";

    [_button addTarget:self
                action:@selector(tapped)
      forControlEvents:UIControlEventTouchUpInside];

    [_button addGestureRecognizer:
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(held:)]];

    _ring = [SGRSingRing new];

    _glyph = [[UIImageView alloc] initWithImage:singGlyph()];
    _glyph.tintColor = SGRPrimary();

    _glyphOn = [[UIImageView alloc] initWithImage:singGlyph()];
    _glyphOn.tintColor = darkGlyph();

    for (UIView *view in @[_ring, _glyph, _glyphOn]) {
        view.userInteractionEnabled = NO;
        view.contentMode = UIViewContentModeCenter;
        [_button addSubview:view];
    }

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(refresh)
               name:SGSingDidChangeNotification
             object:nil];

    _shown = SGSingCurrentState();
    _shownLevel = SGSingVocalLevel();

    [self refreshAnimated:NO];

    return self;
}

- (void)dealloc {
    [_collapseTimer invalidate];

    [_outside.view removeGestureRecognizer:_outside];

    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - what it shows

- (void)updateHold {
    SGSingState state = SGSingCurrentState();

    BOOL held =
        _expanded ||
        _explaining ||
        state == SGSingPreparing ||
        state == SGSingDraining;

    if (!_hold)
        return;

    if (held || held != _holding)
        _hold(held);

    _holding = held;
}

- (void)updateVisibility {
    BOOL visible =
        !_immersive ||
        SGSingStateIsOn(SGSingCurrentState());

    self.alpha = visible ? 1 : 0;
    self.accessibilityElementsHidden = !visible;
}

// Green is reserved specifically for the true vocals-only endpoint.
- (void)updateIsolationAppearance {
    BOOL vocalsOnly = _slider.value >= 1.095f;

    if (vocalsOnly) {
        _fill.backgroundColor =
            [vocalsOnlyGreen() colorWithAlphaComponent:kFillWhite];

        _slider.tintColor = vocalsOnlyGreen();
    } else {
        _fill.backgroundColor =
            [UIColor colorWithWhite:1 alpha:kFillWhite];

        _slider.tintColor = SGRPrimary();
    }

    [_slider setNeedsDisplay];
}

// The colours: the fill's strength, which microphone shows, the ring.
- (void)applyLook {
    SGRSingLook look = lookOf(_shown);

    _fill.alpha =
        look.on ? 1 :
        look.preparing ? kPendingAlpha :
        0;

    _glyphOn.alpha = look.on ? 1 : 0;

    _glyph.alpha =
        look.on ? 0 :
        look.stopped ? kStoppedAlpha :
        1;

    _ring.alpha = look.ring ? 1 : 0;

    _ring.tintColor =
        look.on ? darkGlyph() :
        SGRPrimary();

    [self updateIsolationAppearance];
}

- (void)checkVocalsOnlyHaptic {
    BOOL vocalsOnly = _slider.value >= 1.095f;

    if (vocalsOnly && !_hapticAtVocalsOnly) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleLight];

        [generator prepare];
        [generator impactOccurred];
    }

    _hapticAtVocalsOnly = vocalsOnly;
}

- (void)describe {
    SGSingState state = _shown;
    SGRSingLook look = lookOf(state);

    BOOL instrumentalOnly = _slider.value <= 0.005f;
    BOOL original = fabsf(_slider.value - 1) < 0.005f;
    BOOL vocalsOnly = _slider.value >= 1.095f;

    NSString *sliderValue;

    if (instrumentalOnly) {
        sliderValue = @"Instrumental only";
    } else if (original) {
        sliderValue = @"Original mix";
    } else if (vocalsOnly) {
        sliderValue = @"Vocals only";
    } else if (_slider.value < 1.0f) {
        float isolation = (1.0f - _slider.value) * 100.0f;

        sliderValue =
            [NSString stringWithFormat:
                @"Instrumental isolation, %.0f percent",
                isolation];
    } else {
        float isolation =
            ((_slider.value - 1.0f) / 0.1f) * 100.0f;

        sliderValue =
            [NSString stringWithFormat:
                @"Vocal isolation, %.0f percent",
                isolation];
    }

    _slider.accessibilityValue = sliderValue;

    _button.accessibilityLabel = @"Sing";

    _button.accessibilityValue =
        state == SGSingPreparing
            ? @"Preparing Sing"
        : state == SGSingRecovering
            ? @"Restoring Sing"
        : state == SGSingDraining
            ? @"Turning Sing off"
        : state == SGSingFailed
            ? @"Sing stopped"
        : look.on
            ? (vocalsOnly
                ? @"On, vocals only"
                : original
                    ? @"On, original mix"
                    : [NSString stringWithFormat:
                        @"On, %@", sliderValue])
        : @"Off";

    _button.accessibilityHint =
        state == SGSingPreparing
            ? @"Tap to cancel."
        : state == SGSingDraining
            ? @"Tap to turn Sing back on."
        : state == SGSingFailed
            ? @"Tap to hear why Sing stopped."
        : look.on
            ? (_expanded
                ? @"Tap to turn Sing off. Drag to adjust vocal or instrumental isolation."
                : @"Tap for Sing isolation controls.")
        : @"Turns the song's vocals down on this iPhone.";

    _button.accessibilityTraits =
        UIAccessibilityTraitButton |
        (look.on ? UIAccessibilityTraitSelected : 0);

    __weak typeof(self) weak = self;

    _button.accessibilityCustomActions =
        look.on || look.preparing
            ? @[
                [[UIAccessibilityCustomAction alloc]
                    initWithName:@"Turn Off Sing"
                    actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
                        [weak turnOff];
                        return YES;
                    }]
              ]
            : nil;
}

- (void)refresh {
    [self refreshAnimated:self.window != nil];
}

- (void)refreshAnimated:(BOOL)animated {
    SGSingState state = SGSingCurrentState();
    SGRSingLook look = lookOf(state);

    if (look.on && !_wasOn)
        [self interacted];

    _wasOn = look.on;

    BOOL changed = state != _shown;

    float level = SGSingVocalLevel();
    BOOL moved = level != _shownLevel;

    _shown = state;
    _shownLevel = level;

    _slider.enabled =
        look.on ||
        look.preparing;

    _slider.value = level;

    [self describe];

    if (!look.on && !look.preparing)
        self.expanded = NO;

    [self updateHold];
    [self updateVisibility];
    [self setNeedsLayout];

    if (_dragging || !animated) {
        [self applyLook];

        _ring.turning = look.ring;

        [self layoutIfNeeded];

        return;
    }

    if (changed || moved)
        SGRAnimate(SGRMotionLayout, ^{
            [self layoutIfNeeded];
        }, nil);

    if (!changed) {
        if (moved)
            [self applyLook];

        return;
    }

    if (look.ring)
        _ring.turning = YES;

    __weak typeof(self) weak = self;

    SGRAnimate(SGRMotionFade, ^{
        [self applyLook];
    }, ^(BOOL finished) {
        typeof(self) self = weak;

        if (self)
            self.ring.turning = lookOf(self.shown).ring;
    });
}

#pragma mark - opening and closing

- (void)setAnchor:(CGPoint)anchor {
    if (CGPointEqualToPoint(_anchor, anchor) &&
        self.frame.size.width > 0)
        return;

    _anchor = anchor;

    [self placeAnimated:NO];
}

- (void)placeAnimated:(BOOL)animated {
    void (^place)(void) = ^{
        CGFloat height =
            self.expanded
                ? kOpenHeight
                : kSide;

        self.frame =
            CGRectMake(
                self.anchor.x,
                self.anchor.y + kSide - height,
                kSide,
                height
            );

        [self layoutIfNeeded];
    };

    if (animated)
        SGRAnimate(SGRMotionLayout, place, nil);
    else
        place();
}

- (void)setExpanded:(BOOL)expanded {
    if (_expanded == expanded)
        return;

    _expanded = expanded;

    if (expanded) {
        [self interacted];
    } else {
        [_collapseTimer invalidate];
        _collapseTimer = nil;
    }

    [self describe];
    [self updateHold];

    [self placeAnimated:
        !_dragging && self.window];
}

- (void)interacted {
    _collapseDeadline =
        CACurrentMediaTime() + kCollapseAfter;

    [self scheduleCollapse:kCollapseAfter];
}

- (void)scheduleCollapse:(NSTimeInterval)wait {
    [_collapseTimer invalidate];
    _collapseTimer = nil;

    if (!_expanded)
        return;

    __weak typeof(self) weak = self;

    _collapseTimer =
        [NSTimer
            timerWithTimeInterval:MAX(wait, 0.1)
            repeats:NO
            block:^(NSTimer *timer) {
                [weak collapseIfIdle];
            }];

    [NSRunLoop.mainRunLoop
        addTimer:_collapseTimer
        forMode:NSRunLoopCommonModes];
}

- (void)collapseIfIdle {
    _collapseTimer = nil;

    if (!_expanded || !self.window)
        return;

    BOOL busy =
        !SGSingStateIsOn(SGSingCurrentState()) ||
        _dragging ||
        _slider.tracking ||
        _button.tracking ||
        UIAccessibilityIsVoiceOverRunning();

    for (UIGestureRecognizer *gesture in _button.gestureRecognizers) {
        busy |=
            gesture.state == UIGestureRecognizerStateBegan ||
            gesture.state == UIGestureRecognizerStateChanged;
    }

    NSTimeInterval left =
        _collapseDeadline - CACurrentMediaTime();

    if (!busy && left <= 0) {
        self.expanded = NO;
    } else {
        [self scheduleCollapse:
            busy ? kBusyRecheck : left];
    }
}

- (void)dismissControls {
    self.expanded = NO;
}

#pragma mark - layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat stretch =
        _expanded && !SGRReduceMotion()
            ? _stretch
            : 0;

    CGFloat extension = fabs(stretch) * 16;
    CGFloat width = kSide + fabs(stretch) * 2;

    _panel.frame =
        CGRectMake(
            (kSide - width) / 2,
            -extension / 2 + stretch * 6,
            width,
            CGRectGetHeight(self.bounds) + extension
        );

    UIView *glass =
        SGRGlassCapsuleInside(
            _panel,
            &kPanelGlass,
            _panel.bounds.size,
            NO
        );

    UIView *content = glass;

    if ([glass isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *pane = (id)glass;

        if (@available(iOS 26.0, *)) {
            if ([pane.effect isKindOfClass:UIGlassEffect.class] &&
                !((UIGlassEffect *)pane.effect).interactive) {

                UIGlassEffect *effect =
                    [(UIGlassEffect *)pane.effect copy];

                effect.interactive = YES;
                pane.effect = effect;
            }
        }

        content = pane.contentView;
    }

    glass.userInteractionEnabled = YES;
    glass.accessibilityElementsHidden = NO;

    content.clipsToBounds = YES;
    content.layer.cornerRadius = width / 2;

    for (UIView *view in @[_fill, _button]) {
        if (view.superview != content)
            [content addSubview:view];
    }

    if (_expanded) {
        if (_slider.superview != content)
            [content insertSubview:_slider
                      belowSubview:_button];
    } else {
        [_slider removeFromSuperview];
    }

    CGFloat height = CGRectGetHeight(_panel.bounds);

    SGRSingLook look = lookOf(_shown);

    CGFloat fill =
        look.on || look.preparing
            ? kSide +
                (height - kSide) *
                SGSingPositionFromLevel(
                    SGSingVocalLevel())
            : 0;

    _fill.frame =
        CGRectMake(
            0,
            height - fill,
            width,
            fill
        );

    _slider.frame =
        CGRectMake(
            0,
            0,
            width,
            height - kSide
        );

    _button.frame =
        CGRectMake(
            0,
            height - kSide,
            width,
            kSide
        );

    CGRect square =
        CGRectMake(
            (width - kSide) / 2,
            0,
            kSide,
            kSide
        );

    for (UIView *view in @[_ring, _glyph, _glyphOn])
        view.frame = square;

    [_slider setNeedsDisplay];
}

- (BOOL)pointInside:(CGPoint)point
           withEvent:(UIEvent *)event {
    return CGRectContainsPoint(_panel.frame, point);
}

#pragma mark - touches

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
       shouldReceiveTouch:(UITouch *)touch {

    if (gesture == _outside)
        return _expanded &&
            ![touch.view isDescendantOfView:self];

    [self interacted];

    SGSingState state = SGSingCurrentState();

    _dragStart =
        [touch locationInView:self.superview];

    if ([touch.view isDescendantOfView:_slider]) {
        CGFloat height =
            MAX(1, _slider.bounds.size.height);

        _dragPosition =
            SGSingPositionFromLevel(
                SGSingVocalLevel());

        CGFloat touchPosition =
            1.0f -
            [touch locationInView:_slider].y /
            height;

        _dragLevel =
            SGSingLevelFromPosition(touchPosition);

    } else {
        _dragLevel = SGSingVocalLevel();
        _dragPosition =
            SGSingPositionFromLevel(_dragLevel);
    }

    return
        SGSingStateIsOn(state) ||
        state == SGSingPreparing ||
        state == SGSingIdle;
}

- (void)tapped {
    [self interacted];

    SGSingState state = SGSingCurrentState();

    if (state == SGSingFailed)
        [self showExplanation];

    else if (state == SGSingPreparing ||
             (SGSingStateIsOn(state) && _expanded))
        [self turnOff];

    else if (SGSingStateIsOn(state))
        self.expanded = YES;

    else if (state == SGSingIdle ||
             state == SGSingDraining)
        [self turnOn];
}

- (void)turnOn {
    SGSingSetVocalLevel(SGSingReducedLevel());
    SGSingSetEnabled(YES);

    if (SGSingCurrentState() == SGSingFailed)
        [self showExplanation];
    else
        self.expanded = YES;
}

- (void)turnOff {
    SGSingSetEnabled(NO);
    self.expanded = NO;
}

- (void)expand {
    SGSingState state = SGSingCurrentState();

    if (state == SGSingIdle)
        [self turnOn];

    else if (SGSingStateIsOn(state) ||
             state == SGSingPreparing)
        self.expanded = YES;
}

- (void)dragged:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragging = YES;
        [self expand];
    }

    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged ||
        gesture.state == UIGestureRecognizerStateEnded) {

        // Measure the drag in physical slider space.
        // This keeps both isolation sections the same physical size.
        CGFloat travel =
            [gesture locationInView:self.superview].y -
            _dragStart.y;

        _stretch =
            travel /
            (kSide + fabs(travel));

        CGFloat position =
            _dragPosition -
            travel / 100.0f;

        position =
            fmaxf(0.0f,
                  fminf(1.0f, position));

        _slider.value =
            SGSingLevelFromPosition(position);

        [self changed];
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {

        _dragging = NO;
        _stretch = 0;

        [self setNeedsLayout];

        SGRAnimate(SGRMotionLayout, ^{
            [self layoutIfNeeded];
        }, nil);
    }
}

- (void)held:(UILongPressGestureRecognizer *)gesture {
    [self interacted];

    if (gesture.state == UIGestureRecognizerStateBegan)
        [self expand];

    if (gesture.state == UIGestureRecognizerStateChanged &&
        SGSingStateIsOn(SGSingCurrentState())) {

        CGPoint point =
            [gesture locationInView:_slider];

        CGFloat position =
            1.0f -
            point.y /
            MAX(1, _slider.bounds.size.height);

        _slider.value =
            SGSingLevelFromPosition(position);

        [self changed];
    }
}

- (void)changed {
    [self interacted];

    SGSingSetVocalLevel(_slider.value);

    [self updateIsolationAppearance];
    [self checkVocalsOnlyHaptic];

    [self describe];
    [self setNeedsLayout];
}

#pragma mark - explaining

- (UIViewController *)presenter {
    for (UIResponder *r = self;
         r;
         r = r.nextResponder) {

        if ([r isKindOfClass:UIViewController.class])
            return (id)r;
    }

    return nil;
}

- (void)finishedExplaining {
    _explaining = NO;
    [self updateHold];
}

- (void)showExplanation {
    UIViewController *presenter = [self presenter];

    if (!presenter ||
        presenter.presentedViewController ||
        _explaining)
        return;

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"Sing"
            message:SGSingExplanation()
            preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weak = self;

    [alert
        addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *action) {
                    [weak finishedExplaining];
                }]];

    if (SGSingCanRetry()) {
        [alert
            addAction:
                [UIAlertAction
                    actionWithTitle:@"Try again"
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {

                        [weak finishedExplaining];

                        if (SGSingCanRetry())
                            [weak turnOn];
                    }]];
    }

    if (SGSingCurrentState() == SGSingFailed) {
        [alert
            addAction:
                [UIAlertAction
                    actionWithTitle:@"Turn off Sing"
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {

                        [weak finishedExplaining];
                        [weak turnOff];
                    }]];
    }

    _explaining = YES;

    [self updateHold];

    [presenter
        presentViewController:alert
        animated:YES
        completion:nil];
}

#pragma mark - retirement

- (void)retireFrom:(UIView *)page {
    if (_holding && _hold)
        _hold(NO);

    _holding = NO;

    [_collapseTimer invalidate];
    _collapseTimer = nil;

    [_outside.view removeGestureRecognizer:_outside];

    [self removeFromSuperview];

    objc_setAssociatedObject(
        page,
        &kControlKey,
        nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

@end

UIView *SGRSingControlForPage(
    UIView *page,
    CGRect lyrics,
    BOOL immersive,
    void (^hold)(BOOL)
) {
    SGRSingControl *control =
        page
            ? objc_getAssociatedObject(page, &kControlKey)
            : nil;

    if (!SGSingAvailable()) {
        [control retireFrom:page];
        return nil;
    }

    if (!page || CGRectIsEmpty(lyrics))
        return nil;

    if (!control) {
        control =
            [[SGRSingControl alloc]
                initWithFrame:CGRectZero];

        objc_setAssociatedObject(
            page,
            &kControlKey,
            control,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        [page addSubview:control];

        control.outside =
            [[UITapGestureRecognizer alloc]
                initWithTarget:control
                        action:@selector(dismissControls)];

        control.outside.cancelsTouchesInView = NO;
        control.outside.delegate = control;
    }

    UIView *surface =
        page.superview ?: page;

    if (control.outside.view != surface)
        [surface addGestureRecognizer:control.outside];

    control.hold = hold;
    control.immersive = immersive;

    [control updateHold];
    [control updateVisibility];

    control.anchor =
        CGPointMake(
            CGRectGetMaxX(lyrics) - 56,
            CGRectGetMaxY(lyrics) - 56
        );

    [page bringSubviewToFront:control];

    return control;
}

void SGRSingControlDismiss(UIView *page) {
    SGRSingControl *control =
        objc_getAssociatedObject(page, &kControlKey);

    [control dismissControls];
}
