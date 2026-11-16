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
