//
//  AVCVideoCapController.mm
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-07.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.
//
//  Based in part on AVCVideoCapController.mm by ayanowitz from Apple,
//  Provided in the FireWire SDK from http://developer.apple.com/sdk/

//		switch (lastEMIValue)
//			case 0:	[EMI setStringValue:@"Copy Freely"];
//			case 1: [EMI setStringValue:@"No More Copies"]; 
//			case 2:	[EMI setStringValue:@"Copy Once"];
//			case 3:	[EMI setStringValue:@"Copy Never"];
//			default: [EMI setStringValue:@""];


#include <AVCVideoServices/AVCVideoServices.h>
using namespace AVS;

#import "AVCVideoCapController.h"
#import "PVRDeviceInfo.h"

// AVCDeviceController, and AVCDevice callbacks
IOReturn MyAVCDeviceControllerNotification(AVCDeviceController *pAVCDeviceController, void *pRefCon, AVCDevice* pDevice);
IOReturn MyAVCDeviceMessageNotification (class AVCDevice *pAVCDevice,
										 natural_t messageType,
										 void * messageArgument,
										 void *pRefCon);

// MPEG Receiver callbacks
IOReturn MPEGPacketDataStoreHandler(UInt32 tsPacketCount, 
									UInt32 **ppBuf, 
									void *pRefCon, 
									UInt32 isochHeader,
									UInt32 cipHeader0,
									UInt32 cipHeader1,
									UInt32 fireWireTimeStamp);
void MPEGReceiverMessageReceivedProc(UInt32 msg, UInt32 param1, UInt32 param2, void *pRefCon);

// AVCVideoServices based global objects
AVCDeviceController *pAVCDeviceController = nil;
AVCDeviceStream* pAVCDeviceStream = nil;
AVCDevice *pCaptureDevice = nil;

// Other globals
FILE *outFile = nil;
bool captureInProgress = false;
UInt32 packetCount = 0;
UInt32 lastPacketCount = 0;
UInt32 captureStalledCount = 0;

@interface AVCVideoCapController ()

-(AVCDevice*)deviceWithIndex:(UInt32)myDeviceIndex;

@end

@implementation AVCVideoCapController

- (void)awakeFromNib
{
	// Create a AVCDeviceController
	IOReturn err = CreateAVCDeviceController(&pAVCDeviceController,MyAVCDeviceControllerNotification, self);
	if (!pAVCDeviceController)
	{
		// TODO: This should never happen (unless we've run out of memory), but we should handle it cleanly anyway
	}
}


-(NSDateComponents *)getTimeComponents
{
	NSCalendar *currentCalendar = [NSCalendar currentCalendar];
	unsigned int unitFlags = NSMonthCalendarUnit | NSDayCalendarUnit | NSYearCalendarUnit |
	NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
	return [currentCalendar components:unitFlags fromDate:[NSDate date]];
}

-(AVCDevice*)deviceWithIndex:(UInt32)myDeviceIndex {
	return (AVCDevice*) CFArrayGetValueAtIndex(pAVCDeviceController->avcDeviceArray,myDeviceIndex);
}

-(PVRDeviceInfo*)deviceInfo:(UInt32)myDeviceIndex {
	AVCDevice *dev = [self deviceWithIndex:myDeviceIndex];
	UInt16 pNodeID;
	dev->GetCurrentNodeID(&pNodeID);		
	
	PVRDeviceInfo *info = [PVRDeviceInfo deviceInfo];
	info.model = [NSString stringWithCString:dev->deviceName 
									encoding:NSStringEncodingConversionExternalRepresentation];
	info.vendor = [NSString stringWithCString:dev->vendorName 
									 encoding:NSStringEncodingConversionExternalRepresentation];
	info.nodeID = pNodeID;
	return info;
}

-(BOOL)startDevice:(UInt32)myDeviceIndex {
	AVCDevice *dev = [self deviceWithIndex:myDeviceIndex];
	IOReturn res = dev->openDevice(MyAVCDeviceMessageNotification, self);
	return res == kIOReturnSuccess;
}

-(void)turnDeviceOn:(UInt32)myDeviceIndex  {
	IOReturn res;
	UInt8 powerState;
	
	pCaptureDevice = [self deviceWithIndex:myDeviceIndex];
	res = pCaptureDevice->GetPowerState(&powerState);
	if ((res == kIOReturnSuccess) && (powerState == kAVCPowerStateOff))
	{
		pCaptureDevice->SetPowerState(kAVCPowerStateOn);
		
		// Give it time to power up.
		usleep(2000000); // Sleep for two seconds
	}
}

-(BOOL)changeChannel:(NSInteger)toChannelNumber onDevice:(UInt32)myDeviceIndex  {
	
	pCaptureDevice = [self deviceWithIndex:myDeviceIndex];
	PanelSubunitController *panelController = new PanelSubunitController(pCaptureDevice);
	
	IOReturn res = panelController->Tune(toChannelNumber);
	if (res != kIOReturnSuccess)
	{
		delete panelController;
		return false;
	}
	
	// Give it time to transition.
	usleep(5000000); // Sleep for five seconds
	
	delete panelController;
	
	return true;
}

