//
//  RNConsole.m
//  Created by Jordan Alcott on 4/30/21
//

#import <Foundation/Foundation.h>
#import <React/RCTLog.h>
#import "RNConsole.h"


@implementation RNConsole

+(bool) log:(NSString *) str {
  RCTLogInfo(@"%@", str);
  return true;
}

@end
