#import "AudioCapture.h"
#import "AudioMath.h"
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>

typedef struct { float samples[MUSIC_FFT], right[MUSIC_FFT]; int used; } SpectrumBuffer;
@interface AudioCapture ()
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL running;
@property(nonatomic) BandFilter filter;
@property(nonatomic) SpectrumBuffer spectrumBuffer;
@end
@implementation AudioCapture
- (void)fail:(NSString *)message {
    void (^callback)(NSString *)=self.onError;
    [self stop]; if(callback) callback(message);
}
- (void)start {
    [self stop]; self.running=YES; NSUInteger generation=self.generation;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.running||generation!=self.generation) return;
            if(error||!content.displays.count) {
                [self fail:[NSString stringWithFormat:@"Could not access available displays: %@", error.localizedDescription ?: @"No display available"]]; return;
            }
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDisplay:content.displays.firstObject excludingWindows:@[]];
            SCStreamConfiguration *config=[SCStreamConfiguration new];
            config.width=2; config.height=2; config.minimumFrameInterval=CMTimeMake(1,1); config.queueDepth=3;
            config.capturesAudio=YES; config.sampleRate=48000; config.channelCount=2; config.excludesCurrentProcessAudio=YES;
            if(@available(macOS 15.0,*)) config.captureMicrophone=NO;
            SCStream *stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            self.stream=stream; NSError *outputError=nil;
            // Register only audio output. No screen frames are processed or saved.
            if(![stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:dispatch_get_main_queue() error:&outputError]) { [self fail:[NSString stringWithFormat:@"Could not prepare audio capture: %@", outputError.localizedDescription ?: @"Unknown error"]]; return; }
            [stream startCaptureWithCompletionHandler:^(NSError *startError){
                dispatch_async(dispatch_get_main_queue(),^{
                    if(!self.running||generation!=self.generation) { [stream stopCaptureWithCompletionHandler:^(NSError *e){}]; return; }
                    if(startError) { [self fail:[NSString stringWithFormat:@"Could not start audio capture: %@", startError.localizedDescription ?: @"Unknown error"]]; return; }
                    if(self.onStarted) self.onStarted();
                });
            }];
        });
    }];
}
- (void)stop {
    self.running=NO; self.generation++; self.filter=(BandFilter){0}; self.spectrumBuffer=(SpectrumBuffer){0};
    SCStream *stream=self.stream; self.stream=nil;
    if(stream) [stream stopCaptureWithCompletionHandler:^(NSError *error){}];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(),^{ if(stream==self.stream && self.running) [self fail:[NSString stringWithFormat:@"Audio capture stopped: %@",error.localizedDescription ?: @"Unknown error"]]; });
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if(!self.running||stream!=self.stream||type!=SCStreamOutputTypeAudio||!CMSampleBufferDataIsReady(sample)) return;
    const AudioStreamBasicDescription *format=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
    if(!format||format->mFormatID!=kAudioFormatLinearPCM) return;
    size_t size=0;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,&size,NULL,0,NULL,NULL,0,NULL);
    if(size<sizeof(AudioBufferList)) return;
    AudioBufferList *list=malloc(size); if(!list) return;
    CMBlockBufferRef block=NULL;
    OSStatus status=CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,NULL,list,size,kCFAllocatorDefault,kCFAllocatorDefault,kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,&block);
    double squares=0; size_t count=0;
    if(status==noErr) {
        for(UInt32 b=0;b<list->mNumberBuffers;b++) {
            AudioBuffer buffer=list->mBuffers[b]; if(!buffer.mData) continue;
            if((format->mFormatFlags&kAudioFormatFlagIsFloat)&&format->mBitsPerChannel==32) {
                size_t n=buffer.mDataByteSize/sizeof(float); double rms=AudioRMS(buffer.mData,n); squares+=rms*rms*n; count+=n;
            } else if((format->mFormatFlags&kAudioFormatFlagIsSignedInteger)&&format->mBitsPerChannel==16) {
                const int16_t *p=buffer.mData; size_t n=buffer.mDataByteSize/2;
                for(size_t i=0;i<n;i++){ double v=p[i]/32768.0; squares+=v*v; } count+=n;
            }
        }
    }
    if(status==noErr && self.onBands && (format->mFormatFlags&kAudioFormatFlagIsFloat) && format->mBitsPerChannel==32 && list->mNumberBuffers>0) {
        BOOL planar=(format->mFormatFlags&kAudioFormatFlagIsNonInterleaved)!=0;
        AudioBuffer first=list->mBuffers[0]; size_t frames=planar?first.mDataByteSize/sizeof(float):first.mDataByteSize/(sizeof(float)*MAX(1,format->mChannelsPerFrame));
        if(planar && list->mNumberBuffers>1) frames=MIN(frames,list->mBuffers[1].mDataByteSize/sizeof(float));
        if(first.mData && frames>0 && frames<100000) {
            float *l=malloc(frames*sizeof(float)), *r=malloc(frames*sizeof(float));
            if(l&&r) {
                const float *p=first.mData, *q=(planar&&list->mNumberBuffers>1)?list->mBuffers[1].mData:NULL;
                for(size_t i=0;i<frames;i++) { l[i]=p[planar?i:i*format->mChannelsPerFrame]; r[i]=q?q[i]:(!planar&&format->mChannelsPerFrame>1?p[i*format->mChannelsPerFrame+1]:l[i]); }
                if(self.onSpectrum) {
                    SpectrumBuffer buffer=self.spectrumBuffer;
                    for(size_t i=0;i<frames;i++) {
                        buffer.samples[buffer.used]=l[i]; buffer.right[buffer.used++]=r[i];
                        if(buffer.used==MUSIC_FFT) {
                            float values[MUSIC_BINS], rightValues[MUSIC_BINS]; MusicSpectrum(buffer.samples,format->mSampleRate,values); MusicSpectrum(buffer.right,format->mSampleRate,rightValues);
                            for(int b=0;b<MUSIC_BINS;b++) values[b]=sqrtf((values[b]*values[b]+rightValues[b]*rightValues[b])*0.5f);
                            NSMutableArray *bins=[NSMutableArray arrayWithCapacity:MUSIC_BINS];
                            for(int b=0;b<MUSIC_BINS;b++) [bins addObject:@(values[b])];
                            self.onSpectrum(bins); buffer.used=0;
                        }
                    }
                    self.spectrumBuffer=buffer;
                }
                BandFilter f=self.filter; AudioBands bands=AnalyzeAudio(&f,l,r,frames,format->mSampleRate); self.filter=f; self.onBands(bands);
            }
            free(l); free(r);
        }
    }
    if(block) CFRelease(block); free(list);
    if(count && self.onLevel) self.onLevel(sqrt(squares/count));
}
@end
