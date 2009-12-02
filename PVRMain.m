//
//  PVRMain.m
//  PatrickPVR
//
//  Created by Patrick Quinn-Graham on 09-02-07.
//  Copyright 2009 Patrick Quinn-Graham. All rights reserved.

#import "AVCVideoCapController.h"
#import "PVRMain.h"
#import "JSON.h"
#import "PVRDeviceInfo.h"
#import "NSDateJSON.h"

@implementation PVRMain

@synthesize cap;
@synthesize recordings;
@synthesize recordingsController;
@synthesize statusBar;
@synthesize dataUpdater;
@synthesize whenToStartRecording;
@synthesize whenToStopRecording;

-(void)awakeFromNib {
	self.recordings = [NSMutableArray arrayWithCapacity:5];
	[recordingsController setContent:recordings];
	[self performSelector:@selector(refreshData:) withObject:nil afterDelay:0];	
	
	self.dataUpdater = [NSTimer scheduledTimerWithTimeInterval:60 
											   target:self 
											 selector:@selector(refreshData:) 
											 userInfo:nil
											  repeats:YES];
}

#pragma mark -
#pragma mark Alert server to status change
-(void)alertServerToRecording:(NSInteger)recordingId statusChangeTo:(NSString*)status {
	NSString *requestURL = [NSString stringWithFormat:@"UpdateStatus.json?id=%d&status=%@", recordingId, [status stringByReplacingPercentEscapesUsingEncoding:NSStringEncodingConversionExternalRepresentation]];
	NSString *dataURL = [[[NSUserDefaults standardUserDefaults] stringForKey:@"EPGServer"] stringByAppendingString:requestURL];
	[self performSelectorInBackground:@selector(alertServerBackground:) withObject:dataURL];
}

-(void)alertServerBackground:(NSString*)fromURL {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[statusBar setTitleWithMnemonic:[@"Updating server " stringByAppendingString:fromURL]];
	NSURL *pvrDataURL = [NSURL URLWithString:fromURL];
	NSError *err;
	NSString *str = [NSString stringWithContentsOfURL:pvrDataURL encoding:NSStringEncodingConversionExternalRepresentation error:&err];

	[self performSelectorOnMainThread:@selector(alertServerBackgroundComplete) 
						   withObject:nil
						waitUntilDone:YES];
	[pool release];
}

-(void)alertServerBackgroundComplete {
	[recordings removeAllObjects];
	[self refreshData:nil];
}
	
#pragma mark -
#pragma mark Refresh Data
-(IBAction)refreshData:(id)sender {
	if(![[NSUserDefaults standardUserDefaults] stringForKey:@"EPGServer"]) {
		return; 
	}
	NSString *dataURL = [[[NSUserDefaults standardUserDefaults] stringForKey:@"EPGServer"] stringByAppendingString:@"Data.json"];
	[self performSelectorInBackground:@selector(requestNewData:) withObject:dataURL];
}

-(void)requestNewData:(NSString*)fromURL {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[statusBar setTitleWithMnemonic:[@"Updating from " stringByAppendingString:fromURL]];
	
	NSURL *pvrDataURL = [NSURL URLWithString:fromURL];
	NSError *err = nil;
	NSString *pvrDataString = [NSString stringWithContentsOfURL:pvrDataURL encoding:NSUTF8StringEncoding error:&err];
	
	if(err) { 
		[statusBar setTitleWithMnemonic:[@"Can't reach server: " stringByAppendingString:fromURL]];
	} else {
		
		//NSLog(@"pvrDataString: %@", pvrDataString);
		
		NSDictionary *newRecordings = [pvrDataString JSONValue];	
		
		
		[self performSelectorOnMainThread:@selector(gotData:) 
							   withObject:[newRecordings objectForKey:@"recordings"]
							waitUntilDone:YES];
	}
	[pool release];
}

-(void)gotData:(NSArray*)newData {
	[recordings removeAllObjects];
	
	for(NSDictionary *d in newData) {
		NSString *jsonDate = [d valueForKey:@"startTime"];
		NSDate *startTime = [NSDate dateWithJSONString:jsonDate];
		[d setValue:startTime forKey:@"startTime"];
		NSInteger duration = [[d valueForKey:@"duration"] integerValue];
		NSDate *endTime = [startTime addTimeInterval:(duration * 60)];
		[d setValue:endTime forKey:@"endTime"];
		//NSLog(@"Date: Start: %@, End: %@", startTime, endTime);
	}
	
	NSSortDescriptor *a = [[[NSSortDescriptor alloc] initWithKey:@"startTime" ascending:YES] autorelease];
	NSArray *sorted = [newData sortedArrayUsingDescriptors:[NSArray arrayWithObject:a]];
	
	[recordings addObjectsFromArray:sorted];
	[recordingsController setContent:recordings];
	[statusBar setTitleWithMnemonic:@"Up to date."];
	
	[self findNextRecording];
}

