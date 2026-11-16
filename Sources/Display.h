#import <Cocoa/Cocoa.h>

@interface BBDisplayController : NSObject
@property(nonatomic,copy,readonly) NSArray<NSDictionary*> *snapshot;
@property(nonatomic,readonly) BOOL mediaKeysAuthorized;
@property(nonatomic,readonly) BOOL discoveryFinished;
- (instancetype)initWithDefaults:(NSUserDefaults*)defaults;
- (void)setMappingEnabled:(BOOL)enabled identity:(NSString*)identity;
- (BOOL)mappingEnabledForIdentity:(NSString*)identity;
- (void)start;
- (void)startReadOnly;
- (void)stop;
- (void)rescan;
- (void)refreshControls;
- (void)authorizeMediaKeys;
- (void)refreshMediaKeyAuthorization;
- (void)setPercent:(double)percent code:(uint8_t)code identity:(NSString*)identity;
@end

@interface BBDisplayRow : NSView
@property NSDictionary *record;
@property(weak) BBDisplayController *controller;
@property NSSlider *brightnessSlider;
@property NSSlider *volumeSlider;
@property NSSwitch *mappingSwitch;
@property NSButton *refreshButton;
@property BOOL showsSeparator;
- (instancetype)initWithFrame:(NSRect)frame record:(NSDictionary*)record;
@end
