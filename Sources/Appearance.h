#import <Cocoa/Cocoa.h>
@interface LightPreview : NSView
@property(nonatomic, strong) NSColor *lightColor;
@property(nonatomic) double intensity;
@end
@interface LightCanvas : NSView
@end
@interface MusicSpectrogram : NSView
@property(nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *columns;
- (void)appendSpectrum:(NSArray<NSNumber *> *)spectrum;
- (void)clear;
@end
@interface MusicLabCanvas : NSView
@end
