#import <Cocoa/Cocoa.h>

static void DrawRoundedRect(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *output = [NSString stringWithUTF8String:argv[1]];
        CGFloat size = (CGFloat)atoi(argv[2]);
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
            pixelsWide:(NSInteger)size
            pixelsHigh:(NSInteger)size
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:0
            bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [[NSColor clearColor] setFill];
        NSRectFill(NSMakeRect(0, 0, size, size));

        CGFloat inset = size * 0.08;
        NSRect tile = NSInsetRect(NSMakeRect(0, 0, size, size), inset, inset);
        DrawRoundedRect(tile, size * 0.22, [NSColor colorWithRed:0.12 green:0.20 blue:0.32 alpha:1.0]);

        NSRect paper = NSMakeRect(size * 0.25, size * 0.18, size * 0.50, size * 0.64);
        DrawRoundedRect(paper, size * 0.055, [NSColor colorWithWhite:1 alpha:0.97]);
        [[NSColor colorWithRed:0.31 green:0.70 blue:0.86 alpha:1.0] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(size * 0.33, size * 0.61, size * 0.34, size * 0.045)
                                         xRadius:size * 0.02 yRadius:size * 0.02] fill];
        [[NSColor colorWithWhite:0.70 alpha:1.0] setFill];
        for (NSInteger index = 0; index < 3; index++) {
            CGFloat width = index == 2 ? size * 0.22 : size * 0.34;
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(size * 0.33, size * (0.50 - index * 0.09), width, size * 0.028)
                                             xRadius:size * 0.014 yRadius:size * 0.014] fill];
        }

        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:size * 0.16],
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.12 green:0.20 blue:0.32 alpha:1.0]
        };
        NSString *mark = @"译";
        NSSize markSize = [mark sizeWithAttributes:attributes];
        [mark drawAtPoint:NSMakePoint((size - markSize.width) / 2.0, size * 0.20)
           withAttributes:attributes];

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:output atomically:YES] ? 0 : 3;
    }
}

