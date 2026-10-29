#import <Cocoa/Cocoa.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "AudioCapture.h"
#import "AudioMath.h"
#import "Appearance.h"
#import "AnimationSync.h"

static NSData *Frame(uint8_t len,uint8_t op,uint8_t a,uint8_t b,uint8_t c,uint8_t d,uint8_t e) {
    uint8_t bytes[]={0x7e,len,op,a,b,c,d,e,0xef}; return [NSData dataWithBytes:bytes length:9];
}
static NSData *Power(BOOL on) { return Frame(4,4,on,0,on,255,0); }
static NSData *RGB(int r,int g,int b) { return Frame(7,5,3,r,g,b,0x10); }
static NSData *Music(int r,int g,int b) { return Frame(7,5,3,r,g,b,0x20); }
static NSData *Brightness(int p) { return Frame(4,1,MAX(0,MIN(100,p)),0,255,255,0); }
static NSData *Mode(int n) { return Frame(5,3,n,6,255,255,0); }
static NSData *Speed(int p) { return Frame(4,2,MAX(0,MIN(100,p)),255,255,255,0); }

@interface LightBar : NSObject <NSApplicationDelegate,CBCentralManagerDelegate,CBPeripheralDelegate>
@property (strong) NSStatusItem *item;
@property (strong) NSPopover *popover;
@property (strong) NSPanel *panel;
@property (strong) CBCentralManager *central;
@property (strong) NSMutableArray<CBPeripheral *> *devices;
@property (strong) CBPeripheral *light;
@property (strong) CBCharacteristic *writer;
@property (strong) NSPopUpButton *deviceList, *modes;
@property (strong) NSTextField *status, *brightnessLabel;
@property (strong) NSButton *connectButton, *powerButton;
@property (strong) NSColorWell *color;
@property (strong) NSSlider *brightness, *speed;
@property (strong) NSMutableArray<NSControl *> *lightControls;
@property (strong) NSMutableArray<NSData *> *pending;
@property (strong) NSTimer *scanTimer, *connectionTimer, *sendTimer;
@property BOOL reconnect, quitting;
@property (strong) NSDictionary *effects;
@property (strong) AudioCapture *audio;
@property (strong) NSButton *audioButton;
@property (strong) NSLevelIndicator *audioMeter;
@property (strong) NSSlider *sensitivity;
@property (strong) NSLevelIndicator *bassMeter, *midMeter, *trebleMeter;
@property (strong) LightPreview *preview;
@property double averageLevel, beatGlow, musicHue, lastBeat;
@property (strong) NSTimer *audioTimer;
@property double audioPeak, audioEnvelope, lastAudioSample;
@property AudioBands bands;
@property BOOL audioRequested, audioStarted;
@property NSUInteger audioGeneration;
@property MusicEngine musicEngine;
@property (strong) NSPanel *studioPanel;
@property (strong) NSButton *animationLayer, *studioSyncButton;
@property (strong) NSPopUpButton *studioPattern;
@property (strong) NSSlider *referenceSpeed;
@property (strong) NSTextField *studioTempo;
@property double lastAnimationSpeedTime;
@property int lastAnimationSpeed, lastAnimationBrightness;
@property (strong) NSPopUpButton *paletteMenu;
@property (strong) NSPanel *palettePanel;
@property (strong) NSArray<NSColorWell *> *paletteWells;
@property (strong) NSArray<NSArray<NSString *> *> *paletteHex;
@property (strong) NSArray<NSColor *> *customPalette;
@property (strong) NSColor *blendedPalette;
@property (strong) NSButton *experimentalSwitch;
@property (strong) NSPanel *experimentPanel;
@property (strong) NSTextField *tempoLabel, *confidenceLabel;
@property (strong) MusicSpectrogram *spectrogram;
@end

