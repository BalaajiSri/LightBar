#import "Appearance.h"
@implementation LightCanvas
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithSRGBRed:0.055 green:0.065 blue:0.085 alpha:1] setFill]; NSRectFill(self.bounds);
    NSArray *cards=@[[NSValue valueWithRect:NSMakeRect(20,528,400,114)], [NSValue valueWithRect:NSMakeRect(20,306,400,206)], [NSValue valueWithRect:NSMakeRect(20,62,400,228)]];
    for(NSValue *value in cards) {
        NSBezierPath *p=[NSBezierPath bezierPathWithRoundedRect:value.rectValue xRadius:16 yRadius:16];
        [[NSColor colorWithSRGBRed:0.09 green:0.105 blue:0.13 alpha:1] setFill]; [p fill];
        [[NSColor colorWithWhite:1 alpha:0.055] setStroke]; [p stroke];
    }
}
@end
@implementation LightPreview
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *c=self.lightColor?:[NSColor colorWithSRGBRed:0.6 green:0.4 blue:1 alpha:1];
    NSRect rail=NSInsetRect(self.bounds,7,7);
    NSShadow *shadow=[NSShadow new]; shadow.shadowColor=[c colorWithAlphaComponent:0.3+0.4*self.intensity]; shadow.shadowBlurRadius=12;
    [NSGraphicsContext saveGraphicsState]; [shadow set];
    [[c colorWithAlphaComponent:0.25+0.7*self.intensity] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rail xRadius:7 yRadius:7] fill];
    [NSGraphicsContext restoreGraphicsState];
    NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[c blendedColorWithFraction:0.3 ofColor:NSColor.whiteColor] endingColor:c];
    [gradient drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rail,2,3) xRadius:4 yRadius:4] angle:0];
}
@end
@implementation MusicSpectrogram
- (void)clear { self.columns=[NSMutableArray new]; self.needsDisplay=YES; }
- (void)appendSpectrum:(NSArray<NSNumber *> *)spectrum {
    if(!self.columns) self.columns=[NSMutableArray new]; [self.columns addObject:spectrum];
    if(self.columns.count>120) [self.columns removeObjectAtIndex:0]; self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithSRGBRed:0.035 green:0.04 blue:0.065 alpha:1] setFill]; NSRectFill(self.bounds);
    CGFloat width=self.bounds.size.width/120, height=self.bounds.size.height/16;
    NSInteger offset=120-self.columns.count;
    for(NSInteger x=0;x<(NSInteger)self.columns.count;x++) {
        NSArray *bins=self.columns[x];
        for(NSInteger y=0;y<MIN(16,(NSInteger)bins.count);y++) {
            double value=MIN(1,MAX(0,(20*log10(MAX(0.00001,[bins[y] doubleValue]))+70)/60));
            [[NSColor colorWithCalibratedHue:0.72-value*0.65 saturation:0.85 brightness:0.08+0.92*value alpha:1] setFill];
            NSRectFill(NSMakeRect((offset+x)*width,y*height,ceil(width),ceil(height)));
        }
    }
}
@end
@implementation MusicLabCanvas
- (void)drawRect:(NSRect)dirty { [[NSColor colorWithSRGBRed:0.055 green:0.065 blue:0.085 alpha:1] setFill]; NSRectFill(self.bounds); }
@end
