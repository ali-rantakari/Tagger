//
//  TaggerController.m
//  Tagger
//
// Copyright (C) 2008-2009 Ali Rantakari
// You can contact the author at http://hasseg.org
// 
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


// TODO:
// 
// - Add OmniWeb support
// 
// - Fix the HUD Token Field caret problem: http://code.google.com/p/bghudappkit/issues/detail?id=27
// 
// - Make the token field colors more pleasant
// 
// - OpenMeta allows commas in tag names -- how to handle?
// 


// BUGS TO FIX:
// 


#import "TaggerController.h"
#import "NSArray+NSTableViewDataSource.h"
#import "PFMoveApplication.h"
#import "HGVersionNumberCompare.h"


#define kAppSiteURL			@"http://hasseg.org/tagger/"
#define kAppSiteURLPrefix	kAppSiteURL
#define kVersionCheckURL	[NSURL URLWithString:[NSString stringWithFormat:@"%@?versioncheck=y", kAppSiteURLPrefix]]

#define FINDER_BUNDLE_ID		@"com.apple.finder"
#define MAIL_BUNDLE_ID			@"com.apple.mail"
#define SAFARI_BUNDLE_ID		@"com.apple.Safari"
#define FIREFOX_BUNDLE_ID		@"org.mozilla.firefox"
#define CAMINO_BUNDLE_ID		@"org.mozilla.camino"
#define OPERA_BUNDLE_ID			@"com.operasoftware.Opera"
#define PATH_FINDER_BUNDLE_ID	@"com.cocoatech.PathFinder"

// name of the folder where we save the .webloc files
// that we create for tagging web pages
#define WEBLOCS_FOLDER_NAME @"Web Links"

#define GET_SELECTED_FINDER_ITEMS_APPLESCRIPT	\
	@"tell application \"Finder\"\n\
		set retval to \"\"\n\
		set sel to selection\n\
		repeat with i in sel\n\
			set x to POSIX path of (i as alias)\n\
			set retval to (retval & \"\n\" & x)\n\
		end repeat\n\
		return retval\n\
	end tell"
#define GET_SELECTED_PATH_FINDER_ITEMS_APPLESCRIPT	\
	@"tell application \"Path Finder\"\n\
		set retval to \"\"\n\
		set sel to selection\n\
		repeat with i in sel\n\
			set x to POSIX path of i\n\
			set retval to (retval & \"\n\" & x)\n\
		end repeat\n\
		return retval\n\
	end tell"

#define GET_CURRENT_SAFARI_PAGE_TITLE_APPLESCRIPT \
	@"tell application \"Safari\"\n\
		if front document exists\n\
			return name of front document\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"
#define GET_CURRENT_SAFARI_PAGE_URL_APPLESCRIPT \
	@"tell application \"Safari\"\n\
		if front document exists\n\
			return URL of front document\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"

#define GET_CURRENT_FIREFOX_PAGE_TITLE_APPLESCRIPT \
	@"tell application \"System Events\" to tell process \"Firefox\" to set ffWindowsExist to (front window) exists\n\
	tell application \"Firefox\"\n\
		if ffWindowsExist then\n\
			return item 2 of (properties of front window as list)\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"
#define GET_CURRENT_FIREFOX_PAGE_URL_APPLESCRIPT \
	@"tell application \"System Events\" to tell process \"Firefox\" to set ffWindowsExist to (front window) exists\n\
	tell application \"Firefox\"\n\
		if ffWindowsExist then\n\
			return item 3 of (properties of front window as list)\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"

#define GET_CURRENT_OPERA_PAGE_TITLE_APPLESCRIPT \
	@"tell application \"Opera\" to return item 2 of (GetWindowInfo of window 1)"
#define GET_CURRENT_OPERA_PAGE_URL_APPLESCRIPT \
	@"tell application \"Opera\" to return item 1 of (GetWindowInfo of window 1)"

#define GET_CURRENT_CAMINO_PAGE_TITLE_APPLESCRIPT \
	@"tell application \"Camino\"\n\
		if front browser window exists\n\
			return name of front browser window\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"
#define GET_CURRENT_CAMINO_PAGE_URL_APPLESCRIPT \
	@"tell application \"Camino\"\n\
		if front browser window exists\n\
			return URL of current tab of front browser window\n\
		else\n\
			return \"\"\n\
		end if\n\
	end tell"

#define MAIL_GET_FIRST_SELECTED_EMAIL_SUBJECT_APPLESCRIPT \
	@"tell application \"Mail\" to return (subject of first item of (selection as list))"

#define MAIL_GET_SELECTED_EMAILS_APPLESCRIPT \
	@"set emailPaths to \"\"\n\
	set downloaderror to false\n\
	tell application \"Mail\"\n\
		repeat with msg in (selection as list)\n\
			set theId to id of msg\n\
			set thisPath to (do shell script \"mdfind -onlyin ~/Library/Mail \\\"kMDItemFSName = '\" & theId & \".emlx'\\\"\")\n\
			if thisPath = \"\" then\n\
				set downloaderror to true\n\
			else\n\
				set thisPath to (POSIX path of thisPath)\n\
				set emailPaths to emailPaths & \"\n\" & thisPath\n\
			end if\n\
		end repeat\n\
	end tell\n\
	if downloaderror then\n\
	return \"error\"\n\
	end if\n\
	return emailPaths"

