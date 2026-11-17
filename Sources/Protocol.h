#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL BBHIDReportMatches(NSData *descriptor, uint8_t reportID, uint8_t mainTag, NSUInteger payloadLength);
FOUNDATION_EXPORT NSData *BBAulaF75Query(void);
FOUNDATION_EXPORT NSDictionary *BBAulaF75Decode(NSData *report, uint8_t reportID);
FOUNDATION_EXPORT NSData *BBAulaSC580Query(uint8_t sequence);
FOUNDATION_EXPORT NSDictionary *BBAulaSC580Decode(NSData *report, uint8_t sequence);
FOUNDATION_EXPORT NSData *BBQHWQuery(uint8_t sequence);
FOUNDATION_EXPORT NSDictionary *BBQHWDecode(NSData *report, uint8_t reportID, uint8_t sequence);
FOUNDATION_EXPORT NSDictionary *BBLogitechDecodeBattery(NSData *payload, uint16_t feature);
FOUNDATION_EXPORT NSDictionary *BBLogitechEnvelope(NSData *report, uint8_t reportID);
FOUNDATION_EXPORT BOOL BBYJXDescriptorMatches(NSData *descriptor);
FOUNDATION_EXPORT NSData *BBYJXOnlineQuery(void);
FOUNDATION_EXPORT NSData *BBYJXBatteryQuery(void);
FOUNDATION_EXPORT NSDictionary *BBYJXDecode(NSData *report, uint8_t reportID);
// Read-only receiver protocols. Razer packets exclude the unnumbered report ID.
FOUNDATION_EXPORT NSData *BBRazerQuery(uint8_t transaction, uint8_t command);
FOUNDATION_EXPORT NSNumber *BBRazerDecode(NSData *report, uint8_t transaction, uint8_t command);
FOUNDATION_EXPORT NSData *BBKeychronQuery(void);
FOUNDATION_EXPORT NSDictionary *BBKeychronDecode(NSData *report, uint8_t reportID);
FOUNDATION_EXPORT NSData *BBGloriousQuery(void);
FOUNDATION_EXPORT NSDictionary *BBGloriousDecode(NSData *report);
FOUNDATION_EXPORT NSData *BBSteelSeriesQuery(void);
FOUNDATION_EXPORT NSDictionary *BBSteelSeriesDecode(NSData *report);
// 2026 receiver expansion; all query builders are read-only getters.
FOUNDATION_EXPORT NSData *BBCompxQuery(uint8_t command);
FOUNDATION_EXPORT NSDictionary *BBCompxDecode(NSData *report, uint8_t reportID, uint8_t command);
FOUNDATION_EXPORT NSData *BBMchoseQuery(NSUInteger payloadLength);
FOUNDATION_EXPORT NSDictionary *BBMchoseDecode(NSData *report, uint8_t reportID);
FOUNDATION_EXPORT NSData *BBATKKeyboardQuery(uint16_t sequence);
FOUNDATION_EXPORT NSDictionary *BBATKKeyboardDecode(NSData *report, uint8_t reportID, uint16_t sequence);
FOUNDATION_EXPORT NSData *BBASUSQuery(BOOL keyboard);
FOUNDATION_EXPORT NSDictionary *BBASUSDecode(NSData *report, uint8_t reportID, BOOL keyboard);
FOUNDATION_EXPORT NSData *BBASUSPairQuery(void);
FOUNDATION_EXPORT NSDictionary *BBASUSPairedKeyboard(NSData *report, uint8_t reportID);
