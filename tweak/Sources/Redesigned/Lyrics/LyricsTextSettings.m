// Drag the three texts of a line into size order, largest first.
#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsText.h"
#import "LandscapeLyrics.h"

@interface SGRLyricsTextPage : SGPage
@end

@implementation SGRLyricsTextPage {
    NSMutableArray<NSNumber *> *_order;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Text sizes";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _order = [SGRLyricsTextOrder() mutableCopy];
    self.tableView.editing = YES;
    _footer = SGNote(@"Pronunciation and translation are turned on from the button in the lyrics' corner.");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_order.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, @"Largest first");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"text");
    SGRLyricsText text = _order[(NSUInteger)path.row].integerValue;
    NSArray<NSString *> *sizes = @[@"Largest", @"Smaller", @"Smallest"];
    NSString *symbol = text == SGRLyricsTextLyrics ? @"music.mic" : text == SGRLyricsTextPronunciation ? @"character.phonetic" : @"character.bubble";
    SGFillCell(cell, SGRLyricsTextName(text), sizes[MIN((NSUInteger)path.row, sizes.count - 1)], nil, symbol);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSNumber *text = _order[(NSUInteger)from.row];
    [_order removeObjectAtIndex:(NSUInteger)from.row];
    [_order insertObject:text atIndex:(NSUInteger)to.row];
    SGRSetLyricsTextOrder(_order);
    [table reloadData];   // the sizes under the names have all moved
}

@end

SGModRow *SGRLyricsTextSizesRow(void) {
    return SGPageRow(@"Text sizes", ^UIViewController *{ return [SGRLyricsTextPage new]; });
}

SGModRow *SGRLyricsLandscapeRow(void) {
    SGModRow *row = SGOptionRow(@"Landscape lyrics", @"The lyrics page turns with the phone", SGRKeyLyricsLandscape);
    row.info = @"While the full screen lyrics page is open, Spotify turns to landscape when the phone does, the lyrics reflowing "
               "across the wider screen, and goes back upright when you close it. Nothing else in the app turns. "
               "Rotation lock in Control Center still decides whether the phone turns at all.";
    return row;
}



#pragma mark - Lyrics style preview

static const CGFloat kLyricsStylePreviewHeight = 220.0;

@interface SGRLyricsStylePreview : UIView
@end