#define NO_FILES_TO_TAG_MSG @"Could not get files to tag.\n\
\n\
Tag files by either dropping them on top of Tagger or selecting \
them in Finder (or Path Finder) and then launching Tagger.\n\
\n\
You can also launch Tagger when the frontmost window in the \
active application is a document window, and Tagger will then \
let you tag that document (select the \"Enable access for \
assistive devices\" option in the \"Universal Access\" preference \
pane in System Preferences to enable this feature)."






// Accessibility API helper function: get value of given attribute
// from given accessibility object
id valueOfExistingAttribute(CFStringRef attribute, AXUIElementRef element)
{
	id result = nil;
	NSArray *attrNames;
	
	if (AXUIElementCopyAttributeNames(element, (CFArrayRef *)&attrNames) == kAXErrorSuccess) 
	{
		if ([attrNames indexOfObject:(NSString *)attribute] != NSNotFound &&
			AXUIElementCopyAttributeValue(element, attribute, (CFTypeRef *)&result)
			) 
			[result autorelease];
		[attrNames release];
	}
	
	return result;
}




static NSString* frontAppDocumentURLString = nil;
static NSString* frontAppBundleID = nil;

@implementation TaggerController

@synthesize filesToTag;
@synthesize originalTags;
@synthesize versionCheckConnection;
@synthesize titleArgument;
@synthesize weblocFilesFolderPath;


+ (void) load
{
	NSAutoreleasePool *autoReleasePool = [[NSAutoreleasePool alloc] init];
	
	// if the frontmost application window is a document window,
	// get the document URL represented by that window
	NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
	NSNumber *activeAppPID = [activeAppDict objectForKey:@"NSApplicationProcessIdentifier"];
	NSString *activeAppBundleID = [activeAppDict objectForKey:@"NSApplicationBundleIdentifier"];
	frontAppBundleID = [activeAppBundleID retain];
	
	AXUIElementRef _app = AXUIElementCreateApplication((pid_t)[activeAppPID intValue]);
	AXUIElementRef _window = (AXUIElementRef)valueOfExistingAttribute(kAXMainWindowAttribute, _app);
	
	NSString *documentURL = (NSString *)valueOfExistingAttribute(kAXDocumentAttribute, _window);
	
	if (documentURL != nil)
		frontAppDocumentURLString = [documentURL retain];
	
	[autoReleasePool drain];
}





- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	self.filesToTag = [NSMutableArray array];
	self.titleArgument = nil;
	
	@try
	{
		// get arguments from command line
		
		NSString *filePathsArg = [[NSUserDefaults standardUserDefaults] stringForKey:@"f"];
		if (filePathsArg != nil)
		{
			NSArray *paths = [filePathsArg componentsSeparatedByString:@"\n"];
			NSString *thisPath;
			for (thisPath in paths)
			{
				[self addFileToTag:thisPath];
			}
		}
		
		NSString *titleArg = [[NSUserDefaults standardUserDefaults] stringForKey:@"t"];
		if (titleArg != nil)
			self.titleArgument = titleArg;
	}
	@catch(id exception)
	{
		NSLog(@"ERROR: (in TaggerController -init) exception = %@", exception);
	}
	
	
	// We'll use ~/Library/Metadata/ instead of ~/Library/Caches/Metadata
	// because we want the .webloc files we create to persist and be backed
	// up by Time Machine. Both of these paths are indexed by Spotlight,
	// though: http://support.apple.com/kb/TA23187
	// 
	NSString *userLibraryDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
																	NSUserDomainMask,
																	YES
																	) objectAtIndex:0];
	NSString *userMetadataDir = [userLibraryDir stringByAppendingPathComponent:@"Metadata"];
	NSString *myMetadataDir = [userMetadataDir stringByAppendingPathComponent:[[NSProcessInfo processInfo] processName]];
	self.weblocFilesFolderPath = [myMetadataDir stringByAppendingPathComponent:WEBLOCS_FOLDER_NAME];
	
	DDLogInfo(@"self.weblocFilesFolderPath = %@", self.weblocFilesFolderPath);
	
	BOOL isDir = NO;
	BOOL dirExists = [[NSFileManager defaultManager] fileExistsAtPath:self.weblocFilesFolderPath isDirectory:&isDir];
	if (dirExists && !isDir)
	{
		NSLog(@"ERROR: a file exists in the app data directory's webloc folder location: %@", self.weblocFilesFolderPath);
		[[NSAlert
		 alertWithMessageText:@"Error in Application Support Folder"
		 defaultButton:@"Quit"
		 alternateButton:nil
		 otherButton:nil
		 informativeTextWithFormat:@"A file exists where the application's webloc folder should be: %@ Please delete this file and retry.", self.weblocFilesFolderPath
		 ] runModal];
		[self terminateAppSafely];
	}
	else if (!dirExists)
	{
		NSError *createDirError = nil;
		BOOL success = [[NSFileManager defaultManager]
						createDirectoryAtPath:self.weblocFilesFolderPath
						withIntermediateDirectories:YES
						attributes:nil
						error:&createDirError
						];
		if (!success || createDirError != nil)
		{
			NSLog(@"ERROR: could not create app data directory's webloc folder: %@", self.weblocFilesFolderPath);
			[NSAlert alertWithError:createDirError];
			[self terminateAppSafely];
		}
	}
	
	
	return self;
}