@implementation LightBar
- (void)log:(NSString *)message {
    NSLog(@"LightBar: %@",message);
    NSString *line=[NSString stringWithFormat:@"%@ %@\n",[NSDate date],message];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"LightBar.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:path]; [f seekToEndOfFile]; [f writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [f closeFile];
}
- (NSTextField *)label:(NSString *)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width {
    NSTextField *v=[NSTextField labelWithString:text]; v.frame=NSMakeRect(x,y,width,22); [self.popover.contentViewController.view addSubview:v]; return v;
}
- (NSButton *)button:(NSString *)title action:(SEL)action x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w {
    NSButton *b=[NSButton buttonWithTitle:title target:self action:action]; b.frame=NSMakeRect(x,y,w,28); [self.popover.contentViewController.view addSubview:b]; return b;
}
- (void)heading:(NSString *)title x:(CGFloat)x y:(CGFloat)y {
    NSTextField *v=[self label:title x:x y:y width:300]; v.font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold]; v.textColor=[NSColor colorWithWhite:0.65 alpha:1];
}
- (NSLevelIndicator *)meterAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)width color:(NSColor *)color label:(NSString *)label {
    NSLevelIndicator *m=[[NSLevelIndicator alloc] initWithFrame:NSMakeRect(x,y,width,8)]; m.levelIndicatorStyle=NSLevelIndicatorStyleContinuousCapacity; m.minValue=0; m.maxValue=1; m.warningValue=1; m.criticalValue=1; m.fillColor=color; m.accessibilityLabel=label;
    [self.popover.contentViewController.view addSubview:m]; return m;
}
- (void)buildInterface {
    self.popover=[NSPopover new]; self.popover.contentViewController=[NSViewController new];
    self.popover.contentViewController.view=[[LightCanvas alloc] initWithFrame:NSMakeRect(0,0,440,732)];
    self.popover.contentViewController.view.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSTextField *title=[self label:@"LightBar" x:24 y:679 width:250]; title.font=[NSFont systemFontOfSize:30 weight:NSFontWeightBold]; title.frame=NSMakeRect(24,677,250,40);
    NSTextField *tagline=[self label:@"A little light. A lot of atmosphere." x:26 y:654 width:380]; tagline.font=[NSFont systemFontOfSize:12]; tagline.textColor=NSColor.secondaryLabelColor;
    [self heading:@"YOUR LIGHT" x:36 y:609];
    self.status=[self label:@"Starting Bluetooth…" x:36 y:585 width:368]; self.status.font=[NSFont systemFontOfSize:11]; self.status.lineBreakMode=NSLineBreakByTruncatingTail; self.status.textColor=[NSColor colorWithSRGBRed:0.57 green:0.8 blue:0.79 alpha:1];
    self.deviceList=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(34,547,220,30) pullsDown:NO]; [self.deviceList addItemWithTitle:@"Find your light"]; [self.popover.contentViewController.view addSubview:self.deviceList];
    [self button:@"Scan" action:@selector(scan:) x:259 y:548 width:64];
    self.connectButton=[self button:@"Connect" action:@selector(connect:) x:326 y:548 width:80];
    [self heading:@"MAKE IT YOURS" x:36 y:478];
    self.powerButton=[self button:@"Turn on" action:@selector(power:) x:314 y:476 width:90]; [self.lightControls addObject:self.powerButton];
    self.preview=[[LightPreview alloc] initWithFrame:NSMakeRect(32,433,376,34)]; self.preview.intensity=0.5; self.preview.toolTip=@"Colour preview · whole bar output"; [self.popover.contentViewController.view addSubview:self.preview];
    NSArray *colors=@[[NSColor colorWithSRGBRed:1 green:0.15 blue:0.2 alpha:1],NSColor.orangeColor,NSColor.systemGreenColor,NSColor.systemBlueColor,NSColor.systemPurpleColor,NSColor.whiteColor];
    NSArray *names=@[@"Red",@"Amber",@"Green",@"Blue",@"Purple",@"White"];
    for(NSInteger i=0;i<6;i++){ NSButton *b=[self button:@"●" action:@selector(preset:) x:34+i*48 y:400 width:40]; b.tag=i; b.font=[NSFont systemFontOfSize:23]; b.bordered=NO; b.contentTintColor=colors[i]; b.accessibilityLabel=names[i]; b.toolTip=names[i]; [self.lightControls addObject:b]; }
    self.color=[[NSColorWell alloc] initWithFrame:NSMakeRect(356,400,46,28)]; self.color.color=[self colorFromHex:[[NSUserDefaults standardUserDefaults] stringForKey:@"StaticLightColor"]?:@"FF640A"]; self.color.target=self; self.color.action=@selector(colour:); self.color.accessibilityLabel=@"Custom light colour"; [self.popover.contentViewController.view addSubview:self.color]; [self.lightControls addObject:self.color]; self.preview.lightColor=self.color.color;
    self.brightnessLabel=[self label:@"Brightness · 70%" x:36 y:370 width:240]; self.brightnessLabel.font=[NSFont systemFontOfSize:12];
    self.brightness=[NSSlider sliderWithValue:70 minValue:0 maxValue:100 target:self action:@selector(brightnessChanged:)]; self.brightness.frame=NSMakeRect(36,343,366,22); self.brightness.continuous=NO; self.brightness.accessibilityLabel=@"Brightness"; [self.popover.contentViewController.view addSubview:self.brightness]; [self.lightControls addObject:self.brightness];
    [self heading:@"MUSIC, IN COLOUR" x:36 y:257];
    self.paletteHex=@[@[],@[@"FF3864",@"9B5CFF",@"2DE2E6"],@[@"FF6B35",@"F73670",@"8B5CF6"],@[@"00D9A5",@"45B8FF",@"AA7DFF"],@[@"FF392E",@"FF9438",@"FFD080"],@[@"164BFF",@"00B8D9",@"75F7DC"]];
    NSArray *stored=[[NSUserDefaults standardUserDefaults] arrayForKey:@"CustomMusicPalette"];
    NSMutableArray *custom=[NSMutableArray new];
    for(int i=0;i<3;i++) [custom addObject:[self colorFromHex:(stored.count==3 && [stored[i] isKindOfClass:NSString.class])?stored[i]:self.paletteHex[1][i]]]; self.customPalette=custom;
    self.paletteMenu=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(34,229,254,28) pullsDown:NO];
    [self.paletteMenu addItemsWithTitles:@[@"Original spectrum",@"Neon · pink / violet / cyan",@"Sunset · coral / rose / violet",@"Aurora · mint / sky / lilac",@"Ember · red / amber / gold",@"Ocean · cobalt / teal / mint",@"Single colour",@"Custom palette"]];
    NSInteger selected=[[NSUserDefaults standardUserDefaults] objectForKey:@"MusicPaletteIndex"]?[[NSUserDefaults standardUserDefaults] integerForKey:@"MusicPaletteIndex"]:1; [self.paletteMenu selectItemAtIndex:MAX(0,MIN(7,selected))]; self.paletteMenu.target=self; self.paletteMenu.action=@selector(paletteChanged:); self.paletteMenu.accessibilityLabel=@"Music colour palette"; [self.popover.contentViewController.view addSubview:self.paletteMenu];
    [self button:@"Edit colours…" action:@selector(editPalette:) x:292 y:230 width:114];
    self.audioButton=[self button:@"Start music sync" action:@selector(toggleAudio:) x:34 y:195 width:372]; self.audioButton.bezelColor=[NSColor colorWithSRGBRed:0.46 green:0.3 blue:0.85 alpha:1]; [self.lightControls addObject:self.audioButton];
    [self heading:@"BASS" x:36 y:166]; [self heading:@"MID" x:162 y:166]; [self heading:@"TREBLE" x:288 y:166];
    self.bassMeter=[self meterAtX:36 y:152 width:110 color:NSColor.systemOrangeColor label:@"Bass energy"];
    self.midMeter=[self meterAtX:162 y:152 width:110 color:NSColor.systemPurpleColor label:@"Middle frequency energy"];
    self.trebleMeter=[self meterAtX:288 y:152 width:110 color:NSColor.systemTealColor label:@"Treble energy"];
    NSTextField *sensitivity=[self label:@"Sensitivity" x:36 y:115 width:95]; sensitivity.font=[NSFont systemFontOfSize:12];
    self.sensitivity=[NSSlider sliderWithValue:2 minValue:0.5 maxValue:8 target:nil action:nil]; self.sensitivity.frame=NSMakeRect(139,115,263,22); self.sensitivity.accessibilityLabel=@"Audio sensitivity"; [self.popover.contentViewController.view addSubview:self.sensitivity];
    self.experimentalSwitch=[NSButton checkboxWithTitle:@"Experimental BPM" target:self action:@selector(toggleExperimental:)]; self.experimentalSwitch.frame=NSMakeRect(36,78,230,24); self.experimentalSwitch.font=[NSFont systemFontOfSize:12]; [self.popover.contentViewController.view addSubview:self.experimentalSwitch];
    [self button:@"Live view ↗" action:@selector(showExperiment:) x:298 y:77 width:108];
    [self button:@"Animation Studio" action:@selector(showStudio:) x:20 y:17 width:140];
    [self button:@"Disconnect" action:@selector(disconnect:) x:168 y:17 width:112];
    [self button:@"Quit LightBar" action:@selector(quit:) x:290 y:17 width:130];
    // Keep animations in a separate native menu to give the main panel breathing room.
    self.modes=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.modes addItemWithTitle:@"Choose an effect…"]; self.modes.lastItem.tag=-1;
    NSDictionary *effects=self.effects[@"ANIMATION_MODES"];
    NSArray *keys=[[effects allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ return [@([a intValue]) compare:@([b intValue])]; }];
    for(NSString *key in keys) { [self.modes addItemWithTitle:effects[key]]; self.modes.lastItem.tag=key.integerValue; }
    self.speed=[NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(speedChanged:)]; self.speed.continuous=NO;
}
- (NSColor *)colorFromHex:(NSString *)hex {
    unsigned value=0; if(hex.length!=6 || ![[NSScanner scannerWithString:hex] scanHexInt:&value]) value=0x9B5CFF;
    return [NSColor colorWithSRGBRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
}
- (NSArray<NSColor *> *)musicPalette {
    NSInteger index=self.paletteMenu.indexOfSelectedItem;
    if(index==7) return self.customPalette;
    if(index==6) return @[self.color.color,self.color.color,self.color.color];
    if(index<=0) return @[];
    NSMutableArray *colors=[NSMutableArray new]; for(NSString *hex in self.paletteHex[index]) [colors addObject:[self colorFromHex:hex]]; return colors;
}
- (void)paletteChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setInteger:self.paletteMenu.indexOfSelectedItem forKey:@"MusicPaletteIndex"];
    NSArray *colors=[self musicPalette];
    for(NSInteger i=0;i<3;i++) if(self.paletteWells.count==3) self.paletteWells[i].color=colors.count==3?colors[i]:self.customPalette[i];
    self.blendedPalette=nil;
}
- (void)customPaletteChanged:(id)sender {
    NSMutableArray *colors=[NSMutableArray new], *hex=[NSMutableArray new];
    for(NSColorWell *well in self.paletteWells) { NSColor *c=[well.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; [colors addObject:c]; [hex addObject:[NSString stringWithFormat:@"%02X%02X%02X",(int)lround(c.redComponent*255),(int)lround(c.greenComponent*255),(int)lround(c.blueComponent*255)]]; }
    self.customPalette=colors; [[NSUserDefaults standardUserDefaults] setObject:hex forKey:@"CustomMusicPalette"]; [self.paletteMenu selectItemAtIndex:7]; [self paletteChanged:nil];
}
- (void)editPalette:(id)sender {
    if(!self.palettePanel) {
        self.palettePanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,400,200) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO]; self.palettePanel.contentView=[[MusicLabCanvas alloc] initWithFrame:NSMakeRect(0,0,400,200)]; self.palettePanel.title=@"Music colours"; self.palettePanel.releasedWhenClosed=NO; self.palettePanel.hidesOnDeactivate=NO; self.palettePanel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSArray *names=@[@"Bass",@"Mids",@"Treble"]; NSMutableArray *wells=[NSMutableArray new];
        for(int i=0;i<3;i++) { NSTextField *label=[NSTextField labelWithString:names[i]]; label.frame=NSMakeRect(28+i*124,145,100,24); [self.palettePanel.contentView addSubview:label]; NSColorWell *well=[[NSColorWell alloc] initWithFrame:NSMakeRect(28+i*124,85,96,52)]; well.target=self; well.action=@selector(customPaletteChanged:); well.accessibilityLabel=[names[i] stringByAppendingString:@" music colour"]; [self.palettePanel.contentView addSubview:well]; [wells addObject:well]; }
        self.paletteWells=wells;
        NSTextField *hint=[NSTextField wrappingLabelWithString:@"Choose three colours. Changes apply live to both music reactions and are saved on this Mac."]; hint.font=[NSFont systemFontOfSize:11]; hint.textColor=NSColor.secondaryLabelColor; hint.frame=NSMakeRect(28,23,344,42); [self.palettePanel.contentView addSubview:hint]; [self.palettePanel center];
    }
    [self paletteChanged:nil]; [self.palettePanel makeKeyAndOrderFront:nil];
}
- (void)toggleExperimental:(id)sender {
    self.musicEngine=(MusicEngine){0}; [self.spectrogram clear];
    self.tempoLabel.stringValue=@"Listening for a beat…"; self.confidenceLabel.stringValue=@"Estimate needs several seconds of steady rhythm.";
    if(self.experimentalSwitch.state==NSControlStateValueOn) [self showExperiment:nil];
}
- (void)showExperiment:(id)sender {
    if(!self.experimentPanel) {
        self.experimentPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,480,290) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO]; self.experimentPanel.releasedWhenClosed=NO; self.experimentPanel.hidesOnDeactivate=NO; self.experimentPanel.title=@"Music lab · Experimental"; self.experimentPanel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.experimentPanel.contentView=[[MusicLabCanvas alloc] initWithFrame:NSMakeRect(0,0,480,290)];
        NSView *view=self.experimentPanel.contentView;
        self.tempoLabel=[NSTextField labelWithString:@"Listening for a beat…"]; self.tempoLabel.font=[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold]; self.tempoLabel.frame=NSMakeRect(24,236,432,34); [view addSubview:self.tempoLabel];
        self.confidenceLabel=[NSTextField labelWithString:@"Enable Experimental BPM and start music sync."]; self.confidenceLabel.font=[NSFont systemFontOfSize:11]; self.confidenceLabel.textColor=NSColor.secondaryLabelColor; self.confidenceLabel.frame=NSMakeRect(24,207,432,22); [view addSubview:self.confidenceLabel];
        self.spectrogram=[[MusicSpectrogram alloc] initWithFrame:NSMakeRect(24,63,432,132)]; self.spectrogram.accessibilityLabel=@"Frequency history: bass at bottom, treble at top, newest at right"; [view addSubview:self.spectrogram];
        NSTextField *legend=[NSTextField labelWithString:@"Bass ↓   Treble ↑                      Newest sound →"]; legend.font=[NSFont systemFontOfSize:10]; legend.textColor=NSColor.secondaryLabelColor; legend.frame=NSMakeRect(24,38,432,20); [view addSubview:legend];
        NSTextField *note=[NSTextField labelWithString:@"Whole-bar output · tempo can be half or double the song’s beat."]; note.font=[NSFont systemFontOfSize:10]; note.textColor=NSColor.secondaryLabelColor; note.frame=NSMakeRect(24,12,440,20); [view addSubview:note]; [self.experimentPanel center];
    }
    [self.experimentPanel makeKeyAndOrderFront:nil];
}
- (NSTextField *)studioText:(NSString *)text frame:(NSRect)frame size:(CGFloat)size {
    NSTextField *label=[NSTextField wrappingLabelWithString:text]; label.frame=frame; label.font=[NSFont systemFontOfSize:size]; [self.studioPanel.contentView addSubview:label]; return label;
}
- (void)showStudio:(id)sender {
    if(!self.studioPanel) {
        self.studioPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,460,350) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO]; self.studioPanel.title=@"Animation Studio · Experimental"; self.studioPanel.releasedWhenClosed=NO; self.studioPanel.hidesOnDeactivate=NO; self.studioPanel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.studioPanel.contentView=[[MusicLabCanvas alloc] initWithFrame:NSMakeRect(0,0,460,350)];
        [self studioText:@"Movement meets music" frame:NSMakeRect(24,302,412,32) size:24];
        self.animationLayer=[NSButton checkboxWithTitle:@"Add built-in animation to music sync" target:self action:@selector(animationLayerChanged:)]; self.animationLayer.frame=NSMakeRect(24,262,412,28); [self.studioPanel.contentView addSubview:self.animationLayer];
        self.studioPattern=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(22,219,416,30) pullsDown:NO];
        for(NSMenuItem *item in self.modes.itemArray) { if(item.tag<0)continue; [self.studioPattern addItemWithTitle:item.title]; self.studioPattern.lastItem.tag=item.tag; }
        [self.studioPattern selectItemWithTag:83]; self.studioPattern.target=self; self.studioPattern.action=@selector(animationLayerChanged:); self.studioPattern.accessibilityLabel=@"Music animation pattern"; [self.studioPanel.contentView addSubview:self.studioPattern];
        [self studioText:@"Reference speed · adjust until movement feels right" frame:NSMakeRect(24,183,412,24) size:12];
        self.referenceSpeed=[NSSlider sliderWithValue:50 minValue:1 maxValue:100 target:self action:@selector(animationReferenceChanged:)]; self.referenceSpeed.frame=NSMakeRect(24,153,412,24); self.referenceSpeed.continuous=NO; self.referenceSpeed.accessibilityLabel=@"Reference animation speed"; [self.studioPanel.contentView addSubview:self.referenceSpeed];
        self.studioTempo=[self studioText:@"Start music sync to estimate tempo." frame:NSMakeRect(24,119,412,24) size:12]; self.studioTempo.textColor=NSColor.systemTealColor;
        NSTextField *note=[self studioText:@"Uses built-in colours. Bass accents brightness; tempo adjusts speed. Timing is approximate and needs testing on your light." frame:NSMakeRect(24,66,412,45) size:11]; note.textColor=NSColor.secondaryLabelColor;
        self.studioSyncButton=[NSButton buttonWithTitle:(self.audioRequested?@"Stop music sync":@"Start music sync") target:self action:@selector(toggleAudio:)]; self.studioSyncButton.frame=NSMakeRect(24,20,200,30); self.studioSyncButton.enabled=self.writer!=nil; [self.studioPanel.contentView addSubview:self.studioSyncButton];
        NSButton *browse=[NSButton buttonWithTitle:@"Static animations…" target:self action:@selector(showAnimations:)]; browse.frame=NSMakeRect(236,20,200,30); [self.studioPanel.contentView addSubview:browse];
        [self.studioPanel center];
    }
    [self.studioPanel makeKeyAndOrderFront:nil];
}
- (BOOL)usingAnimationLayer { return self.animationLayer.state==NSControlStateValueOn && self.animationLayer!=nil; }
- (void)animationReferenceChanged:(id)sender { self.lastAnimationSpeed=-1; self.lastAnimationSpeedTime=0; }
- (void)animationLayerChanged:(id)sender {
    self.lastAnimationSpeed=-1; self.lastAnimationBrightness=-1; self.lastAnimationSpeedTime=0;
    if(!self.audioStarted||!self.writer) return;
    [self.pending removeAllObjects];
    if([self usingAnimationLayer]) { [self send:Power(YES)]; [self send:Mode((int)self.studioPattern.selectedItem.tag)]; [self send:Brightness(self.brightness.intValue)]; [self showStatus:@"Animation layer · built-in colours, audio-driven movement"]; }
    else { [self send:Brightness(self.brightness.intValue)]; [self showStatus:@"Colour music sync · palette restored"]; }
}
- (void)updateMusicAnimation:(double)now level:(double)level {
    MusicEngine engine=self.musicEngine;
    double confidence=now-engine.lastSignal<2?engine.confidence:0;
    int speed=AnimationTempoSpeed(self.referenceSpeed.doubleValue,engine.bpm,confidence);
    self.studioTempo.stringValue=confidence>0.35?[NSString stringWithFormat:@"≈ %.0f BPM · speed %d%% · approximate timing",engine.bpm,speed]:@"Learning tempo · using reference speed";
    if(self.pending.count||!self.light.canSendWriteWithoutResponse) return;
    if(now-self.lastAnimationSpeedTime>=1 && (self.lastAnimationSpeed<0||abs(speed-self.lastAnimationSpeed)>=3)) {
        [self.light writeValue:Speed(speed) forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse]; self.lastAnimationSpeed=speed; self.lastAnimationSpeedTime=now; return;
    }
    int brightness=AnimationMusicBrightness(self.brightness.doubleValue,level,self.audioEnvelope);
    if(self.lastAnimationBrightness<0||abs(brightness-self.lastAnimationBrightness)>=2) {
        [self.light writeValue:Brightness(brightness) forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse]; self.lastAnimationBrightness=brightness;
    }
}
- (void)showAnimations:(NSButton *)sender {
    if(!self.writer) return;
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Animations"];
    for(NSMenuItem *item in self.modes.itemArray) { if(item.tag<0) continue; NSMenuItem *copy=[[NSMenuItem alloc] initWithTitle:item.title action:@selector(selectAnimation:) keyEquivalent:@""]; copy.tag=item.tag; copy.target=self; [menu addItem:copy]; }
    NSMenuItem *speed=[NSMenuItem new]; NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,260,42)]; self.speed.frame=NSMakeRect(16,8,228,22); self.speed.accessibilityLabel=@"Animation speed"; [view addSubview:self.speed]; speed.view=view; [menu insertItem:speed atIndex:0];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,32) inView:sender];
}
- (void)selectAnimation:(NSMenuItem *)item { [self.modes selectItemWithTag:item.tag]; [self modeChanged:self.modes]; }
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.reconnect=YES; self.devices=[NSMutableArray new]; self.lightControls=[NSMutableArray new]; self.pending=[NSMutableArray new];
    NSURL *url=[[NSBundle mainBundle] URLForResource:@"Effects" withExtension:@"json"];
    NSData *data=[NSData dataWithContentsOfURL:url]; self.effects=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@{};
    self.item=[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.item.autosaveName=@"LightBarMenu"; self.item.button.title=@"💡"; self.item.button.accessibilityLabel=@"LightBar";
    self.item.button.target=self; self.item.button.action=@selector(togglePanel:); self.item.button.toolTip=@"LightBar";
    [self buildInterface];
    [self enableControls:NO]; self.connectButton.enabled=NO;
    self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,440,732) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.panel.title=@"LightBar"; self.panel.releasedWhenClosed=NO; self.panel.hidesOnDeactivate=NO;
    self.panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.panel.titlebarAppearsTransparent=YES; self.panel.backgroundColor=[NSColor colorWithSRGBRed:0.055 green:0.065 blue:0.085 alpha:1];
    self.panel.contentViewController=self.popover.contentViewController;
    if([NSProcessInfo.processInfo.arguments containsObject:@"--preview"] || [NSProcessInfo.processInfo.arguments containsObject:@"--preview-experiment"] || [NSProcessInfo.processInfo.arguments containsObject:@"--preview-palette"] || [NSProcessInfo.processInfo.arguments containsObject:@"--preview-studio"]) {
        self.status.stringValue=@"Ready to connect";
        [self.panel.contentView layoutSubtreeIfNeeded];
        NSView *view=self.popover.contentViewController.view;
        if([NSProcessInfo.processInfo.arguments containsObject:@"--preview-experiment"]) { [self showExperiment:nil]; view=self.experimentPanel.contentView; }
        if([NSProcessInfo.processInfo.arguments containsObject:@"--preview-palette"]) { [self editPalette:nil]; view=self.palettePanel.contentView; }
        if([NSProcessInfo.processInfo.arguments containsObject:@"--preview-studio"]) { [self showStudio:nil]; view=self.studioPanel.contentView; }
        NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/private/tmp/LightBar-preview.png" atomically:YES];
        [NSApp terminate:nil]; return;
    }
    self.central=[[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue() options:@{CBCentralManagerOptionShowPowerAlertKey:@YES}];
    [self.panel center];
    [self log:@"Application started"];
    [self showPanel];
}
- (void)togglePanel:(id)sender {
    if (self.panel.visible) [self.panel orderOut:nil]; else [self showPanel];
}
- (void)showPanel { [NSApp activateIgnoringOtherApps:YES]; [self.panel makeKeyAndOrderFront:nil]; [self log:@"Control panel opened"]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag { [self showPanel]; return YES; }
- (void)enableControls:(BOOL)on { self.studioSyncButton.enabled=on; for(NSControl *c in self.lightControls) c.enabled=on; }
- (void)showStatus:(NSString *)text { self.status.stringValue=text; [self log:text]; }
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if(central.state==CBManagerStatePoweredOn) { [self scan:nil]; }
    else { [self stopAudioRestoring:NO]; self.writer=nil; [self enableControls:NO]; self.connectButton.enabled=NO; [self.pending removeAllObjects];
        NSString *s=central.state==CBManagerStateUnauthorized?@"Allow LightBar in Privacy & Security → Bluetooth":central.state==CBManagerStatePoweredOff?@"Turn Bluetooth on in System Settings":@"Bluetooth is unavailable"; [self showStatus:s]; }
}
- (void)scan:(id)sender {
    if (self.central.state!=CBManagerStatePoweredOn) return;
    [self.scanTimer invalidate]; [self.central stopScan];
    if(!self.light) { [self.devices removeAllObjects]; [self.deviceList removeAllItems]; [self.deviceList addItemWithTitle:@"Looking for your light…"]; self.connectButton.enabled=NO; }
    [self showStatus:@"Scanning… close the light’s iPhone app"];
    [self.central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@NO}];
    self.scanTimer=[NSTimer scheduledTimerWithTimeInterval:12 repeats:NO block:^(NSTimer *t){ [self.central stopScan]; [self showStatus:self.writer?@"Connected · ready": self.devices.count?@"Choose your light, then Connect":@"No compatible light found. Try Scan again."]; }];
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)p advertisementData:(NSDictionary<NSString *,id> *)ad RSSI:(NSNumber *)RSSI {
    NSString *name=ad[CBAdvertisementDataLocalNameKey]?:p.name?:@"";
    BOOL supported=[name.uppercaseString hasPrefix:@"MELK"]||[name.lowercaseString containsString:@"duoco"];
    for(CBUUID *s in ad[CBAdvertisementDataServiceUUIDsKey]) if([s isEqual:[CBUUID UUIDWithString:@"FFF0"]]) supported=YES;
    if(!supported) return;
    for(CBPeripheral *other in self.devices) if([other.identifier isEqual:p.identifier]) return;
    if(!self.devices.count) [self.deviceList removeAllItems];
    [self.devices addObject:p]; [self.deviceList addItemWithTitle:[NSString stringWithFormat:@"%@ · %@ dBm",name.length?name:@"LED controller",RSSI]];
    self.connectButton.enabled=self.light==nil;
    NSString *saved=[[NSUserDefaults standardUserDefaults] stringForKey:@"LightIdentifier"];
    if([saved isEqualToString:p.identifier.UUIDString] && !self.light && self.reconnect) { [self.deviceList selectItemAtIndex:self.devices.count-1]; [self connect:nil]; }
}
- (void)connect:(id)sender {
    NSInteger i=self.deviceList.indexOfSelectedItem; if(self.light||i<0||(NSUInteger)i>=self.devices.count) return;
    [self.central stopScan]; [self.scanTimer invalidate]; self.light=self.devices[i]; self.light.delegate=self;
    self.connectButton.enabled=NO; self.deviceList.enabled=NO; self.reconnect=YES;
    [self showStatus:[NSString stringWithFormat:@"Connecting to %@…",self.light.name?:@"light"]];
    [self.central connectPeripheral:self.light options:nil];
    self.connectionTimer=[NSTimer scheduledTimerWithTimeInterval:12 repeats:NO block:^(NSTimer *t){ if(self.light && !self.writer) { self.reconnect=NO; [self.central cancelPeripheralConnection:self.light]; [self showStatus:@"Connection timed out. Close the phone app and retry."]; } }];
}
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)p { [p discoverServices:@[[CBUUID UUIDWithString:@"FFF0"]]]; }
- (void)peripheral:(CBPeripheral *)p didDiscoverServices:(NSError *)error {
    if(error||!p.services.count) { [self incompatible:@"Required lighting service was not found"]; return; }
    for(CBService *s in p.services) [p discoverCharacteristics:@[[CBUUID UUIDWithString:@"FFF3"]] forService:s];
}
- (void)peripheral:(CBPeripheral *)p didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if(error) { [self incompatible:@"Could not inspect the light’s controls"]; return; }
    for(CBCharacteristic *c in service.characteristics) if([c.UUID isEqual:[CBUUID UUIDWithString:@"FFF3"]] && (c.properties&CBCharacteristicPropertyWriteWithoutResponse)) {
        self.writer=c; [self.connectionTimer invalidate]; [self enableControls:YES];
        [[NSUserDefaults standardUserDefaults] setObject:p.identifier.UUIDString forKey:@"LightIdentifier"];
        self.item.button.toolTip=@"LightBar · connected";
        [self showStatus:[NSString stringWithFormat:@"Connected · %@",p.name?:@"light"]]; return;
    }
    [self incompatible:@"This controller uses a different lighting protocol"];
}
- (void)incompatible:(NSString *)s { self.reconnect=NO; [self.central cancelPeripheralConnection:self.light]; [self showStatus:s]; }
- (void)clearConnection {
    [self stopAudioRestoring:NO];
    self.writer=nil; self.light=nil; [self.pending removeAllObjects]; [self.connectionTimer invalidate]; [self.sendTimer invalidate]; self.sendTimer=nil;
    [self enableControls:NO]; self.deviceList.enabled=YES; self.connectButton.enabled=self.devices.count>0&&self.central.state==CBManagerStatePoweredOn;
    self.item.button.toolTip=@"LightBar · disconnected";
}
- (void)centralManager:(CBCentralManager *)c didFailToConnectPeripheral:(CBPeripheral *)p error:(NSError *)e { [self clearConnection]; [self showStatus:@"Couldn’t connect. Close the iPhone app and retry."]; }
- (void)centralManager:(CBCentralManager *)c didDisconnectPeripheral:(CBPeripheral *)p error:(NSError *)e {
    BOOL retry=self.reconnect&&!self.quitting; [self clearConnection]; [self showStatus:@"Disconnected"];
    if(retry) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ if(!self.light && self.reconnect) [self scan:nil]; });
}
- (void)send:(NSData *)data {
    if(!self.writer||self.light.state!=CBPeripheralStateConnected) return;
    [self.pending addObject:data];
    if(!self.sendTimer) self.sendTimer=[NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *t){ [self flush]; }];
}
- (void)flush {
    if(!self.writer||!self.pending.count) { [self.sendTimer invalidate]; self.sendTimer=nil; return; }
    if(!self.light.canSendWriteWithoutResponse) return;
    NSData *data=self.pending.firstObject; [self.pending removeObjectAtIndex:0];
    [self.light writeValue:data forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse];
    [self log:[NSString stringWithFormat:@"Sent %@",data]];
}
- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)p { [self flush]; }
- (void)power:(NSButton *)b { [self stopAudioRestoring:YES]; BOOL on=[b.title isEqualToString:@"Turn on"]; [self send:Power(on)]; b.title=on?@"Turn off":@"Turn on"; }
- (void)colour:(id)sender {
    NSColor *c=[self.color.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]; if(!c) return;
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"%02X%02X%02X",(int)lround(c.redComponent*255),(int)lround(c.greenComponent*255),(int)lround(c.blueComponent*255)] forKey:@"StaticLightColor"];
    self.preview.lightColor=c; self.preview.needsDisplay=YES;
    if(self.audioRequested) { [self.paletteMenu selectItemAtIndex:6]; [self paletteChanged:nil]; }
    if(!self.audioRequested) [self send:RGB(lround(c.redComponent*255),lround(c.greenComponent*255),lround(c.blueComponent*255))]; [self.modes selectItemAtIndex:0];
}
- (void)preset:(NSButton *)b {
    const int colors[][3]={{255,0,0},{255,100,10},{0,255,0},{0,80,255},{180,0,255},{255,255,255}};
    int i=(int)b.tag; self.color.color=[NSColor colorWithSRGBRed:colors[i][0]/255.0 green:colors[i][1]/255.0 blue:colors[i][2]/255.0 alpha:1]; [self colour:nil];
}
- (void)brightnessChanged:(NSSlider *)s { int p=s.intValue; self.brightnessLabel.stringValue=[NSString stringWithFormat:@"Brightness · %d%%",p]; [self send:Brightness(p)]; }
- (void)modeChanged:(NSPopUpButton *)s { [self stopAudioRestoring:YES]; if(s.selectedItem.tag>=0) [self send:Mode((int)s.selectedItem.tag)]; }
- (void)speedChanged:(NSSlider *)s { [self send:Speed(s.intValue)]; }
- (void)disconnect:(id)sender { [self stopAudioRestoring:YES]; [self flush]; self.reconnect=NO; [self.central stopScan]; [self.scanTimer invalidate]; if(self.light) [self.central cancelPeripheralConnection:self.light]; else [self showStatus:@"Disconnected · click Scan to find your light"]; }
- (void)applicationWillTerminate:(NSNotification *)note { [self stopAudioRestoring:YES]; }
- (void)toggleAudio:(id)sender {
    if(self.audioRequested) { [self stopAudioRestoring:YES]; return; }
    if(!self.writer) return;
    self.blendedPalette=nil; self.musicEngine=(MusicEngine){0}; [self.spectrogram clear]; self.audioRequested=YES; self.audioStarted=NO; NSUInteger generation=++self.audioGeneration;
    self.audioButton.title=@"Cancel audio setup"; [self showStatus:@"Allow macOS recording permission to react to audio"];
    self.audio=[AudioCapture new]; __weak LightBar *weakSelf=self;
    self.audio.onLevel=^(double rms){ LightBar *owner=weakSelf; if(!owner.audioRequested) return; owner.audioPeak=MAX(owner.audioPeak,rms); owner.lastAudioSample=NSProcessInfo.processInfo.systemUptime; };
    self.audio.onBands=^(AudioBands bands){
        LightBar *owner=weakSelf; if(!owner.audioRequested) return; owner.bands=bands;
        if(owner.experimentalSwitch.state==NSControlStateValueOn || [owner usingAnimationLayer]) { MusicEngine engine=owner.musicEngine; double gain=owner.sensitivity.doubleValue; MusicFeed(&engine,NSProcessInfo.processInfo.systemUptime,AudioTarget(bands.bass,gain),AudioTarget(bands.mid,gain),AudioTarget(bands.treble,gain)); owner.musicEngine=engine; }
    };
    self.audio.onSpectrum=^(NSArray<NSNumber *> *bins){ LightBar *owner=weakSelf; if(owner.audioRequested && owner.experimentalSwitch.state==NSControlStateValueOn) [owner.spectrogram appendSpectrum:bins]; };
    self.audio.onStarted=^{
        LightBar *owner=weakSelf; if(!owner||!owner.audioRequested||generation!=owner.audioGeneration) return;
        owner.audioStarted=YES; owner.audioButton.title=@"Stop music sync"; owner.studioSyncButton.title=@"Stop music sync";
        [owner send:Power(YES)]; owner.powerButton.title=@"Turn off";
        [owner send:Brightness(owner.brightness.intValue)];
        if([owner usingAnimationLayer]) [owner animationLayerChanged:nil];
        [owner showStatus:@"Reacting to Mac audio · play some music"];
        owner.audioTimer=[NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer){ [weakSelf audioTick]; }];
        [[NSRunLoop mainRunLoop] addTimer:owner.audioTimer forMode:NSRunLoopCommonModes];
    };
    self.audio.onError=^(NSString *message){
        LightBar *owner=weakSelf; if(!owner||generation!=owner.audioGeneration) return;
        [owner stopAudioRestoring:YES]; [owner showStatus:@"Audio capture unavailable"]; [owner log:[NSString stringWithFormat:@"Audio error: %@",message]];
        NSAlert *alert=[NSAlert new]; alert.messageText=@"Computer audio couldn’t start"; alert.informativeText=message;
        [alert addButtonWithTitle:@"OK"]; [alert beginSheetModalForWindow:owner.panel completionHandler:nil];
    };
    [self.audio start];
}
- (void)audioTick {
    if(!self.audioRequested||!self.audioStarted||!self.writer) return;
    double rms=NSProcessInfo.processInfo.systemUptime-self.lastAudioSample>0.3?0:self.audioPeak; self.audioPeak=0;
    double now=NSProcessInfo.processInfo.systemUptime;
    if(now-self.lastAudioSample>0.3) self.bands=(AudioBands){0};
    double gain=self.sensitivity.doubleValue;
    double bass=AudioTarget(self.bands.bass,gain), mid=AudioTarget(self.bands.mid,gain), high=AudioTarget(self.bands.treble,gain);
    double level=AudioTarget(rms,gain);
    BOOL beat=bass>0.08 && bass>self.averageLevel*1.4+0.06 && now-self.lastBeat>0.26;
    self.averageLevel=self.averageLevel*0.91+bass*0.09;
    if(beat) { self.lastBeat=now; self.beatGlow=1; } else self.beatGlow*=0.68;
    self.audioEnvelope=AudioEnvelope(MIN(1.0,level*0.7+self.beatGlow*bass*0.4),self.audioEnvelope);
    self.bassMeter.doubleValue=bass; self.midMeter.doubleValue=mid; self.trebleMeter.doubleValue=high;
    double total=self.bands.left+self.bands.right;
    double pan=total>0.002?(self.bands.right-self.bands.left)/total:0;
    // Warm bass, violet mids and cyan highs, gently biased by stereo balance.
    double red=bass+mid*0.55+MAX(0,-pan)*0.15*level;
    double green=bass*0.22+high*0.7;
    double blue=mid*0.85+high+MAX(0,pan)*0.15*level;
    double peak=MAX(0.001,MAX(red,MAX(green,blue)));
    NSColor *c=[NSColor colorWithSRGBRed:MIN(1,red/peak) green:MIN(1,green/peak) blue:MIN(1,blue/peak) alpha:1];
    if(self.experimentalSwitch.state==NSControlStateValueOn) {
        MusicEngine engine=self.musicEngine; MusicOutput output=MusicRender(&engine,now,bass,mid,high,level,pan); self.musicEngine=engine;
        c=[NSColor colorWithSRGBRed:output.r green:output.g blue:output.b alpha:1]; self.audioEnvelope=output.intensity;
        self.tempoLabel.stringValue=output.confidence>0.35?[NSString stringWithFormat:@"≈ %.0f BPM",output.bpm]:@"Listening for a beat…";
        self.confidenceLabel.stringValue=output.confidence>0.35?[NSString stringWithFormat:@"%.0f%% rhythm confidence · colour follows song energy",output.confidence*100]:@"Following the spectrum while the beat estimate settles.";
    }
    NSArray *palette=[self musicPalette];
    if(palette.count==3) {
        double weights[3]={bass*(1-MAX(0,pan)*0.2),mid,high*(1+pan*0.2)};
        double total=MAX(0.001,weights[0]+weights[1]+weights[2]),r=0,g=0,b=0;
        for(int i=0;i<3;i++){ NSColor *p=[palette[i] colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; r+=p.redComponent*weights[i]/total; g+=p.greenComponent*weights[i]/total; b+=p.blueComponent*weights[i]/total; }
        NSColor *target=[NSColor colorWithSRGBRed:MIN(1,r) green:MIN(1,g) blue:MIN(1,b) alpha:1];
        self.blendedPalette=self.blendedPalette?[self.blendedPalette blendedColorWithFraction:(self.experimentalSwitch.state==NSControlStateValueOn?0.16:0.35) ofColor:target]:target; c=self.blendedPalette;
    }
    if([self usingAnimationLayer]) {
        self.preview.lightColor=NSColor.whiteColor; self.preview.intensity=self.audioEnvelope; self.preview.needsDisplay=YES;
        self.preview.toolTip=@"Animation brightness preview · physical colours come from the built-in pattern";
        [self updateMusicAnimation:now level:level]; return;
    }
    self.preview.toolTip=@"Colour preview · whole bar output";
    self.preview.lightColor=c; self.preview.intensity=self.audioEnvelope; self.preview.needsDisplay=YES;
    if(self.pending.count||!self.light.canSendWriteWithoutResponse) return;
    c=[c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    double a=self.audioEnvelope;
    [self.light writeValue:Music(lround(c.redComponent*255*a),lround(c.greenComponent*255*a),lround(c.blueComponent*255*a)) forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse];
}
- (void)stopAudioRestoring:(BOOL)restore {
    if(!self.audioRequested && !self.audio) return;
    BOOL started=self.audioStarted; self.audioRequested=NO; self.audioStarted=NO; self.audioGeneration++;
    [self.audioTimer invalidate]; self.audioTimer=nil; [self.audio stop]; self.audio=nil;
    self.musicEngine=(MusicEngine){0}; [self.spectrogram clear]; self.tempoLabel.stringValue=@"Music sync stopped"; self.confidenceLabel.stringValue=@"Start music sync to estimate the beat.";
    self.bands=(AudioBands){0}; self.audioPeak=0; self.audioEnvelope=0; self.averageLevel=0; self.beatGlow=0; self.lastBeat=0; self.bassMeter.doubleValue=0; self.midMeter.doubleValue=0; self.trebleMeter.doubleValue=0; self.audioButton.title=@"Start music sync"; self.studioSyncButton.title=@"Start music sync"; self.studioTempo.stringValue=@"Music sync stopped";
    if(restore && started && self.writer && self.light.state==CBPeripheralStateConnected) {
        [self.pending removeAllObjects];
        NSData *look=nil;
        if([self usingAnimationLayer] && self.light.canSendWriteWithoutResponse) [self.light writeValue:Brightness(self.brightness.intValue) forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse];
        if([self usingAnimationLayer]) look=Mode((int)self.studioPattern.selectedItem.tag);
        else if(self.modes.selectedItem.tag>=0) look=Mode((int)self.modes.selectedItem.tag);
        else { NSColor *c=[self.color.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; look=RGB(lround(c.redComponent*255),lround(c.greenComponent*255),lround(c.blueComponent*255)); }
        if(self.light.canSendWriteWithoutResponse) [self.light writeValue:look forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse]; else [self send:look];
        [self showStatus:@"Audio stopped · returned to selected colour or mode"];
    }
}
- (void)quit:(id)sender { self.quitting=YES; [self disconnect:nil]; [NSApp terminate:nil]; }
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc>1 && strcmp(argv[1],"--test")==0) {
            const uint8_t power[]={0x7e,4,4,1,0,1,255,0,0xef};
            const uint8_t red[]={0x7e,7,5,3,255,0,0,0x10,0xef};
            const uint8_t bright[]={0x7e,4,1,70,0,255,255,0,0xef};
            const uint8_t effect[]={0x7e,5,3,12,6,255,255,0,0xef};
            const uint8_t speed[]={0x7e,4,2,50,255,255,255,0,0xef};
            BOOL ok=[Power(YES) isEqual:[NSData dataWithBytes:power length:9]] && [RGB(255,0,0) isEqual:[NSData dataWithBytes:red length:9]] && [Brightness(70) isEqual:[NSData dataWithBytes:bright length:9]] && [Mode(12) isEqual:[NSData dataWithBytes:effect length:9]] && [Speed(50) isEqual:[NSData dataWithBytes:speed length:9]];
            const uint8_t music[]={0x7e,7,5,3,128,64,0,0x20,0xef};
            float silence[4]={0,0,0,0}, tone[4]={0.5,-0.5,0.5,-0.5};
            ok=ok && [Music(128,64,0) isEqual:[NSData dataWithBytes:music length:9]];
            ok=ok && AudioRMS(silence,4)==0 && fabs(AudioRMS(tone,4)-0.5)<1e-6;
            ok=ok && AudioTarget(0,2)==0 && AudioTarget(1,8)==1 && AudioTarget(NAN,2)==0;
            ok=ok && AudioTarget(0.1,4)>AudioTarget(0.1,1);
            double envelope=1; for(int i=0;i<40;i++) envelope=AudioEnvelope(0,envelope);
            ok=ok && envelope==0 && AudioEnvelope(0.9,0.1)==0.9;
            float low[4800], high[4800], zero[4800]={0};
            for(int i=0;i<4800;i++){ low[i]=0.5*sin(2*M_PI*80*i/48000); high[i]=0.5*sin(2*M_PI*6000*i/48000); }
            BandFilter f1={0}, f2={0}; AudioBands lowBands=AnalyzeAudio(&f1,low,zero,4800,48000), highBands=AnalyzeAudio(&f2,high,high,4800,48000);
            ok=ok && lowBands.bass>lowBands.treble*3 && highBands.treble>highBands.bass*3 && lowBands.left>0.3 && lowBands.right<0.001;
            printf("Frequency and stereo checks: %s\n",ok?"PASS":"FAIL");
            printf("Audio level, silence, sensitivity, and decay checks: %s\n",ok?"PASS":"FAIL");
            ok=MusicEngineTests() && ok;
            ok=ok && AnimationTempoSpeed(50,120,1)==50 && AnimationTempoSpeed(50,180,1)==75 && AnimationTempoSpeed(50,0,0)==50 && AnimationTempoSpeed(90,180,1)==100;
            ok=ok && AnimationMusicBrightness(70,0,1)==0 && AnimationMusicBrightness(70,1,1)==70 && AnimationMusicBrightness(30,1,2)==30 && AnimationMusicBrightness(70,NAN,1)==0;
            printf("Animation speed and brightness bounds: %s\n",ok?"PASS":"FAIL");
            printf("Protocol frame checks: %s\n",ok?"PASS":"FAIL"); return ok?0:1;
        }
        NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        LightBar *delegate=[LightBar new]; app.delegate=delegate; [app run];
    } return 0;
}