@implementation SGRLyricsStylePreview {
    CAGradientLayer *_gradient;
    UILabel *_currentLabel;
    UILabel *_nextLabel;
    CADisplayLink *_link;
    NSArray<NSString *> *_examples;
    NSInteger _exampleIndex;
    NSInteger _wordIndex;
    CFTimeInterval _lineStartedAt;
    CGFloat _wordProgress;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;

    _examples = @[
        @"Paper boats on a river of light",
        @"Carry the words we forgot to say",
        @"And watch you sabotage",
        @"We are still finding our way home",
        @"Nothing lasts forever but this moment does"
    ];
    _exampleIndex = 0;
    _wordIndex = 0;
    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerRadius = 24.0;
    self.clipsToBounds = YES;

    _gradient = [CAGradientLayer layer];
    _gradient.colors = @[
        (id)[UIColor colorWithRed:0.14 green:0.28 blue:0.48 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.35 green:0.30 blue:0.52 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.12 green:0.42 blue:0.43 alpha:1].CGColor
    ];
    _gradient.startPoint = CGPointMake(0.05, 0.10);
    _gradient.endPoint = CGPointMake(0.95, 0.90);
    [self.layer insertSublayer:_gradient atIndex:0];

    _currentLabel = [UILabel new];
    _currentLabel.numberOfLines = 0;
    _currentLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _currentLabel.textAlignment = NSTextAlignmentLeft;
    _currentLabel.layer.masksToBounds = NO;
    [self addSubview:_currentLabel];

    _nextLabel = [UILabel new];
    _nextLabel.numberOfLines = 0;
    _nextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _nextLabel.textAlignment = NSTextAlignmentLeft;
    _nextLabel.layer.masksToBounds = NO;
    [self addSubview:_nextLabel];

    [NSNotificationCenter.defaultCenter addObserver:self
                                             selector:@selector(styleDidChange:)
                                                 name:SGRLyricsTextDidChangeNotification
                                               object:nil];

    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _lineStartedAt = CACurrentMediaTime();
    [self refreshPreview];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_link invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
    CGFloat inset = 22.0;
    CGFloat width = MAX(1.0, self.bounds.size.width - inset * 2.0);
    CGFloat size = SGRLyricsStyleFontSize();
    CGSize fitting = [_currentLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat currentHeight = MIN(MAX(size * 1.15, fitting.height), self.bounds.size.height * 0.64);
    CGFloat currentY = 26.0;
    _currentLabel.frame = CGRectMake(inset, currentY, width, currentHeight);
    // Line spacing is the gap between the active and upcoming lyric rows, not paragraph spacing.
    CGFloat nextY = CGRectGetMaxY(_currentLabel.frame) + SGRLyricsStyleLineGap();
    CGFloat nextHeight = 32.0;
    if (nextY + nextHeight > self.bounds.size.height - 12.0)
        nextY = MAX(currentY + currentHeight + 4.0, self.bounds.size.height - nextHeight - 12.0);
    _nextLabel.frame = CGRectMake(inset, nextY, width, nextHeight);
}

- (void)styleDidChange:(NSNotification *)notification {
    [self setNeedsLayout];
    [self refreshPreview];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    NSArray<NSString *> *words = [_examples[_exampleIndex] componentsSeparatedByString:@" "];
    const CFTimeInterval wordDuration = 0.58;
    CFTimeInterval elapsed = MAX(0, now - _lineStartedAt);
    NSInteger step = (NSInteger)(elapsed / wordDuration);
    if (step >= (NSInteger)words.count) {
        NSInteger nextIndex = (_exampleIndex + 1) % (NSInteger)_examples.count;
        _exampleIndex = nextIndex;
        _lineStartedAt = now;
        _wordProgress = 0;
            _currentLabel.alpha = 0.25;
        _currentLabel.transform = CGAffineTransformMakeTranslation(0, 8);
        [self refreshPreview];
        [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
            self->_currentLabel.alpha = 1;
            self->_currentLabel.transform = CGAffineTransformIdentity;
        } completion:nil];
        return;
    }
    _wordIndex = step;
    _wordProgress = (CGFloat)((elapsed - step * wordDuration) / wordDuration);
    // Keep the small preview lightweight: update text only when the swept word changes or the highlight
    // has moved enough to be visibly smooth at ordinary display rates.
    [self refreshPreview];
}