- (void) dealloc
{
	self.filesToTag = nil;
	self.originalTags = nil;
	self.titleArgument = nil;
	self.versionCheckConnection = nil;
	
	if (frontAppBundleID != nil)
		[frontAppBundleID release];
	
	if (frontAppDocumentURLString != nil)
		[frontAppDocumentURLString release];
	
	[super dealloc];
}


- (void) awakeFromNib
{
#ifdef _DEBUG_TARGET
	[mainWindow setTitle:@"Tagger (DEBUG)"];
#endif	
	// if executed from the command line, we don't get focus
	// by default so let's ask for it (ignoring other apps
	// since I think we can safely assume, due to the nature
	// of this app, that if it is launched, the user wants
	// it to get focus right away).
	if (![NSApp isActive])
		[NSApp activateIgnoringOtherApps:YES];
	
	[mainWindow center];
	[aboutWindowVersionLabel setStringValue:[NSString stringWithFormat:@"Version %@", [self getVersionString]]];
	[self checkForUpdates];
}


- (NSString *) getVersionString
{
	return [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
}




- (void) showFileListDialog
{
	[fileListTable setDataSource:self.filesToTag];
	
	[NSApp
	 beginSheet:fileListSheet
	 modalForWindow:mainWindow
	 modalDelegate:self
	 didEndSelector:NULL
	 contextInfo:nil
	 ];
}

- (void) closeFileListDialog
{
	[fileListSheet orderOut:nil];
	[NSApp endSheet:fileListSheet];
}






// add a file path to the list of files to tag
- (void) addFileToTag:(NSString *)aFilePath
{
	if (aFilePath == nil || [aFilePath length] == 0)
		return;
	
	NSString *thisFilePath = [aFilePath stringByStandardizingPath];
	NSString *selfBundlePath = [[[NSBundle bundleForClass:[self class]] bundlePath] stringByStandardizingPath];
	
	// let's not allow tagging of self ;)
	if ([thisFilePath isEqualToString:selfBundlePath])
		return;
	
	BOOL thisPathIsDirectory;
	BOOL thisPathExists = [[NSFileManager defaultManager]
						   fileExistsAtPath:thisFilePath
						   isDirectory:&thisPathIsDirectory
						   ];
	if (thisPathExists)
		[self.filesToTag addObject:thisFilePath];
	else
		NSLog(@"Error: file doesn't exist: '%@'", thisFilePath);
}



- (IBAction) aboutSelected:(id)sender
{
	[aboutWindow center];
	[aboutWindow makeKeyAndOrderFront:self];
}

- (IBAction) preferencesSelected:(id)sender
{
	[preferencesWindow center];
	[preferencesWindow makeKeyAndOrderFront:self];
}

- (IBAction) okSelected:(id)sender
{
	[self setTagsAndQuit];
}

- (IBAction) showFileListSelected:(id)sender
{
	[self showFileListDialog];
}

- (IBAction) closeFileListSelected:(id)sender
{
	[self closeFileListDialog];
}


- (IBAction) goToWebsiteSelected:(id)sender
{
	[[NSWorkspace sharedWorkspace]
	 openURL:[NSURL URLWithString:kAppSiteURL]
	 ];
}




- (void) setTagsAndQuit
{
	[okButton setEnabled:NO];
	
	if ([self.filesToTag count] > 0)
	{
		DDLogInfo(@"[tagsField objectValue] = %@", [tagsField objectValue]);
		
		NSSet *newTagsSet = [NSSet setWithArray:(NSArray *)[tagsField objectValue]];
		
		[tagsField setEnabled:NO];
		
		DDLogInfo(@"committing...");
		DDLogInfo(@"newTagsSet = %@", newTagsSet);
		
		NSSet *originalTagsSet = [NSSet setWithArray:self.originalTags];
		BOOL tagsModified = (![originalTagsSet isEqualToSet:newTagsSet]);
		
		DDLogInfo(@"tagsModified = %@", ((tagsModified)?@"YES":@"NO"));
		
		if (tagsModified)
		{
			NSArray *newTagsArray = [newTagsSet allObjects];
			
			NSError *setTagsErr;
			if ([self.filesToTag count] == 1)
				setTagsErr = [OpenMeta
							  setUserTags:newTagsArray
							  path:[self.filesToTag objectAtIndex:0]
							  ];
			else
				setTagsErr = [OpenMeta
							  setCommonUserTags:self.filesToTag
							  originalCommonTags:self.originalTags
							  replaceWith:newTagsArray
							  ];
			
			if (setTagsErr == nil)
				[OpenMetaPrefs updatePrefsRecentTags:self.originalTags newTags:newTagsArray];
			else
			{
				NSLog(@"error setting tags: %@", [setTagsErr description]);
				[[NSAlert alertWithError:setTagsErr] runModal];
			}
		}
	}
	
	[self terminateAppSafely];
}











// NSTokenField delegate method: token field autocompletion
- (NSArray *) tokenField:(NSTokenField *)tokenField
 completionsForSubstring:(NSString *)substring 
			indexOfToken:(NSInteger)tokenIndex
	 indexOfSelectedItem:(NSInteger *)selectedIndex
{
	if (substring == nil || [substring length] == 0)
		return [OpenMetaPrefs recentTags];
	
	NSMutableArray *tagsForAutoCompletion = [NSMutableArray array];
	
	for (NSString *recentTag in [OpenMetaPrefs recentTags])
	{
		if ([recentTag hasPrefix:substring])
			[tagsForAutoCompletion addObject:recentTag];
	}
	
	return tagsForAutoCompletion;
}



// NSTokenField delegate method: catch keyboard events
- (BOOL) control:(NSControl *)control
		textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
	static NSInteger allModifierKeysMask = (NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
	static BOOL returnPressedLast = NO;
	static NSString *lastTagsFieldValue = nil;
	
	if (![kDefaults boolForKey:kDefaultsKey_SaveChangesOnDoubleReturn])
		return NO;
	
	if (control != tagsField)
		return NO;
	
	NSEvent *currEvent = [NSApp currentEvent];
	
	if (command == @selector(insertNewline:) &&
		[currEvent type] == NSKeyDown &&
		[currEvent keyCode] == 36 &&
		([currEvent modifierFlags] & allModifierKeysMask) == 0
		)
	{
		BOOL fieldContentsChanged = (lastTagsFieldValue == nil)
									? [tagsField stringValue] != nil
									: ![lastTagsFieldValue isEqualToString:[tagsField stringValue]];
		
		if (returnPressedLast && !fieldContentsChanged)
			[self setTagsAndQuit];
		else
		{
			returnPressedLast = YES;
			lastTagsFieldValue = [[tagsField stringValue] copy];
		}
	}
	else
		returnPressedLast = NO;
	
	return NO;
}



- (void) deleteWeblocFilesIfNecessary
{
	// check if any of the tagged files are .webloc files we've
	// created, and delete them if they don't have any tags
	
	if ([self.filesToTag count] == 0)
		return;
	
	for (NSString *filePath in self.filesToTag)
	{
		if (![[filePath stringByStandardizingPath]
			  hasPrefix:[self.weblocFilesFolderPath stringByStandardizingPath]
			  ])
			continue;
		
		NSError *getTagsError = nil;
		NSArray *tags = [OpenMeta getUserTags:filePath error:&getTagsError];
		if (getTagsError != nil || [tags count] > 0)
			continue;
		
		NSError *removeItemError = nil;
		BOOL success = [[NSFileManager defaultManager]
						removeItemAtPath:filePath
						error:&removeItemError
						];
		if (!success)
		{
			NSLog(@"ERROR: Could not delete .webloc file (%@): %@",
				  filePath, [removeItemError localizedDescription]
				  );
		}
	}
}



- (void) terminateAppSafely
{
	[OpenMetaPrefs synchPrefs];
	[OpenMetaBackup appIsTerminating];
	[self deleteWeblocFilesIfNecessary];
	[NSApp terminate:self];
}



- (NSString *) getWeblocFilePathForTitle:(NSString *)title
									 URL:(NSString *)url
{
	// remove the anchor part of the URL (we want to consider only
	// 'full' pages, not parts thereof)
	NSRange hashRange = [url rangeOfString:@"#" options:NSBackwardsSearch];
	if (hashRange.location != NSNotFound)
		url = [url substringToIndex:hashRange.location];
	
	// 'clean up' the page title a bit before using it as a file name.
	// the primary filename & path is what we'd like to call this webloc
	// file and the secondary is a more unique version of the filename
	// that we'll use to avoid collisions (i.e. two web pages at different
	// URLs with the same title)
	// 
	NSString *primaryFilename = [title
								 stringByReplacingOccurrencesOfString:@"/"
								 withString:@"-"];
	// remove all leading dots
	while ([primaryFilename hasPrefix:@"."])
	{
		primaryFilename = [primaryFilename substringFromIndex:1];
	}
	
	BOOL useSecondaryFilename = NO;
	if ([[primaryFilename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0)
	{
		// (this probably won't happen with Safari since if
		// the page title is empty Safari will still give us the
		// filename as the title instead of an empty string.
		// probably the other browsers do something similar.)
		// 
		// page title is all whitespace after sanitizing, so
		// we'll just use some dumbo default filename:
		// 
		primaryFilename = @"Web Page";
		// also force usage of the secondary name (with the
		// url at the end)
		// 
		useSecondaryFilename = YES;
	}
	
	NSString *primaryPath = [self.weblocFilesFolderPath
							 stringByAppendingPathComponent:
							 [primaryFilename stringByAppendingString:@".webloc"]
							 ];
	
	NSString *urlForSecondaryFilename = [url
										 stringByReplacingOccurrencesOfString:@"://"
										 withString:@"::"
										 ];
	urlForSecondaryFilename = [urlForSecondaryFilename
							   stringByReplacingOccurrencesOfString:@"/"
							   withString:@":"
							   ];
	NSString *secondaryFilename = [primaryFilename
								   stringByAppendingString:
								   [NSString stringWithFormat:@" (%@)", urlForSecondaryFilename]
								   ];
	NSString *secondaryPath = [self.weblocFilesFolderPath
							   stringByAppendingPathComponent:
							   [secondaryFilename stringByAppendingString:@".webloc"]
							   ];
	
	NSString *newWeblocPath = primaryPath;
	
	if (useSecondaryFilename)
		newWeblocPath = secondaryPath;
	else if ([[NSFileManager defaultManager] fileExistsAtPath:primaryPath])
	{
		// make sure the URL matches as well:
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:primaryPath];
		if ([[d objectForKey:@"URL"] isEqual:url])
			return primaryPath;
		newWeblocPath = secondaryPath;
	}
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:secondaryPath])
	{
		// make sure the URL matches as well:
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:secondaryPath];
		if ([[d objectForKey:@"URL"] isEqual:url])
			return secondaryPath;
		newWeblocPath = nil;
	}
	
	if (newWeblocPath != nil)
	{
		NSDictionary *weblocContentsDict = [NSDictionary
											dictionaryWithObject:url
											forKey:@"URL"
											];
		[weblocContentsDict writeToFile:newWeblocPath atomically:YES];
		return newWeblocPath;
	}
	
	// both the primary and secondary filenames/paths already exist
	// but point to different URLs, so we don't know what to do.
	return nil;
}





