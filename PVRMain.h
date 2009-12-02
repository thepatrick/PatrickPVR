//
//  PVRMain.h
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-07.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.

#import <Cocoa/Cocoa.h>

@class AVCVideoCapController;

@interface PVRMain : NSObject {

	IBOutlet AVCVideoCapController *cap;
	IBOutlet NSArrayController *recordingsController;
	IBOutlet NSTextField *statusBar;
	
	NSMutableArray *recordings;
	
	NSTimer *dataUpdater;
	NSTimer *whenToStartRecording;
	NSTimer *whenToStopRecording;
	
	BOOL recordingNow;
	
}

@property (nonatomic, retain) IBOutlet AVCVideoCapController *cap;
@property (nonatomic, retain) IBOutlet NSArrayController *recordingsController;
@property (nonatomic, retain) IBOutlet NSTextField *statusBar;

@property (nonatomic, retain) NSMutableArray *recordings;
@property (nonatomic, retain) NSTimer *dataUpdater;
@property (nonatomic, retain) NSTimer *whenToStartRecording;
@property (nonatomic, retain) NSTimer *whenToStopRecording;

-(IBAction)refreshData:(id)sender;
-(void)requestNewData:(NSString*)fromURL;
-(void)gotData:(NSArray*)newData;
-(void)findNextRecording;

-(IBAction)populateDevices:(id)sender;

@end