- (void)refreshPreview {
    if (!_currentLabel || !_nextLabel) return;

    CGFloat size = SGRLyricsStyleFontSize();
    CGFloat weight = SGRLyricsStyleFontWeight();
    CGFloat dim = SGRLyricsStyleDim();
    CGFloat blur = SGRLyricsStyleBlur();
    CGFloat bloom = SGRLyricsStyleBloom() / 100.0;

    NSString *text = _examples[_exampleIndex];
    NSArray<NSString *> *words = [text componentsSeparatedByString:@" "];
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentLeft;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.lineSpacing = 2.0; // independent of the current-to-next lyric spacing control

    NSMutableAttributedString *current = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange all = NSMakeRange(0, current.length);
    [current addAttribute:NSFontAttributeName value:font range:all];
    [current addAttribute:NSForegroundColorAttributeName
                    value:[UIColor colorWithWhite:1 alpha:MAX(0.18, 1.0 - dim)]
                    range:all];
    [current addAttribute:NSParagraphStyleAttributeName value:paragraph range:all];

    NSUInteger location = 0;
    for (NSInteger i = 0; i < (NSInteger)words.count; i++) {
        NSString *word = words[i];
        NSRange wordRange = NSMakeRange(location, word.length);
        CGFloat alpha = i < _wordIndex ? 1.0 : (i == _wordIndex ? MAX(0.18, (1.0 - dim) + (1.0 - MAX(0.18, 1.0 - dim)) * _wordProgress) : MAX(0.18, 1.0 - dim));
        [current addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:1 alpha:alpha] range:wordRange];
        if (i == _wordIndex && bloom > 0) {
            NSShadow *shadow = [NSShadow new];
            shadow.shadowColor = [UIColor colorWithWhite:1 alpha:MIN(0.9, bloom)];
            shadow.shadowBlurRadius = 5.0 + 16.0 * bloom;
            shadow.shadowOffset = CGSizeZero;
            [current addAttribute:NSShadowAttributeName value:shadow range:wordRange];
        }
        location += word.length + 1;
    }

    _currentLabel.attributedText = current;
    NSString *nextText = _examples[(_exampleIndex + 1) % (NSInteger)_examples.count];
    UIFont *nextFont = [UIFont systemFontOfSize:MAX(14.0, size * 0.58) weight:weight];
    _nextLabel.attributedText = [[NSAttributedString alloc] initWithString:nextText attributes:@{
        NSFontAttributeName: nextFont,
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:MAX(0.12, dim * 0.75)]
    }];
    _nextLabel.layer.filters = blur > 0 ? @[[self blurFilterWithRadius:blur]] : nil;
    [self setNeedsLayout];
}

- (id)blurFilterWithRadius:(CGFloat)radius {
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setValue:@(radius) forKey:kCIInputRadiusKey];
    return filter;
}

@end

#pragma mark - Lyrics styles

static CGFloat SGRLyricsStyleDefaultFontSize(void) {
    return 30.0;
}

static CGFloat SGRLyricsStyleDefaultFontWeight(void) {
    return UIFontWeightBold;
}

static CGFloat SGRLyricsStyleDefaultLineGap(void) { return 24.0; }
static CGFloat SGRLyricsStyleDefaultDim(void) { return 0.30; }
static CGFloat SGRLyricsStyleDefaultBlur(void) { return 6.0; }
static CGFloat SGRLyricsStyleDefaultBloom(void) { return 0.0; }

CGFloat SGRLyricsStyleFontSize(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleFontSize];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultFontSize();
}

CGFloat SGRLyricsStyleFontWeight(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsStyleFontWeight];
    if (![stored respondsToSelector:@selector(doubleValue)]) return SGRLyricsStyleDefaultFontWeight();
    CGFloat value = (CGFloat)[stored doubleValue];
    return MIN(UIFontWeightBlack, MAX(UIFontWeightUltraLight, value));
}

CGFloat SGRLyricsStyleLineGap(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleLineGap];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultLineGap();
}
CGFloat SGRLyricsStyleDim(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleDim];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultDim();
}
CGFloat SGRLyricsStyleBlur(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleBlur];
    return value >= 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultBlur();
}
CGFloat SGRLyricsStyleBloom(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleBloom];
    return value >= 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultBloom();
}

static void SGRSetLyricsStylePreset(NSInteger preset) {
    CGFloat size = 30.0, weight = UIFontWeightBold, gap = 24.0, dim = 0.30, blur = 6.0, bloom = 0.0;

    switch (preset) {
        case 1: // Subtle
            size = 27.0; weight = UIFontWeightRegular; gap = 20.0; dim = 0.22; blur = 4.0;
            break;
        case 2: // Bold
            size = 33.0; weight = UIFontWeightBlack; gap = 28.0; dim = 0.35; blur = 8.0; bloom = 35.0;
            break;
        default: // Default
            break;
    }

    [NSUserDefaults.standardUserDefaults setDouble:size forKey:SGRKeyLyricsStyleFontSize];
    [NSUserDefaults.standardUserDefaults setDouble:weight forKey:SGRKeyLyricsStyleFontWeight];
    [NSUserDefaults.standardUserDefaults setDouble:gap forKey:SGRKeyLyricsStyleLineGap];
    [NSUserDefaults.standardUserDefaults setDouble:dim forKey:SGRKeyLyricsStyleDim];
    [NSUserDefaults.standardUserDefaults setDouble:blur forKey:SGRKeyLyricsStyleBlur];
    [NSUserDefaults.standardUserDefaults setDouble:bloom forKey:SGRKeyLyricsStyleBloom];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}

