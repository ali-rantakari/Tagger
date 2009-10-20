//
//  OpenMetaAuthenticate.m
//  leap
//
//  Created by Tom Andersen on 19/05/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

// This file is optional. If you use it you also need to use the Security Framework

#import "OpenMetaAuthenticate.h"
#include <sys/types.h>
#include <sys/wait.h>


NSString* const OM_CantSetMetadataErrorString = @"OpenMeta can't set the meta data, likely a permissions problem";


// this file is optional. Without it, you can't authenticate and set tags using UI.
// in order to use it you need to add the header and the implementation file, and also link to the correct framework "Security"

@implementation OpenMeta (Authenticated)
#pragma mark setting tags with AuthorizationRef
//----------------------------------------------------------------------
//	getAuthenticationPossiblyUsingUI
//
//	Purpose:	returns an authentication refereence that you can use to execute a command line tool with.
//
//	Inputs:		The 
//
//	Outputs:	AuthorizationRef if you get a nil auth, means don't do it. If you get a non nil, 
//				DO NOT FREE the returned Authorization! it is a shared global. That way, when you do 100 settings in a row,
//				the user only has to type in a password once.
//
//  Created by Tom Andersen on 2008/01/14 
//
//----------------------------------------------------------------------
+(AuthorizationRef)getAuthenticationPossiblyUsingUI:(NSString*)prompt;
{
	static AuthorizationRef gAuthRef = nil;
	static OSStatus gAuthCreateStatus;
	static CFAbsoluteTime dontAskForUserInteractionAgainUntil = 0.0;
	
	if (gAuthRef == nil)
	{
		gAuthCreateStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &gAuthRef);
	}

	if (gAuthCreateStatus != errAuthorizationSuccess) 
	{
		return nil;
	}
	
	AuthorizationItem authItems = {kAuthorizationRightExecute, 0, NULL, 0};
	AuthorizationRights rights = {1, &authItems};
	AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
#if OPEN_META_NO_UI 
	// of course if the user is not allowed to enter a password, then this will also likely fail. 
	// for command line tools, the answer is to run the tool with sudo for files that need to be tagged
#else
	// if we are on the main thread (is the main thread a real requirement - docs not clear?) and the user has not recently pressed cancel
	// then allow the auth to ask for user interaction
	if ([NSThread isMainThread] && (CFAbsoluteTimeGetCurrent() > dontAskForUserInteractionAgainUntil))
		flags += kAuthorizationFlagInteractionAllowed;
#endif
	// create an authItem for the passed prompt.
	AuthorizationItem promptItem;
	promptItem.name = kAuthorizationEnvironmentPrompt;
	promptItem.value = (void*)[prompt UTF8String];
	promptItem.valueLength = strlen(promptItem.value);
	promptItem.flags = 0;
	
	AuthorizationEnvironment authEnvironment;
	authEnvironment.count = 1;
	authEnvironment.items = &promptItem;
	
	OSStatus status = AuthorizationCopyRights(gAuthRef, &rights, &authEnvironment, flags, NULL);
	
	if (status == errAuthorizationCanceled)
		dontAskForUserInteractionAgainUntil = CFAbsoluteTimeGetCurrent() + 20.0; // how can you tell how often to bug user if they cancelled once?
	
	if (status != errAuthorizationSuccess) 
	{
	   return nil;
	}
	return gAuthRef;
}

