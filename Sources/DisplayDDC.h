#import <Foundation/Foundation.h>

// DDC/CI (MCCS) wire format. No guessed readings or implicit maximum of 100.
FOUNDATION_EXPORT NSData *BBDDCRequest(uint8_t code, NSNumber *value);
FOUNDATION_EXPORT NSDictionary *BBDDCParseReply(NSData *data, uint8_t code);
FOUNDATION_EXPORT NSDictionary *BBEDIDIdentity(NSData *data);
FOUNDATION_EXPORT NSString *BBDisplayNameKey(NSString *name);
FOUNDATION_EXPORT BOOL BBDisplayIdentityMatches(NSDictionary *screen, NSDictionary *port);

// Shared gate for UI, media keys and queued DDC writes.
FOUNDATION_EXPORT BOOL BBDisplayControlAvailable(NSDictionary *record, uint8_t code);
