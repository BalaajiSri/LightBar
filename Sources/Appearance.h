#import <Cocoa/Cocoa.h>
@interface LightPreview : NSView
@property(nonatomic, strong) NSColor *lightColor;
@property(nonatomic) double intensity;
@end
@interface LightCanvas : NSView
@end
