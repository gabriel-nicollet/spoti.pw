// Drag the three texts of a line into size order, largest first.
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

static const CGFloat kLyricsStylePreviewHeight = 180.0;

@interface SGRLyricsStylePreview : UIView
@end

@implementation SGRLyricsStylePreview

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerRadius = 24.0;
    self.clipsToBounds = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                             selector:@selector(styleDidChange:)
                                                 name:SGRLyricsTextDidChangeNotification
                                               object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)styleDidChange:(NSNotification *)notification {
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGFloat size = SGRLyricsStyleFontSize();
    CGFloat weight = SGRLyricsStyleFontWeight();

    UIFont *current = [UIFont systemFontOfSize:size weight:weight];
    UIFont *next = [UIFont systemFontOfSize:size * 0.67 weight:weight];

    NSDictionary *currentAttributes = @{
        NSFontAttributeName: current,
        NSForegroundColorAttributeName: UIColor.whiteColor
    };
    NSDictionary *nextAttributes = @{
        NSFontAttributeName: next,
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45]
    };

    NSString *currentText = @"This is your lyric";
    NSString *nextText = @"A live preview of the style";

    CGRect currentRect = CGRectMake(22.0, 48.0, rect.size.width - 44.0, size + 12.0);
    CGRect nextRect = CGRectMake(22.0, 48.0 + size + 20.0, rect.size.width - 44.0, size * 0.67 + 12.0);

    [currentText drawInRect:currentRect withAttributes:currentAttributes];
    [nextText drawInRect:nextRect withAttributes:nextAttributes];
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
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleFontWeight];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultFontWeight();
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
                SGSection(@"Lyrics", @[SGRLyricsTextSizesRow(), SGLyricsWordTimingRow()])
            ] footer:nil];
        return page;
    });
}
