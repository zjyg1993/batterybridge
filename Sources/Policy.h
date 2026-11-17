#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSTimeInterval BBInterval(id value);
FOUNDATION_EXPORT BOOL BBReadingFresh(NSTimeInterval sample,NSTimeInterval now,NSTimeInterval interval);
FOUNDATION_EXPORT BOOL BBQueryDue(NSTimeInterval previous,NSTimeInterval now,NSTimeInterval interval,BOOL forced,BOOL newReceiver);
FOUNDATION_EXPORT NSString *BBIntervalLabel(NSTimeInterval interval);