#pragma mark -
#pragma mark Other stuff

-(IBAction)populateDevices:(id)sender {
	NSMutableArray *devices = (NSMutableArray*)[cap devices];	
	NSInteger devicesCount = [devices count];
	for(NSInteger idx = 0; idx < devicesCount; idx++) {
		PVRDeviceInfo *info = [cap deviceInfo:idx];
		//NSLog(@"Device Name: %@ %@ (%d)", info.model, info.vendor, info.nodeID);
	}
}

-(void)findNextRecording {
	NSDictionary *useThisDictionary = nil;
	for(NSMutableDictionary *d in recordings) {
		if([[d objectForKey:@"status"] isEqualToString:@"New"]) {
			// is the end time in the past?
			int endTimeFromNow = [[d objectForKey:@"endTime"] timeIntervalSinceNow];
			if(endTimeFromNow < 0) {
				[d setObject:@"Missed" forKey:@"status"];
				[self alertServerToRecording:[[d objectForKey:@"id"] integerValue] statusChangeTo:@"Missed"];
			} else {
				useThisDictionary = d;
				break;
			}
		}
	}
	if(useThisDictionary != nil) {
		//NSLog(@"The next recording is: %@", useThisDictionary);
		
		if(whenToStartRecording) {
			[whenToStartRecording invalidate];
		}
		
		int startTimeFromNow = [[useThisDictionary objectForKey:@"startTime"] timeIntervalSinceNow];
		if(startTimeFromNow < 1) startTimeFromNow = 1;
		//NSLog(@"I should start recording in %d seconds", startTimeFromNow );		
		whenToStartRecording = [NSTimer scheduledTimerWithTimeInterval:startTimeFromNow 
																target:self 
															  selector:@selector(shouldStartRecordingNow:) 
															  userInfo:useThisDictionary 
															   repeats:NO];
	}
}

-(void)shouldStartRecordingNow:(NSTimer*)sender {
	if(recordingNow) {
		NSLog(@"Already recording, so can't start  %@", [sender userInfo]);
		// We need to try again in one second.
		whenToStartRecording = [NSTimer scheduledTimerWithTimeInterval:30
																target:self 
															  selector:@selector(shouldStartRecordingNow:) 
															  userInfo:[sender userInfo] 
															   repeats:NO];
		return;
	}
	
	NSLog(@"Timer said I should start recording... now! UserInfo was: %@", [sender userInfo]);
	whenToStartRecording = nil;
	
	recordingNow = YES;
	
	NSMutableDictionary *recDetail = [sender userInfo];
	[recDetail setObject:@"Recording" forKey:@"status"];
	
	
	// tell the EPG this so it doesn't come back down as new.	
	[self alertServerToRecording:[[recDetail objectForKey:@"id"] integerValue] statusChangeTo:@"Recording"];
	
	NSString *fileName = [NSString stringWithFormat:@"/Users/patrick/Movies/Recording/%@.m2t", [recDetail objectForKey:@"showName"]];
	
	[cap startDevice:0];
	[cap turnDeviceOn:0];
	[cap changeChannel:[[recDetail objectForKey:@"channel"] integerValue] onDevice:0];
	[cap startRecordingFromDeviceAtIndex:0 toFile:fileName];
	
	// set up a timer to stop recording
	int endTimeFromNow = [[recDetail objectForKey:@"endTime"] timeIntervalSinceNow];
	NSLog(@"Recording stops in %d seconds", endTimeFromNow);
	
	whenToStopRecording = [NSTimer scheduledTimerWithTimeInterval:endTimeFromNow 
															target:self 
														  selector:@selector(shouldStopRecordingNow:) 
														  userInfo:recDetail 
														   repeats:NO];
}
-(void)shouldStopRecordingNow:(NSTimer*)sender {
	NSLog(@"Recording done!");
	NSMutableDictionary *recDetail = [sender userInfo];
	
	[cap abortCapture:@"Finished"];
	
	[recDetail setObject:@"Done" forKey:@"status"];
	// notify the EPG that it is done so it doesn't come back down as new :)
	[self alertServerToRecording:[[recDetail objectForKey:@"id"] integerValue] statusChangeTo:@"Done"];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	
	whenToStopRecording = nil;
	recordingNow = NO;
	
	NSString *src = [NSString stringWithFormat:@"/Users/patrick/Movies/Recording/%@.m2t", [recDetail objectForKey:@"showName"]];
	NSString *dest = [NSString stringWithFormat:@"/Users/patrick/Movies/%@.m2t", [recDetail objectForKey:@"showName"]];
	NSError *err;
	[fm moveItemAtPath:src toPath:dest error:&err];
	
	[self findNextRecording];
}

@end
