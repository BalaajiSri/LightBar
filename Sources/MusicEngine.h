#pragma once
#include <stdbool.h>
#define MUSIC_HISTORY 600
#define MUSIC_BINS 16
#define MUSIC_FFT 2048
typedef struct {
    double history[MUSIC_HISTORY]; int count, cursor;
    double slot, previous, floor, lastEstimate, lastOnset, lastSignal, bpm, confidence;
    double energy, pulse, hue, r, g, b;
} MusicEngine;
typedef struct { double r,g,b,intensity,bpm,confidence; } MusicOutput;
void MusicFeed(MusicEngine *engine,double time,double bass,double mid,double treble);
MusicOutput MusicRender(MusicEngine *engine,double time,double bass,double mid,double treble,double level,double pan);
void MusicSpectrum(const float *samples,double sampleRate,float output[MUSIC_BINS]);
bool MusicEngineTests(void);