// NSWindow delegate method: terminate app when window closes
- (void) windowWillClose:(NSNotification *)notification
{
	[self terminateAppSafely];
}


// NSApplication delegate method: receive file to open (drag & drop or dbl-click if set as handler for a
// file type.) Gets called once for each file if several "opened" at once
- (BOOL) application:(NSApplication *)anApplication
			openFile:(NSString *)aFileName
{
	[self addFileToTag:aFileName];
	return NO;
}


// NSApplication delegate method: before app initialization
- (void) applicationWillFinishLaunching:(NSNotification *)notification
{
	// If not in /Applications, offer to move it there
	PFMoveToApplicationsFolderIfNecessary();
}


// NSApplication delegate method: after app initialization
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	DDLogInfo(@"applicationDidFinishLaunching");
	DDLogInfo(@"frontAppBundleID = %@", frontAppBundleID);
	
	[progressIndicator startAnimation:self];
	
	if ([self.filesToTag count] == 0 && frontAppBundleID != nil)
	{
		if ([frontAppBundleID isEqualToString:FINDER_BUNDLE_ID] ||
			[frontAppBundleID isEqualToString:PATH_FINDER_BUNDLE_ID])
		{
			// try to get the selected files in Finder or Path Finder via AppleScript
			NSDictionary *appleScriptError = nil;
			NSString *getItemsASSource = nil;
			if ([frontAppBundleID isEqualToString:FINDER_BUNDLE_ID])
				getItemsASSource = GET_SELECTED_FINDER_ITEMS_APPLESCRIPT;
			else if ([frontAppBundleID isEqualToString:PATH_FINDER_BUNDLE_ID])
				getItemsASSource = GET_SELECTED_PATH_FINDER_ITEMS_APPLESCRIPT;
			
			if (getItemsASSource != nil)
			{
				NSAppleScript *getFinderSelectionAS = [[NSAppleScript alloc] initWithSource:getItemsASSource];
				NSAppleEventDescriptor *ret = [getFinderSelectionAS executeAndReturnError:&appleScriptError];
				
				if ([ret stringValue] != nil)
				{
					NSArray *separatedPaths = [[[ret stringValue]
												stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]
												] componentsSeparatedByString:@"\n"
											   ];
					NSString *thisPath;
					for (thisPath in separatedPaths)
					{
						[self addFileToTag:thisPath];
					}
				}
				
				[getFinderSelectionAS release];
			}
		}
		else if ([frontAppBundleID isEqualToString:MAIL_BUNDLE_ID])
		{
			// try to get the selected email files in Mail.app
			NSDictionary *appleScriptError = nil;
			NSString *getEmailFilesASSource = MAIL_GET_SELECTED_EMAILS_APPLESCRIPT;
			
			if (getEmailFilesASSource != nil)
			{
				NSAppleScript *getEmailFilesAS = [[NSAppleScript alloc] initWithSource:getEmailFilesASSource];
				NSAppleEventDescriptor *ret = [getEmailFilesAS executeAndReturnError:&appleScriptError];
				
				if ([ret stringValue] != nil)
				{
					if ([[ret stringValue] isEqualToString:@"error"])
					{
						NSRunAlertPanel(@"Error Tagging Emails from Mail.app",
										@"Could not find all the files for the selected email messages. This could simply mean that not all messages have been fully downloaded by Mail. Please try again after Mail is done downloading the messages.",
										@"OK",
										nil,
										nil);
					}
					else
					{
						NSArray *separatedPaths = [[[ret stringValue]
													stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]
													] componentsSeparatedByString:@"\n"
												   ];
						NSString *thisPath;
						for (thisPath in separatedPaths)
						{
							[self addFileToTag:thisPath];
						}
					}
				}
				
				[getEmailFilesAS release];
			}
			
			if ([self.filesToTag count] > 0)
			{
				// tagging emails; set appropriate title (the email
				// filenames used by Mail.app are not exactly very
				// descriptive.
				
				if ([self.filesToTag count] == 1)
				{
					NSString *emailSubject = nil;
					
					// get selected email subject
					appleScriptError = nil;
					NSAppleScript *getEmailSubjectAS = [[NSAppleScript alloc] initWithSource:MAIL_GET_FIRST_SELECTED_EMAIL_SUBJECT_APPLESCRIPT];
					NSAppleEventDescriptor *ret = [getEmailSubjectAS executeAndReturnError:&appleScriptError];
					if ([ret stringValue] != nil)
						emailSubject = [ret stringValue];
					[getEmailSubjectAS release];
					
					if (emailSubject != nil)
						self.titleArgument = [NSString
											  stringWithFormat:
											  @"Email: %@",
											  emailSubject];
					else
						self.titleArgument = @"1 Email";
				}
				else
				{
					self.titleArgument = [NSString
										  stringWithFormat:
										  @"%i Email%@",
										  [self.filesToTag count],
										  (([self.filesToTag count] > 1)?@"s":@"")];
				}
			}
		}
		else if ([frontAppBundleID isEqualToString:SAFARI_BUNDLE_ID] ||
				 [frontAppBundleID isEqualToString:FIREFOX_BUNDLE_ID] ||
				 [frontAppBundleID isEqualToString:OPERA_BUNDLE_ID] ||
				 [frontAppBundleID isEqualToString:CAMINO_BUNDLE_ID] 
				 )
		{
			// try to get the current page's title and URL from Safari via AppleScript
			NSDictionary *appleScriptError = nil;
			
			NSString *getPageTitleASSource = nil;
			NSString *getPageURLASSource = nil;
			if ([frontAppBundleID isEqualToString:SAFARI_BUNDLE_ID])
			{
				getPageTitleASSource = GET_CURRENT_SAFARI_PAGE_TITLE_APPLESCRIPT;
				getPageURLASSource = GET_CURRENT_SAFARI_PAGE_URL_APPLESCRIPT;
			}
			else if ([frontAppBundleID isEqualToString:FIREFOX_BUNDLE_ID])
			{
				getPageTitleASSource = GET_CURRENT_FIREFOX_PAGE_TITLE_APPLESCRIPT;
				getPageURLASSource = GET_CURRENT_FIREFOX_PAGE_URL_APPLESCRIPT;
			}
			else if ([frontAppBundleID isEqualToString:OPERA_BUNDLE_ID])
			{
				getPageTitleASSource = GET_CURRENT_OPERA_PAGE_TITLE_APPLESCRIPT;
				getPageURLASSource = GET_CURRENT_OPERA_PAGE_URL_APPLESCRIPT;
			}
			else if ([frontAppBundleID isEqualToString:CAMINO_BUNDLE_ID])
			{
				getPageTitleASSource = GET_CURRENT_CAMINO_PAGE_TITLE_APPLESCRIPT;
				getPageURLASSource = GET_CURRENT_CAMINO_PAGE_URL_APPLESCRIPT;
			}
			
			NSAppleScript *getPageTitleAS = [[NSAppleScript alloc] initWithSource:getPageTitleASSource];
			NSAppleEventDescriptor *getPageTitleASOutput = [getPageTitleAS executeAndReturnError:&appleScriptError];
			[getPageTitleAS release];
			
			if ([getPageTitleASOutput stringValue] == nil)
			{
				NSLog(@"ERROR: Could not get page title from browser.");
				if (appleScriptError != nil)
					NSLog(@" AS error: %@", appleScriptError);
				
				NSString *errorMsg = @"Apologies -- there was an error when trying to tag this web page (could not get page title from browser).\n\nPlease send a bug report to the author at the following web page and remember to attach your system log with the message:\n\nhttp://hasseg.org";
				if ([frontAppBundleID isEqualToString:FIREFOX_BUNDLE_ID])
					errorMsg = @"Apologies -- there was an error when trying to tag this web page (could not get page title from browser).\n\nNOTE: Firefox has had bugs related to AppleScript that might be causing this problem -- known workarounds are to make sure that the frontmost window is a regular browser window and if that doesn't help, to restart Firefox and try again. You can send a bug report to the author at the following web page (and remember to attach your system log with the message) but this is probably a bug in Firefox, not Tagger.\n\nhttp://hasseg.org";
				[[NSAlert
				 alertWithMessageText:@"Error tagging web page"
				 defaultButton:@"Quit"
				 alternateButton:nil
				 otherButton:nil
				 informativeTextWithFormat:errorMsg
				 ] runModal];
				[self terminateAppSafely];
			}
			else
			{
				NSAppleScript *getPageURLAS = [[NSAppleScript alloc] initWithSource:getPageURLASSource];
				NSAppleEventDescriptor *getPageURLASOutput = [getPageURLAS executeAndReturnError:&appleScriptError];
				[getPageURLAS release];
				
				if ([getPageURLASOutput stringValue] == nil)
				{
					NSLog(@"ERROR: Could not get page URL from browser.");
					if (appleScriptError != nil)
						NSLog(@" AS error: %@", appleScriptError);
					[[NSAlert
					 alertWithMessageText:@"Error tagging web page"
					 defaultButton:@"Quit"
					 alternateButton:nil
					 otherButton:nil
					 informativeTextWithFormat:
					 @"Apologies -- there was an error when trying to tag this web page (could not get page URL from browser).\n\nPlease send a bug report to the author at the following web page and remember to attach your system log with the message:\n\nhttp://hasseg.org"
					 ] runModal];
					[self terminateAppSafely];
				}
				else if (![[getPageURLASOutput stringValue] hasPrefix:@"topsites://"] &&
						 ![[getPageURLASOutput stringValue] hasPrefix:@"about:"] &&
						 ([[[getPageURLASOutput stringValue]
							stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]
							] length] > 0)
						 )
				{
					DDLogInfo(@"title = %@", [getPageTitleASOutput stringValue]);
					DDLogInfo(@"url = %@", [getPageURLASOutput stringValue]);
					
					NSString *weblocFilePath = [self
												getWeblocFilePathForTitle:[getPageTitleASOutput stringValue]
												URL:[getPageURLASOutput stringValue]
												];
					if (weblocFilePath != nil)
					{
						[self addFileToTag:weblocFilePath];
						
						NSString *weblocFileName = [weblocFilePath lastPathComponent];
						NSRange dotRange = [weblocFileName rangeOfString:@"." options:NSBackwardsSearch];
						if (dotRange.location != NSNotFound)
							self.titleArgument = [weblocFileName substringToIndex:dotRange.location];
						else
							self.titleArgument = weblocFileName;
					}
				}
			}
		}
	}
	
	if ([self.filesToTag count] == 0 && frontAppDocumentURLString != nil)
	{
		NSURL *frontAppDocumentURL = [NSURL URLWithString:frontAppDocumentURLString];
		[self addFileToTag:[frontAppDocumentURL path]];
	}
	
	
	DDLogInfo(@"filesToTag = %@", self.filesToTag);
	
	
	if ([self.filesToTag count] == 0)
	{
		// no files to tag --> reorganize UI for displaying an
		// info message instead.
		
		NSRect infoLabelFrame = [infoLabel frame];
		CGFloat heightOffset = 100;
		NSRect infoLabelNewFrame = NSMakeRect(infoLabelFrame.origin.x,
											  infoLabelFrame.origin.y-heightOffset,
											  infoLabelFrame.size.width,
											  infoLabelFrame.size.height+heightOffset
											  );
		[infoLabel setFrame:infoLabelNewFrame];
		[infoLabel setStringValue:NO_FILES_TO_TAG_MSG];
		[progressIndicator stopAnimation:self];
		[tagsField setEnabled:NO];
		[okButton setEnabled:YES];
		[okButton setTitle:@"Ok"];
		[okButton setToolTip:@"Quit"];
	}
	else
	{
		[okButton setTitle:@"Save"];
		[okButton setToolTip:@"Save tags and quit"];
		
		if ([self.filesToTag count] == 1)
		{
			[infoLabel setStringValue:@"Editing tags for:"];
			if (self.titleArgument != nil)
				[filenameLabel setStringValue:self.titleArgument];
			else
				[filenameLabel setStringValue:[[self.filesToTag objectAtIndex:0] lastPathComponent]];
			
			// launch thread for getting and setting icon
			[NSThread
				detachNewThreadSelector:@selector(setFileIconToView:)
				toTarget:self
				withObject:[self.filesToTag objectAtIndex:0]
			];
			
			// get current tag names for specified file,
			// set tokens into field to represent current tags
			NSError *err = nil;
			self.originalTags = [OpenMeta getUserTags:[self.filesToTag objectAtIndex:0] error:&err];
			
			if (err != nil)
			{
				NSLog(@"error getting originalTags: %@", [err description]);
				[[NSAlert alertWithError:err] runModal];
			}
		}
		else
		{
			[infoLabel setStringValue:[NSString stringWithFormat:@"Editing common tags for %d files:", [self.filesToTag count]]];
			
			if (self.titleArgument != nil)
				[filenameLabel setStringValue:self.titleArgument];
			else
			{
				// get comma-separated list of all filenames of files to be tagged
				NSMutableArray *filesToTagFilenames = [NSMutableArray arrayWithCapacity:[self.filesToTag count]];
				NSString *thisFilePath;
				for (thisFilePath in self.filesToTag)
				{
					[filesToTagFilenames addObject:[thisFilePath lastPathComponent]];
				}
				[filenameLabel setStringValue:[filesToTagFilenames componentsJoinedByString:@", "]];
			}
			
			[fileCountLabel setStringValue:[NSString stringWithFormat:@"%d", [self.filesToTag count]]];
			[fileCountLabel setHidden:NO];
			
			[iconImageView setImage:[NSImage imageNamed:@"manyFiles.png"]];
			[progressIndicator stopAnimation:self];
			
			// get common tag names for specified files,
			// set tokens into field to represent current common tags
			NSError *err = nil;
			self.originalTags = [OpenMeta getCommonUserTags:self.filesToTag error:&err];
			
			if (err != nil)
			{
				NSLog(@"error getting originalTags for multiple files: %@", [err description]);
				[[NSAlert alertWithError:err] runModal];
			}
		}
		
		if (self.originalTags == nil)
			self.originalTags = [NSArray array];
		[tagsField setObjectValue:self.originalTags];
		DDLogInfo(@"originalTags = %@", self.originalTags);
		
		// enable UI controls
		[okButton setEnabled:YES];
		[tagsField setHidden:NO];
		
		[mainWindow makeFirstResponder:tagsField];
		
		// set caret (insertion point) to the end of the token field
		[[tagsField currentEditor]
		 setSelectedRange:NSMakeRange([[[tagsField currentEditor] string] length], 0)
		];
	}
}



