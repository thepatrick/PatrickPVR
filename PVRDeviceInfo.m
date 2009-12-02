//
//  PVRDeviceInfo.m
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-08.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.
//

#import "PVRDeviceInfo.h"


@implementation PVRDeviceInfo

@synthesize model;
@synthesize vendor;
@synthesize nodeID;

+deviceInfo {
	return [[[self alloc] init] autorelease];
}

@end
