#import <Cocoa/Cocoa.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "AudioCapture.h"
#import "AudioMath.h"

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
@property (strong) NSPopUpButton *musicStyle;
@property double averageLevel, beatGlow, musicHue, lastBeat;
@property (strong) NSTimer *audioTimer;
@property double audioPeak, audioEnvelope, lastAudioSample;
@property AudioBands bands;
@property BOOL audioRequested, audioStarted;
@property NSUInteger audioGeneration;
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
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.reconnect=YES; self.devices=[NSMutableArray new]; self.lightControls=[NSMutableArray new]; self.pending=[NSMutableArray new];
    NSURL *url=[[NSBundle mainBundle] URLForResource:@"Effects" withExtension:@"json"];
    NSData *data=[NSData dataWithContentsOfURL:url]; self.effects=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:@{};
    self.item=[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.item.autosaveName=@"LightBarMenu"; self.item.button.title=@"💡"; self.item.button.accessibilityLabel=@"LightBar";
    self.item.button.target=self; self.item.button.action=@selector(togglePanel:); self.item.button.toolTip=@"LightBar";
    self.popover=[NSPopover new]; self.popover.behavior=NSPopoverBehaviorTransient;
    self.popover.contentSize=NSMakeSize(340,670); self.popover.contentViewController=[NSViewController new];
    self.popover.contentViewController.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,340,670)];
    NSTextField *title=[self label:@"LightBar" x:20 y:477 width:220]; title.font=[NSFont boldSystemFontOfSize:21];
    self.status=[self label:@"Starting Bluetooth…" x:20 y:446 width:300]; self.status.font=[NSFont systemFontOfSize:11]; self.status.lineBreakMode=NSLineBreakByTruncatingTail;
    self.deviceList=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(18,407,220,30) pullsDown:NO]; [self.deviceList addItemWithTitle:@"Scan for your light"]; [self.popover.contentViewController.view addSubview:self.deviceList];
    [self button:@"Scan" action:@selector(scan:) x:242 y:408 width:78];
    self.connectButton=[self button:@"Connect" action:@selector(connect:) x:20 y:372 width:144];
    self.powerButton=[self button:@"Turn on" action:@selector(power:) x:176 y:372 width:144]; [self.lightControls addObject:self.powerButton];
    [self label:@"COLOUR" x:20 y:335 width:150].font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    NSArray *names=@[@"Red",@"Amber",@"Green",@"Blue",@"Purple",@"White"];
    NSArray *colors=@[[NSColor systemRedColor],[NSColor orangeColor],[NSColor systemGreenColor],[NSColor systemBlueColor],[NSColor systemPurpleColor],[NSColor whiteColor]];
    for (NSInteger i=0;i<6;i++) { NSButton *b=[self button:@"●" action:@selector(preset:) x:18+i*43 y:300 width:40]; b.tag=i; b.contentTintColor=colors[i]; b.toolTip=names[i]; b.accessibilityLabel=names[i]; [self.lightControls addObject:b]; }
    self.color=[[NSColorWell alloc] initWithFrame:NSMakeRect(282,299,38,29)]; self.color.color=[NSColor orangeColor]; self.color.target=self; self.color.action=@selector(colour:); [self.popover.contentViewController.view addSubview:self.color]; [self.lightControls addObject:self.color];
    self.brightnessLabel=[self label:@"Brightness · 70%" x:20 y:263 width:300];
    self.brightness=[NSSlider sliderWithValue:70 minValue:0 maxValue:100 target:self action:@selector(brightnessChanged:)]; self.brightness.frame=NSMakeRect(20,237,300,22); self.brightness.continuous=NO; [self.popover.contentViewController.view addSubview:self.brightness]; [self.lightControls addObject:self.brightness];
    [self label:@"MODE" x:20 y:202 width:150].font=[NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    self.modes=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(18,169,304,30) pullsDown:NO];
    [self.modes addItemWithTitle:@"Choose an effect…"]; self.modes.lastItem.tag=-1;
    NSDictionary *m=self.effects[@"ANIMATION_MODES"];
    NSArray *keys=[[m allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ return [@([a intValue]) compare:@([b intValue])]; }];
    for (NSString *key in keys) { [self.modes addItemWithTitle:m[key]]; self.modes.lastItem.tag=key.integerValue; }
    self.modes.target=self; self.modes.action=@selector(modeChanged:); [self.popover.contentViewController.view addSubview:self.modes]; [self.lightControls addObject:self.modes];
    [self label:@"Effect speed" x:20 y:137 width:300];
    self.speed=[NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(speedChanged:)]; self.speed.frame=NSMakeRect(20,111,300,22); self.speed.continuous=NO; [self.popover.contentViewController.view addSubview:self.speed]; [self.lightControls addObject:self.speed];
    NSTextField *hint=[self label:@"Controls show your last commands, not live light state." x:20 y:77 width:300]; hint.font=[NSFont systemFontOfSize:10]; hint.textColor=[NSColor secondaryLabelColor];
    for(NSView *view in self.popover.contentViewController.view.subviews) { NSRect frame=view.frame; frame.origin.y+=110; view.frame=frame; }
    self.audioButton=[self button:@"React to Mac audio" action:@selector(toggleAudio:) x:20 y:145 width:300];
    [self.lightControls addObject:self.audioButton];
    self.audioMeter=[[NSLevelIndicator alloc] initWithFrame:NSMakeRect(22,123,296,12)];
    self.audioMeter.levelIndicatorStyle=NSLevelIndicatorStyleContinuousCapacity; self.audioMeter.minValue=0; self.audioMeter.maxValue=1; self.audioMeter.warningValue=0.8; self.audioMeter.criticalValue=0.95;
    self.audioMeter.accessibilityLabel=@"Computer audio level"; [self.popover.contentViewController.view addSubview:self.audioMeter];
    [self label:@"Audio sensitivity" x:20 y:94 width:300];
    self.sensitivity=[NSSlider sliderWithValue:2 minValue:0.5 maxValue:8 target:nil action:nil]; self.sensitivity.frame=NSMakeRect(20,68,300,22); self.sensitivity.accessibilityLabel=@"Audio sensitivity";
    [self.popover.contentViewController.view addSubview:self.sensitivity];
    for(NSView *view in self.popover.contentViewController.view.subviews) { if(view.frame.origin.y>=123) { NSRect frame=view.frame; frame.origin.y+=40; view.frame=frame; } }
    self.musicStyle=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(18,130,304,28) pullsDown:NO];
    [self.musicStyle addItemsWithTitles:@[@"Beat pulse", @"Smooth glow", @"Colour flow", @"Bass pulse", @"Voice-range glow", @"Spectrum colour", @"Stereo colour"]];
    self.musicStyle.accessibilityLabel=@"Music reaction style"; [self.popover.contentViewController.view addSubview:self.musicStyle];
    self.audioButton.toolTip=@"Pulse the selected colour with computer sound. Requires macOS recording permission. Audio is processed locally and never saved.";
    [self button:@"Disconnect" action:@selector(disconnect:) x:20 y:31 width:144];
    [self button:@"Quit LightBar" action:@selector(quit:) x:176 y:31 width:144];
    [self enableControls:NO]; self.connectButton.enabled=NO;
    self.central=[[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue() options:@{CBCentralManagerOptionShowPowerAlertKey:@YES}];
    self.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,340,670) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.panel.title=@"LightBar"; self.panel.releasedWhenClosed=NO; self.panel.hidesOnDeactivate=NO;
    self.panel.contentViewController=self.popover.contentViewController;
    [self.panel center];
    [self log:@"Application started"];
    [self showPanel];
}
- (void)togglePanel:(id)sender {
    if (self.panel.visible) [self.panel orderOut:nil]; else [self showPanel];
}
- (void)showPanel { [NSApp activateIgnoringOtherApps:YES]; [self.panel makeKeyAndOrderFront:nil]; [self log:@"Control panel opened"]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag { [self showPanel]; return YES; }
- (void)enableControls:(BOOL)on { for(NSControl *c in self.lightControls) c.enabled=on; }
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
    self.audioRequested=YES; self.audioStarted=NO; NSUInteger generation=++self.audioGeneration;
    self.audioButton.title=@"Cancel audio setup"; [self showStatus:@"Allow macOS recording permission to react to audio"];
    self.audio=[AudioCapture new]; __weak LightBar *weakSelf=self;
    self.audio.onLevel=^(double rms){ LightBar *owner=weakSelf; if(!owner.audioRequested) return; owner.audioPeak=MAX(owner.audioPeak,rms); owner.lastAudioSample=NSProcessInfo.processInfo.systemUptime; };
    self.audio.onBands=^(AudioBands bands){ LightBar *owner=weakSelf; if(owner.audioRequested) owner.bands=bands; };
    self.audio.onStarted=^{
        LightBar *owner=weakSelf; if(!owner||!owner.audioRequested||generation!=owner.audioGeneration) return;
        owner.audioStarted=YES; owner.audioButton.title=@"Stop reacting to audio";
        [owner send:Power(YES)]; owner.powerButton.title=@"Turn off";
        [owner send:Brightness(owner.brightness.intValue)];
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
    NSInteger style=self.musicStyle.indexOfSelectedItem;
    double input=rms;
    if(style==3) input=self.bands.bass;
    if(style==4) input=self.bands.mid;
    if(now-self.lastAudioSample>0.3) self.bands=(AudioBands){0};
    double level=AudioTarget(input,self.sensitivity.doubleValue);
    BOOL beat=level>0.08 && level>self.averageLevel*1.45+0.06 && now-self.lastBeat>0.26;
    self.averageLevel=self.averageLevel*0.91+level*0.09;
    if(beat) { self.lastBeat=now; self.beatGlow=1; self.musicHue=fmod(self.musicHue+0.075,1.0); }
    else self.beatGlow*=0.68;
    double target=(style==1||style==4) ? level*0.8 : MAX(level*0.55,self.beatGlow*level);
    self.audioEnvelope=AudioEnvelope(target,self.audioEnvelope);
    self.audioMeter.doubleValue=self.audioEnvelope;
    // Real-time frames are disposable. Never queue stale audio behind Bluetooth backpressure.
    if(self.pending.count||!self.light.canSendWriteWithoutResponse) return;
    NSColor *c=[self.color.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; if(!c) return;
    if(style==2) c=[NSColor colorWithCalibratedHue:self.musicHue saturation:0.85 brightness:1 alpha:1];
    if(style==5) {
        double bass=AudioTarget(self.bands.bass,self.sensitivity.doubleValue), mid=AudioTarget(self.bands.mid,self.sensitivity.doubleValue), high=AudioTarget(self.bands.treble,self.sensitivity.doubleValue);
        double maxBand=MAX(bass,MAX(mid,high)); if(maxBand>0) c=[NSColor colorWithSRGBRed:bass/maxBand green:mid/maxBand blue:high/maxBand alpha:1];
    }
    if(style==6) {
        double total=self.bands.left+self.bands.right;
        double pan=total>0.002?(self.bands.right-self.bands.left)/total:0;
        c=[NSColor colorWithCalibratedHue:0.58+0.25*pan saturation:0.85 brightness:1 alpha:1];
    }
    c=[c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    double a=self.audioEnvelope;
    [self.light writeValue:Music(lround(c.redComponent*255*a),lround(c.greenComponent*255*a),lround(c.blueComponent*255*a)) forCharacteristic:self.writer type:CBCharacteristicWriteWithoutResponse];
}
- (void)stopAudioRestoring:(BOOL)restore {
    if(!self.audioRequested && !self.audio) return;
    BOOL started=self.audioStarted; self.audioRequested=NO; self.audioStarted=NO; self.audioGeneration++;
    [self.audioTimer invalidate]; self.audioTimer=nil; [self.audio stop]; self.audio=nil;
    self.bands=(AudioBands){0}; self.audioPeak=0; self.audioEnvelope=0; self.averageLevel=0; self.beatGlow=0; self.lastBeat=0; self.audioMeter.doubleValue=0; self.audioButton.title=@"React to Mac audio";
    if(restore && started && self.writer && self.light.state==CBPeripheralStateConnected) {
        [self.pending removeAllObjects];
        NSData *look=nil;
        if(self.modes.selectedItem.tag>=0) look=Mode((int)self.modes.selectedItem.tag);
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
            printf("Protocol frame checks: %s\n",ok?"PASS":"FAIL"); return ok?0:1;
        }
        NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        LightBar *delegate=[LightBar new]; app.delegate=delegate; [app run];
    } return 0;
}