// method for setting the preview image (or icon) of a file to an imageview
// -- to be run in a thread of its own
- (void) setFileIconToView:(NSString *)pathToFile
{
	NSAutoreleasePool *setIconThreadAutoReleasePool = [[NSAutoreleasePool alloc] init];
	
	BOOL isDir = NO;
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:pathToFile isDirectory:&isDir];
	
	if (exists)
	{
		BOOL isPackage = [[NSWorkspace sharedWorkspace] isFilePackageAtPath:pathToFile];
		BOOL useIconDecor = (!isDir || isPackage);
		
		[iconImageView
		 setImage:[NSImage
				   imageWithPreviewOfFileAtPath:pathToFile
				   ofSize:NSMakeSize(180,180)
				   asIcon:useIconDecor
				   ]
		 ];
	}
	
	[progressIndicator stopAnimation:self];
	[setIconThreadAutoReleasePool drain];
}










#pragma mark version check & update code

- (void) checkForUpdates
{
	NSURL *url = kVersionCheckURL;
	
	NSURLRequest *request = [NSURLRequest
							 requestWithURL:url
							 cachePolicy:NSURLRequestReloadIgnoringCacheData
							 timeoutInterval:10.0
							 ];
	
	if (!self.versionCheckConnection)
		self.versionCheckConnection = [NSURLConnection
									   connectionWithRequest:request
									   delegate:self
									   ];
}


