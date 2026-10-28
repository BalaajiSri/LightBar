#import <Foundation/Foundation.h>
#import <math.h>
static inline double AudioRMS(const float *samples, size_t count) {
    if (!count) return 0;
    double sum=0;
    for(size_t i=0;i<count;i++) { double v=samples[i]; if(isfinite(v)) sum+=v*v; }
    return sqrt(sum/count);
}
static inline double AudioTarget(double rms, double gain) {
    if(!isfinite(rms)||!isfinite(gain)) return 0;
    return MIN(1.0,sqrt(MAX(0.0,rms-0.002)*MAX(0.0,gain)*3.0));
}
static inline double AudioEnvelope(double target,double previous) {
    double value=MAX(target,previous*0.68);
    return value<0.015?0:MIN(1.0,value);
}

typedef struct { double low[2], high[2]; } BandFilter;
typedef struct { double bass, mid, treble, left, right; } AudioBands;
static inline AudioBands AnalyzeAudio(BandFilter *f, const float *left, const float *right, size_t n, double rate) {
    AudioBands out={0}; if(!n || rate<8000) return out;
    double a=1-exp(-2*M_PI*180/rate), b=1-exp(-2*M_PI*2500/rate);
    double e[5]={0};
    for(size_t i=0;i<n;i++) {
        double l=isfinite(left[i])?left[i]:0, r=right && isfinite(right[i])?right[i]:l;
        double v[2]={l,r};
        for(int c=0;c<2;c++) {
            f->low[c]+=a*(v[c]-f->low[c]); f->high[c]+=b*(v[c]-f->high[c]);
            double lo=f->low[c], mid=f->high[c]-lo, hi=v[c]-f->high[c];
            e[0]+=lo*lo; e[1]+=mid*mid; e[2]+=hi*hi; e[3+c]+=v[c]*v[c];
        }
    }
    out.bass=sqrt(e[0]/(2*n)); out.mid=sqrt(e[1]/(2*n)); out.treble=sqrt(e[2]/(2*n)); out.left=sqrt(e[3]/n); out.right=sqrt(e[4]/n); return out;
}
