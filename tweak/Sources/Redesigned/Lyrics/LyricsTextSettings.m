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

CGFloat SGRLyricsStyleFontSize(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleFontSize];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultFontSize();
}

CGFloat SGRLyricsStyleFontWeight(void) {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:SGRKeyLyricsStyleFontWeight];
    return value > 0.0 ? (CGFloat)value : SGRLyricsStyleDefaultFontWeight();
}

static void SGRSetLyricsStylePreset(NSInteger preset) {
    CGFloat size = 30.0;
    CGFloat weight = UIFontWeightBold;

    switch (preset) {
        case 1: // Subtle
            size = 27.0;
            weight = UIFontWeightRegular;
            break;
        case 2: // Bold
            size = 33.0;
            weight = UIFontWeightBlack;
            break;
        default: // Default
            break;
    }

    [NSUserDefaults.standardUserDefaults setDouble:size forKey:SGRKeyLyricsStyleFontSize];
    [NSUserDefaults.standardUserDefaults setDouble:weight forKey:SGRKeyLyricsStyleFontWeight];
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

SGModRow *SGRLyricsStyleTuneRow(void) {
    SGModRow *row = SGPageRow(@"Fine-tune style", ^{
        SGModPage *page = [[SGModPage alloc] initWithTitle:@"Fine-tune style"
                                                      intro:@"Adjust the lyrics appearance. Changes apply immediately."
                                                   sections:@[
            SGSection(nil, @[
                SGSliderRow(@"Size", @"Overall lyric size", 20.0, 44.0, 1.0,
                            ^double { return SGRLyricsStyleFontSize(); },
                            ^(double value) {
                                [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGRKeyLyricsStyleFontSize];
                                [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
                            },
                            ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f pt", value]; }),

                SGSliderRow(@"Weight", @"Font weight", UIFontWeightUltraLight, UIFontWeightBlack, 0.05,
                            ^double { return SGRLyricsStyleFontWeight(); },
                            ^(double value) {
                                [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGRKeyLyricsStyleFontWeight];
                                [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
                            },
                            ^NSString *(double value) { return [NSString stringWithFormat:@"%.2f", value]; })
            ])
        ] footer:nil];
        return page;
    });
    return row;
}