- (void) connection:(NSURLConnection *)connection
   didFailWithError:(NSError *)error
{
	self.versionCheckConnection = nil;
	
	NSLog(@"Version check connection failed. Error: - %@ %@",
		  [error localizedDescription],
		  [[error userInfo] objectForKey:NSErrorFailingURLStringKey]
		  );
}



- (void) connection:(NSURLConnection *)connection
 didReceiveResponse:(NSHTTPURLResponse *)response
{
	NSInteger statusCode = [response statusCode];
	if (statusCode >= 400)
	{
		[connection cancel];
		[self
		 connection:connection
		 didFailWithError:[NSError
						   errorWithDomain:@"HTTP Status"
						   code:500
						   userInfo:[NSDictionary
									 dictionaryWithObjectsAndKeys:
										NSLocalizedDescriptionKey,
										[NSHTTPURLResponse localizedStringForStatusCode:500],
										nil
									 ]
						   ]
		];
	}
	else
	{
		NSString *latestVersionString = [[response allHeaderFields] valueForKey:@"Orghassegsoftwarelatestversion"];
		NSString *currentVersionString = [self getVersionString];
		
		if (versionNumberCompare(currentVersionString, latestVersionString) == NSOrderedAscending)
		{
			DDLogInfo(@"update found! (latest: %@ current: %@)", latestVersionString, currentVersionString);
			[updateButton setEnabled: YES];
			[updateButton setHidden: NO];
			[updateButton
			 setToolTip:[NSString
						 stringWithFormat:
							@"Version %@ of Tagger is available! (you have v.%@)",
							latestVersionString,
							currentVersionString
						 ]
			];
		}
		else
			DDLogInfo(@"NO update found. (latest: %@ current: %@)", latestVersionString, currentVersionString);
	}
}





- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
	self.versionCheckConnection = nil;
}




- (IBAction) updateSelected:(id)sender
{
	[[NSWorkspace sharedWorkspace]
	 openURL:[NSURL
			  URLWithString:[NSString
							 stringWithFormat:
								@"%@?currentversion=%@",
								kAppSiteURLPrefix,
								[self getVersionString]
							 ]
			  ]
	];
}










@end
