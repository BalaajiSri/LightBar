#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import "AudioMath.h"

// All callbacks and lifecycle calls run on the main queue.
@interface AudioCapture : NSObject <SCStreamOutput, SCStreamDelegate>
@property(nonatomic, copy) void (^onLevel)(double rms);
@property(nonatomic, copy) void (^onBands)(AudioBands bands);
@property(nonatomic, copy) void (^onStarted)(void);
@property(nonatomic, copy) void (^onError)(NSString *message);
- (void)start;
- (void)stop;
@end
