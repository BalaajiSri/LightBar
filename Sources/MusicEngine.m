#import "MusicEngine.h"
#import <Accelerate/Accelerate.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
static double clamp(double x,double lo,double hi){ return fmin(hi,fmax(lo,isfinite(x)?x:0)); }
static double at(MusicEngine *e,int back){ return e->history[(e->cursor-1-back+MUSIC_HISTORY)%MUSIC_HISTORY]; }
static void estimate(MusicEngine *e,double now) {
    e->lastEstimate=now; if(e->count<200) return;
    int n=e->count; double mean=0; for(int i=0;i<n;i++) mean+=at(e,i); mean/=n;
    double best=0; int lagBest=0; double correlations[52]={0};
    for(int lag=16;lag<=51;lag++) {
        double dot=0,a=0,b=0;
        for(int i=0;i<n-lag;i++){ double x=at(e,i)-mean,y=at(e,i+lag)-mean; dot+=x*y; a+=x*x; b+=y*y; }
        correlations[lag]=(a*b>1e-12)?dot/sqrt(a*b):0;
    }
    for(int lag=17;lag<=50;lag++) {
        double score=correlations[lag]-lag*0.0008;
        if(score>best){best=score;lagBest=lag;}
    }
    if(lagBest && best>0.18) {
        double a=correlations[lagBest-1],b=correlations[lagBest],c=correlations[lagBest+1];
        double offset=fabs(a-2*b+c)>1e-9?clamp(0.5*(a-c)/(a-2*b+c),-0.5,0.5):0;
        double bpm=clamp(3000.0/(lagBest+offset),60,180);
        if(e->confidence>0.35 && fabs(bpm-e->bpm)<8) e->bpm=e->bpm*0.65+bpm*0.35; else e->bpm=bpm;
        e->confidence=clamp(best,0,1)*clamp((n-150)/250.0,0,1);
    } else e->confidence*=0.6;
}
void MusicFeed(MusicEngine *e,double now,double bass,double mid,double treble) {
    if(!isfinite(now)) return;
    double signal=clamp(bass,0,1)*0.8+clamp(treble,0,1)*0.2;
    double slot=floor(now*50);
    if(e->count && slot<=e->slot) return;
    if(e->count && slot-e->slot>25) { memset(e,0,sizeof(*e)); }
    int steps=e->count?(int)fmin(25,slot-e->slot):1;
    double novelty=fmax(0,signal-e->previous); e->previous=signal;
    e->floor=e->floor*0.97+novelty*0.03;
    if(novelty>fmax(0.025,e->floor*2.0) && now-e->lastOnset>0.24) { e->lastOnset=now; e->pulse=1; }
    if(signal+mid>0.02) e->lastSignal=now;
    for(int i=0;i<steps;i++){ e->history[e->cursor]=i==steps-1?novelty:0; e->cursor=(e->cursor+1)%MUSIC_HISTORY; if(e->count<MUSIC_HISTORY)e->count++; }
    e->slot=slot;
    if(now-e->lastEstimate>=1) estimate(e,now);
}
MusicOutput MusicRender(MusicEngine *e,double now,double bass,double mid,double treble,double level,double pan) {
    bass=clamp(bass,0,1); mid=clamp(mid,0,1); treble=clamp(treble,0,1); level=clamp(level,0,1); pan=clamp(pan,-1,1);
    e->energy=e->energy*0.92+level*0.08;
    double confidence=now-e->lastSignal<2?e->confidence:0;
    double beat=0;
    if(confidence>0.35 && e->bpm>0) { double phase=fmod(fmax(0,now-e->lastOnset),60/e->bpm)/(60/e->bpm); beat=exp(-phase*7); }
    e->pulse*=0.65;
    double drive=clamp((e->energy-0.12)/0.5,0,1);
    double accent=fmax(beat*confidence,e->pulse);
    double intensity=level*(0.55+drive*0.15)+accent*bass*drive*0.35;
    // Quiet phrases diffuse slowly; louder phrases reveal bass-weighted pulses.
    double mix=0.08+drive*0.25;
    double red=bass+mid*0.55+fmax(0,-pan)*level*0.2;
    double green=bass*0.25+treble*0.75;
    double blue=mid*0.9+treble+fmax(0,pan)*level*0.2;
    double peak=fmax(0.001,fmax(red,fmax(green,blue)));
    e->r+=(red/peak-e->r)*mix; e->g+=(green/peak-e->g)*mix; e->b+=(blue/peak-e->b)*mix;
    return (MusicOutput){clamp(e->r,0,1),clamp(e->g,0,1),clamp(e->b,0,1),clamp(intensity,0,1),e->bpm,confidence};
}
void MusicSpectrum(const float *samples,double rate,float output[MUSIC_BINS]) {
    memset(output,0,sizeof(float)*MUSIC_BINS); if(rate<8000) return;
    float window[MUSIC_FFT],input[MUSIC_FFT],real[MUSIC_FFT/2],imag[MUSIC_FFT/2];
    vDSP_hann_window(window,MUSIC_FFT,vDSP_HANN_NORM);
    vDSP_vmul(samples,1,window,1,input,1,MUSIC_FFT);
    DSPSplitComplex split={real,imag}; vDSP_ctoz((const DSPComplex *)input,2,&split,1,MUSIC_FFT/2);
    FFTSetup setup=vDSP_create_fftsetup(11,kFFTRadix2); if(!setup) return;
    vDSP_fft_zrip(setup,&split,1,11,FFT_FORWARD); imag[0]=0;
    for(int band=0;band<MUSIC_BINS;band++) {
        double lo=40*pow(400.0,(double)band/MUSIC_BINS),hi=40*pow(400.0,(double)(band+1)/MUSIC_BINS),sum=0;
        int start=fmax(1,ceil(lo*MUSIC_FFT/rate)),end=fmin(MUSIC_FFT/2,ceil(hi*MUSIC_FFT/rate));
        for(int k=start;k<end;k++) sum+=real[k]*real[k]+imag[k]*imag[k];
        output[band]=(float)clamp(sqrt(sum)/MUSIC_FFT*2,0,1);
    }
    vDSP_destroy_fftsetup(setup);
}
bool MusicEngineTests(void) {
    bool ok=true;
    int tempos[]={90,120,150};
    for(int t=0;t<3;t++) {
        MusicEngine e={0}; double period=60.0/tempos[t];
        for(int i=0;i<900;i++){ double now=i/50.0,phase=fmod(now,period); MusicFeed(&e,1000+now,phase<0.06?0.7:0.01,0.1,phase<0.04?0.3:0.01); }
        bool pass=fabs(e.bpm-tempos[t])<4 && e.confidence>0.35;
        printf("Synthetic %d BPM: %.1f, confidence %.2f %s\n",tempos[t],e.bpm,e.confidence,pass?"PASS":"FAIL"); ok &= pass;
    }
    MusicEngine missing={0};
    for(int i=0;i<900;i++){ double t=i/50.0; int beat=(int)(t/0.5); double bass=(fmod(t,0.5)<0.06 && beat%7!=0)?0.7:0.01; MusicFeed(&missing,1000+t,bass,0.1,0); }
    ok &= fabs(missing.bpm-120)<4;
    MusicOutput stale=MusicRender(&missing,1100,0,0,0,0,0); ok &= stale.confidence==0 && stale.intensity==0;
    MusicEngine silence={0};
    for(int i=0;i<700;i++) MusicFeed(&silence,1000+i/50.0,0,0,0);
    MusicOutput o=MusicRender(&silence,1014,0,0,0,0,0); ok &= o.confidence==0 && o.intensity==0;
    float tone[MUSIC_FFT],spectrum[MUSIC_BINS];
    for(int i=0;i<MUSIC_FFT;i++) tone[i]=0.5*sin(2*M_PI*1000*i/48000);
    MusicSpectrum(tone,48000,spectrum); int peak=0; for(int i=1;i<MUSIC_BINS;i++) if(spectrum[i]>spectrum[peak])peak=i;
    ok &= peak>=7 && peak<=9;
    for(int i=0;i<100;i++){ o=MusicRender(&silence,1014+i*0.1,1,1,1,1,1); ok &= isfinite(o.intensity)&&o.intensity<=1&&o.r<=1&&o.g<=1&&o.b<=1; }
    printf("Tempo, spectrum, silence and bounded output checks: %s\n",ok?"PASS":"FAIL"); return ok;
}
