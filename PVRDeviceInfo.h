//
//  PVRDeviceInfo.h
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-08.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface PVRDeviceInfo : NSObject {

	NSString *model;
	NSString *vendor;
	UInt16 nodeID;
	
}

@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *vendor;
@property (nonatomic, assign) UInt16 nodeID;

+deviceInfo;

@end
