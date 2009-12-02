//
//  AVCVideoCapController.m
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-07.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.

#import <Cocoa/Cocoa.h>

@class PVRDeviceInfo;

@interface AVCVideoCapController : NSObject {

	UInt32 overrunCount;
	UInt32 droppedCount;
	UInt32 lastEMIValue;
	
}

-(NSDateComponents *)getTimeComponents;

- (void) incrementDCLOverrunCount;
- (void) resetDCLOverrunCount;

- (void) incrementDroppedFrameCount;
- (void) resetDroppedFrameCount;

- (void) setCurrentEMI:(UInt32)emiValue;

- (void) abortCapture: (NSString*) abortString;

-(CFMutableArrayRef)devices;

#pragma mark -
#pragma mark Device Control
-(PVRDeviceInfo*)deviceInfo:(UInt32)myDeviceIndex;
-(BOOL)startDevice:(UInt32)myDeviceIndex;
-(void)turnDeviceOn:(UInt32)myDeviceIndex;
-(BOOL)changeChannel:(NSInteger)toChannelNumber onDevice:(UInt32)myDeviceIndex;
-(BOOL)startRecordingFromDeviceAtIndex:(UInt32)myDeviceIndex;
-(BOOL)startRecordingFromDeviceAtIndex:(UInt32)myDeviceIndex toFile:(NSString*)fileName;

@end
