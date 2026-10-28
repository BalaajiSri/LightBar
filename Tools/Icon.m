#import <Cocoa/Cocoa.h>
int main(int argc,const char *argv[]) { @autoreleasepool {
    if(argc<2) return 1;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1024 pixelsHigh:1024 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]; [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:context];
    NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(65,65,894,894) xRadius:205 yRadius:205];
    NSGradient *bg=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.16 green:0.18 blue:0.28 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.035 green:0.04 blue:0.07 alpha:1]]; [bg drawInBezierPath:tile angle:110];
    CGFloat heights[]={260,460,620,400,240};
    NSArray *colors=@[NSColor.systemOrangeColor,NSColor.systemPinkColor,NSColor.systemPurpleColor,NSColor.systemTealColor,NSColor.systemBlueColor];
    for(int i=0;i<5;i++) {
        NSColor *c=colors[i]; NSRect rect=NSMakeRect(252+i*106,512-heights[i]/2,70,heights[i]);
        [NSGraphicsContext saveGraphicsState]; NSShadow *shadow=[NSShadow new]; shadow.shadowColor=[c colorWithAlphaComponent:0.7]; shadow.shadowBlurRadius=35; [shadow set];
        NSBezierPath *bar=[NSBezierPath bezierPathWithRoundedRect:rect xRadius:35 yRadius:35]; [c setFill]; [bar fill]; [NSGraphicsContext restoreGraphicsState];
        NSGradient *light=[[NSGradient alloc] initWithStartingColor:[c blendedColorWithFraction:0.45 ofColor:NSColor.whiteColor] endingColor:c]; [light drawInBezierPath:bar angle:90];
    }
    [NSGraphicsContext restoreGraphicsState];
    NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]?0:1;
} }