//----------------------------------------------------------------------
//	AuthenticatedXAttr
//
//	Purpose:	
//
//	Inputs:		plistObject is either nil to remove the attribute, or a plist object like a dict/array
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/05/17 
//
//----------------------------------------------------------------------
+(NSError*)authenticatedSetXAttr:(id)plistObject forKey:(NSString*)inKeyName path:(NSString*)path;
{
	if ([inKeyName length] == 0 || [path length] == 0)
		return [NSError errorWithDomain:@"openmeta" code:OM_CantSetMetadataError userInfo:[NSDictionary dictionaryWithObject:OM_CantSetMetadataErrorString forKey:@"info"]];
	
	AuthorizationRef authRef = [self getAuthenticationPossiblyUsingUI:NSLocalizedString(@"You need to authorize to set metadata like tags on some files.\n", @"")];
	if (authRef == nil)
		return [NSError errorWithDomain:@"openmeta" code:OM_CantSetMetadataError userInfo:[NSDictionary dictionaryWithObject:OM_CantSetMetadataErrorString forKey:@"info"]];
	
	// I don't think that you can set binary data using the command line. 
	// So either we make a command line tool that takes in an xml plist as an arg (can args be 4k long or longer?)
	// and then binaryize it, or we just try writing xml formatted plists to objects that we don't have permission to write to:
	// if spotlight and the OS can deal with xml plists, then this mehod is much much simpler and hence likely more secure.
	NSString* stringToSendNS = nil;
	if (plistObject)
	{
		NSString *errorString = nil;
		NSData* dataToSendNS = [NSPropertyListSerialization dataFromPropertyList:plistObject
																				format:kCFPropertyListXMLFormat_v1_0
																				errorDescription:&errorString];
		if (errorString)
		{
			[errorString autorelease];
			[dataToSendNS release];
			dataToSendNS = nil;
		}
		
		if (dataToSendNS)
			stringToSendNS = [[NSString alloc] initWithBytes:[dataToSendNS bytes] length:[dataToSendNS length] encoding:NSUTF8StringEncoding];
	}
	
	
	//   xattr -w attr_name attr_value file [file ...] // will write xattr
	//   xattr -d attr_name file [file ...]  // will delete xattr
	char* args[5];
	if ([stringToSendNS length] > 0)
	{
		args[0] = "-w";
		args[1] = (char*) [inKeyName fileSystemRepresentation];
		args[2] = (char*) [stringToSendNS UTF8String];
		args[3] = (char*) [path fileSystemRepresentation];
		args[4] = NULL;
	}
	else
	{
		args[0] = "-d";
		args[1] = (char*) [inKeyName fileSystemRepresentation];
		args[2] = (char*) [path fileSystemRepresentation];
		args[3] = NULL;
	}
	
	// I think that by calling this in a synch fashion, we make the somewhat non robust use of waitpid work better.
	// that way we wait for the right process to finish more of the time.
	OSStatus ret = 0;
	static NSNumber* theSyncItem = nil;
	if (theSyncItem == nil)
		theSyncItem = [[NSNumber alloc] initWithDouble:0.34343];
	@synchronized(theSyncItem)
	{
		// as the docs say "AuthorizationExecuteWithPrivileges function poses a security concern because it will indiscriminately run any tool or application"
		// but we are hard coding the tool to run - i think that this fixes that problem? Also the tool is located in an area that requires root access to over write.
		// NOTE: Errors are printed to stderr, not stdout. "There's no way to capture it from the authorization API" so not much use connecting a pipe. 
		// callers will need to attempt a read of the attributes they thought were set...
		// In BetterAuthSample, Apple says that for occasional use that this is the right design pattern - to call AuthorizationExecuteWithPrivileges directly
		ret = AuthorizationExecuteWithPrivileges(authRef, "/usr/bin/xattr", kAuthorizationFlagDefaults, args, NULL);
		
		// found on the internet. (with additions by Tom).
		//What's This About Zombies?
		//  --------------------------
		//  AuthorizationExecuteWithPrivileges creates a process that runs with privileges. 
		//  This process is a child of our process.  Thus, we need to reap the process 
		//  (by calling <x-man-page://2/waitpid>).  If we don't do this, we create a 'zombie' 
		//  process (<x-man-page://1/ps> displays its status as "Z") that persists until 
		//  our process quits (at which point the zombie gets reparented to launchd, and 
		//  launchd automatically reaps it).  Zombies are generally considered poor form. 
		//  Thus, we want to avoid creating them.
		
		// Tom adds: With about 200 to 300 calls to this, we make enough zombies that for whatever reason  
		//  applications refuse to launch on the machine (10.5 anyways), (terminal sessions too), with an -10810 error.
		// Other people claim that there is no problem (other than small resource usage) with having lots of zombies,
		// so I wonder if the problem is that these are _ Python _ zombies, which do sound pretty scary, bein like undead snakes and all.
		//  example ps -Av listing:
		//11884 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//11883 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//11882 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//11878 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//11877 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//11876 Z      0:00.00   0   0      0        0      0     -        0   0.0  0.0 (Python)
		//
		// Too many of these python zombies and you run into the 'The Application xxxxx cannot be launched" -10810 error dialog.
		
		//  Unfortunately, AEWP doesn't return the process ID of the child process 
		//  <rdar://problem/3090277>, which makes it challenging for us to reap it.  We could 
		//  reap all children (by passing -1 to waitpid) but that's not cool for library code 
		//  (we could end up reaping a child process that's completely unrelated to this 
		//  code, perhaps created by some other part of the host application).  Thus, we need 
		//  to find the child process's PID.  And the only way to do that is for the child 
		//  process to tell us.
		//
		//  So, in the child process (the install tool) we echo the process ID and in the 
		//  parent we look for that in the returned text.  *sigh*  It's pretty ugly, but 
		//  that's the best I can come up with.  We delimit the process ID with some 
		//  pretty distinctive text to make it clear that we've got the right thing.

		// tom adds:
		//	This IS library code - but I don't want to make a wrapper for xattr, 
		//	so I wait for any child process to finish... 
		// this will likely work most of the time. In the case that some other child process finishes before the xattr call,
		// the side effect will be to leave a few zombies lying around.
		int status = 0;
		if (ret == errAuthorizationSuccess) // only wait if we actually launched xattr
			waitpid(-1, &status, 0);
	}
	
	if (ret == errAuthorizationSuccess)
		return nil;
	
	// i seem to get quite frequently the error errAuthorizationToolEnvironmentError coming back, but the xattrs are getting set. 
	// not quite sure what it means, but I will rate it as 'not a problem' and return 
	if (ret == errAuthorizationToolEnvironmentError)
		return nil;
		
	return [NSError errorWithDomain:@"openmeta" code:OM_CantSetMetadataError userInfo:[NSDictionary dictionaryWithObject:OM_CantSetMetadataErrorString forKey:@"info"]];
}


@end
