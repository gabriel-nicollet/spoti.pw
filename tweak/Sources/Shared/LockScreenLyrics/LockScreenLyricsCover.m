// The card behind the lock screen's controls when "Lyrics on the cover" is on: the album's cover blurred and dimmed, the line
// being sung large and white at the middle, the line before it and the line after it smaller and dim. It is a still per line,
// drawn when the line changes (a few times a minute), not an animation: iOS gives a now playing artwork no per-word clock.
#import <CoreImage/CoreImage.h>
#import "LockScreenLyrics.h"
#import "Redesigned/Lyrics/LyricsText.h"

@implementation SGLyricsCoverArtwork
@end

static UIImage *blurred(UIImage *cover, CGSize size) {
    CIImage *input = cover.CIImage ?: (cover.CGImage ? [CIImage imageWithCGImage:cover.CGImage] : nil);
    if (!input) return nil;
    CGRect extent = input.extent;
    if (CGRectIsInfinite(extent) || extent.size.width < 1 || extent.size.height < 1) return nil;
    CIFilter *colors = [CIFilter filterWithName:@"CIColorControls"];
    [colors setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
    [colors setValue:@(1.18) forKey:kCIInputSaturationKey];
    [colors setValue:@(1.06) forKey:kCIInputContrastKey];
    CIImage *enhanced = [colors outputImage] ?: input;

    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[enhanced imageByClampingToExtent] forKey:kCIInputImageKey];
    [blur setValue:@(MAX(extent.size.width, extent.size.height) / 14) forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:extent];
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:nil]; });
    CGImageRef image = [context createCGImage:output fromRect:extent];
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

// The largest size, from `start` down, at which `text` fits `width` in at most `lines` lines.
static UIFont *fitted(NSString *text, CGFloat start, CGFloat width, NSUInteger lines, UIFontWeight weight) {
    for (CGFloat size = start; size > 10; size -= 2) {
        UIFont *font = [UIFont systemFontOfSize:size weight:weight];
        CGRect box = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: font} context:nil];
        if (ceil(box.size.height) <= ceil(font.lineHeight) * lines + 1) return font;
    }
    return [UIFont systemFontOfSize:10 weight:weight];
}

UIImage *SGLyricsCoverImage(UIImage *cover, NSString *previous, NSString *current, NSString *next, CGSize size) {
    if (size.width < 8 || size.height < 8 || size.width > 4096 || size.height > 4096) size = CGSizeMake(600, 600);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = MAX(2.0, UIScreen.mainScreen.scale);
    format.opaque = YES;
    UIImage *back = cover ? blurred(cover, size) : nil;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect all = CGRectMake(0, 0, size.width, size.height);
        [UIColor.blackColor setFill];
        UIRectFill(all);
        UIImage *picture = back ?: cover;
        if (picture && picture.size.width > 0 && picture.size.height > 0) {
            CGFloat scale = MAX(size.width / picture.size.width, size.height / picture.size.height) * (back ? 1.15 : 1);
            CGSize drawn = CGSizeMake(picture.size.width * scale, picture.size.height * scale);
            [picture drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
        }
        [[UIColor colorWithWhite:0 alpha:back ? 0.38 : 0.25] setFill];
        UIRectFill(all);

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[
            (id)[UIColor colorWithRed:0.25 green:0.18 blue:0.42 alpha:0.28].CGColor,
            (id)[UIColor colorWithRed:0.58 green:0.28 blue:0.22 alpha:0.20].CGColor,
            (id)[UIColor colorWithRed:0.18 green:0.34 blue:0.48 alpha:0.18].CGColor
        ];
        CGFloat locations[] = {0.0, 0.5, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
        CGContextDrawLinearGradient(context.CGContext, gradient,
                                     CGPointMake(0, 0), CGPointMake(size.width, size.height),
                                     kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        CGFloat margin = size.width * 0.09, width = size.width - margin * 2, gap = size.height * 0.035;
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        shadow.shadowBlurRadius = size.width * 0.02;
        UIFont *main = fitted(current ?: @"", size.width * (0.105 + MIN(0.045, MAX(0.0, (SGRLyricsStyleFontSize() - 20.0) / 24.0 * 0.045))), width, 5, SGRLyricsStyleFontWeight());
        UIFont *small = [UIFont systemFontOfSize:MAX(10, main.pointSize * 0.55) weight:UIFontWeightSemibold];
        // Heights first, so the line being sung sits at the middle however long the others are.
        CGSize (^measure)(NSString *, UIFont *) = ^CGSize(NSString *text, UIFont *font) {
            if (!text.length) return CGSizeZero;
            CGRect box = [text boundingRectWithSize:CGSizeMake(width, size.height * 0.28) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                                         attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style} context:nil];
            return CGSizeMake(width, ceil(box.size.height));
        };
        CGSize mainSize = measure(current, main), previousSize = measure(previous, small), nextSize = measure(next, small);
        CGFloat middle = size.height / 2;
        void (^draw)(NSString *, UIFont *, CGFloat, CGRect, CGFloat) = ^(NSString *text, UIFont *font, CGFloat alpha, CGRect box, CGFloat unused) {
            if (!text.length) return;
            [text drawWithRect:box options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine attributes:@{
                NSFontAttributeName: font, NSParagraphStyleAttributeName: style, NSShadowAttributeName: shadow,
                NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:alpha]} context:nil];
        };
        draw(current, main, 1, CGRectMake(margin, middle - mainSize.height / 2, width, mainSize.height), 0);
        draw(previous, small, 0.45, CGRectMake(margin, middle - mainSize.height / 2 - gap - previousSize.height, width, previousSize.height), 0);
        draw(next, small, 0.45, CGRectMake(margin, middle + mainSize.height / 2 + gap, width, nextSize.height), 0);
    }];
}
