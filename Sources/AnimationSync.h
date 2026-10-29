#pragma once
#include <math.h>
// A user-trimmable heuristic, not a calibrated percent-to-BPM conversion.
static inline int AnimationTempoSpeed(double reference,double bpm,double confidence) {
    double speed=reference;
    if(isfinite(bpm) && bpm>=60 && bpm<=180 && confidence>0.35) speed*=bpm/120.0;
    return (int)lround(fmax(1,fmin(100,isfinite(speed)?speed:50)));
}
static inline int AnimationMusicBrightness(double cap,double level,double envelope) {
    cap=fmax(0,fmin(100,isfinite(cap)?cap:0));
    double intensity=isfinite(level)&&level>0.005?fmin(1,fmax(0,0.25+0.75*(isfinite(envelope)?envelope:0))):0;
    return (int)lround(cap*intensity);
}