SGModRow *SGRLyricsStyleRow(void) {
    SGModRow *row = SGChoiceRow(@"Lyrics style", @"Choose the overall appearance", SGRKeyLyricsStyle,
                                @[@"Default", @"Subtle", @"Bold"], 0);
    row.chosen = ^(NSInteger index) {
        [NSUserDefaults.standardUserDefaults setInteger:index forKey:SGRKeyLyricsStyle];
        SGRSetLyricsStylePreset(index);
    };
    return row;
}

SGModRow *SGRLyricsStylePreviewRow(void) {
    return SGViewRow([SGRLyricsStylePreview new], kLyricsStylePreviewHeight);
}

static void SGRLyricsStyleSet(CGFloat value, NSString *key) {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}
static SGModRow *SGRLyricsStyleSlider(NSString *title, NSString *detail, double min, double max, double step,
                                       NSString *key, double (^getter)(void), NSString *(^formatter)(double)) {
    return SGSliderRow(title, detail, min, max, step, getter, ^(double value) {
        SGRLyricsStyleSet((CGFloat)value, key);
    }, formatter);
}
SGModRow *SGRLyricsStyleTuneRow(void) { return SGRLyricsStyleCustomizeRow(); }
SGModRow *SGRLyricsStyleCustomizeRow(void) {
    return SGPageRow(@"Customize lyrics", ^{
        SGModPage *page = [[SGModPage alloc] initWithTitle:@"Customize lyrics"
            intro:@"Changes apply immediately."
            sections:@[
                SGSection(nil, @[SGRLyricsStylePreviewRow()]),
                SGSection(@"Text", @[
                    SGRLyricsStyleSlider(@"Size", @"Overall lyric size", 20.0, 44.0, 1.0, SGRKeyLyricsStyleFontSize, ^double { return SGRLyricsStyleFontSize(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f pt", v]; }),
                    SGRLyricsStyleSlider(@"Weight", @"Font weight", UIFontWeightUltraLight, UIFontWeightBlack, 0.05, SGRKeyLyricsStyleFontWeight, ^double { return SGRLyricsStyleFontWeight(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.2f", v]; }),
                    SGRLyricsStyleSlider(@"Line spacing", @"Space between lyric lines", 8.0, 44.0, 1.0, SGRKeyLyricsStyleLineGap, ^double { return SGRLyricsStyleLineGap(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f pt", v]; }),
                    SGRLyricsStyleSlider(@"Inactive opacity", @"Brightness of lyrics that are not being sung", 0.10, 0.70, 0.01, SGRKeyLyricsStyleDim, ^double { return SGRLyricsStyleDim(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v * 100.0]; })
                ]),
                SGSection(@"Effects", @[
                    SGRLyricsStyleSlider(@"Distant blur", @"Blur on lines farther from the current line", 0.0, 12.0, 0.5, SGRKeyLyricsStyleBlur, ^double { return SGRLyricsStyleBlur(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.1f", v]; }),
                    SGRLyricsStyleSlider(@"Bloom / glare", @"Glow on the sung line", 0.0, 100.0, 1.0, SGRKeyLyricsStyleBloom, ^double { return SGRLyricsStyleBloom(); }, ^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v]; })
                ]),
                SGSection(@"Preset", @[SGRLyricsStyleRow()]),
                SGSection(@"Lyrics", @[SGRLyricsTextSizesRow()])
            ] footer:nil];
        return page;
    });
}