-(BOOL)startRecordingFromDeviceAtIndex:(UInt32)myDeviceIndex {
	packetCount = 0;
	lastPacketCount = 0;
	captureStalledCount = 0;
	[self resetDCLOverrunCount];
	[self resetDroppedFrameCount];
	
	pCaptureDevice = [self deviceWithIndex:myDeviceIndex];
	
	// Attempt to open the device
	if(!pCaptureDevice->isOpened()) {
		if(![self startDevice:myDeviceIndex]) {
			NSLog(@"Could not open device");
			return NO;			
		}
	}
	NSLog(@"Device opened");
	pAVCDeviceStream = pCaptureDevice->CreateMPEGReceiverForDevicePlug(0,
																	   nil, // We'll install the extended callback later (g),
																	   self,
																	   MPEGReceiverMessageReceivedProc,
																	   self,
																	   nil,
																	   kCyclesPerReceiveSegment,
																	   kNumReceiveSegments*2);
	if (pAVCDeviceStream == nil) {
		NSLog(@"Could not create MPEGReceiver");
		[self abortCapture:@"Could not create MPEGReceiver"];
		return NO;
	}
	// Install the extended MPEG receive callback 
	pAVCDeviceStream->pMPEGReceiver->registerExtendedDataPushCallback(MPEGPacketDataStoreHandler,self);
	lastEMIValue = 0xFFFFFFFF;
	pCaptureDevice->StartAVCDeviceStream(pAVCDeviceStream);
	NSLog(@"Capturing from device");
	return YES;
}

-(BOOL)startRecordingFromDeviceAtIndex:(UInt32)myDeviceIndex toFile:(NSString*)fileName {
	outFile = fopen([fileName cStringUsingEncoding:NSStringEncodingConversionExternalRepresentation],"wb");
	if (!outFile)
	{
		NSLog(@"Unable to open output file");
		pCaptureDevice = [self deviceWithIndex:myDeviceIndex];
		pCaptureDevice->closeDevice();
		pCaptureDevice = nil;
		return NO;
	}
	
	NSLog(@"File opened");
	
	NSLog(@"startRecordingFromDeviceAtIndex:toFile: handing over to startRecordingFromDeviceAtIndex:");
	
	return [self startRecordingFromDeviceAtIndex:(UInt32)myDeviceIndex];
}

- (void) abortCapture: (NSString*) abortString
{
	IOReturn res;

	captureInProgress = false;
	if(abortString != nil)
		NSLog(@"Stopping capture because: %@", abortString);	
	
	// Stop and destroy the receive stream object
	if (pAVCDeviceStream)
	{
		pCaptureDevice->StopAVCDeviceStream(pAVCDeviceStream);
		pCaptureDevice->DestroyAVCDeviceStream(pAVCDeviceStream);
		pAVCDeviceStream = nil;
	}

	// Close the file
	if (outFile)
		fclose(outFile);

	pCaptureDevice->closeDevice();
	pCaptureDevice = nil;
}

#pragma mark -
#pragma mark Display updaters
	
- (void) setCurrentEMI:(UInt32)emiValue {
	lastEMIValue = emiValue;
}

- (void) incrementDCLOverrunCount {
	overrunCount += 1;
}

- (void) resetDCLOverrunCount {
	overrunCount = 0;
}

-(void)incrementDroppedFrameCount {
	droppedCount += 1;
}

- (void) resetDroppedFrameCount {
	droppedCount = 0;
}

-(CFMutableArrayRef)devices {
	return pAVCDeviceController->avcDeviceArray;
}

@end



#pragma mark -
#pragma mark AVC Callbacks

IOReturn MyAVCDeviceControllerNotification(AVCDeviceController *pAVCDeviceController, void *pRefCon, AVCDevice* pDevice)
{	
	// Note: This app doesn't use this callback, and instead relies on polling in the userInterfaceUpdateTimerExpired function
}	

IOReturn MyAVCDeviceMessageNotification (class AVCDevice *pAVCDevice,
												 natural_t messageType,
												 void * messageArgument,
												 void *pRefCon)
{
	NSLog(@"MyAVCDeviceMessageNotification!");

	AVCVideoCapController *controller = (AVCVideoCapController*) pRefCon;

	if ((messageType == kIOMessageServiceIsRequestingClose) && (captureInProgress == true))
		[controller abortCapture:@"Device disconnected during capture"];
}

IOReturn MPEGPacketDataStoreHandler(UInt32 tsPacketCount, 
									UInt32 **ppBuf, 
									void *pRefCon, 
									UInt32 isochHeader,
									UInt32 cipHeader0,
									UInt32 cipHeader1,
									UInt32 fireWireTimeStamp)
{
	unsigned int i;
	unsigned int cnt;
	UInt8 *pTSPacketBytes;
	AVCVideoCapController *controller = (AVCVideoCapController*) pRefCon;
	
	// Set the EMI
	[controller setCurrentEMI:((isochHeader & 0x0000000C) >> 2)];

	// Increment packet count for progress display
	packetCount += tsPacketCount;
	
	// Write packets to file
	for (i=0;i<tsPacketCount;i++)
	{
		// Write TS packet to m2t file
		cnt = fwrite(ppBuf[i],1,kMPEG2TSPacketSize,outFile);
		if (cnt != kMPEG2TSPacketSize)
		{
			[controller abortCapture:@"Error writing capture file"];

			return kIOReturnError;
		}
	}
	
	return kIOReturnSuccess;
}	

void MPEGReceiverMessageReceivedProc(UInt32 msg, UInt32 param1, UInt32 param2, void *pRefCon)
{
	AVCVideoCapController *controller = (AVCVideoCapController*) pRefCon;
	NSLog(@"MPEGReceiverMessageReceivedProc!");
	switch (msg)
	{
		case kMpeg2ReceiverDCLOverrun:
		case kMpeg2ReceiverReceivedBadPacket:
			[controller incrementDCLOverrunCount];
			break;
			
		default:
			break;
	};
}
