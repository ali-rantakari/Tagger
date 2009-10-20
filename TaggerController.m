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
// - Fix the HUD Token Field caret problem: http://code.google.com/p/bghudappkit/issues/detail?id=27
// 
// - Make the token field colors more pleasant
// 
// - OpenMeta allows commas in tag names -- how to handle?
// 
// - add Help somewhere
// 


// BUGS TO FIX:
// 


#import "TaggerController.h"
#import "NSArray+NSTableViewDataSource.h"
#import "PFMoveApplication.h"


#define kAppSiteURL			@"http://hasseg.org/tagger/"
#define kAppSiteURLPrefix	kAppSiteURL
#define kVersionCheckURL [NSURL URLWithString:[NSString stringWithFormat:@"%@?versioncheck=y", kAppSiteURLPrefix]]

#define FINDER_BUNDLE_ID						@"com.apple.finder"
#define PATH_FINDER_BUNDLE_ID					@"com.cocoatech.PathFinder"
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

// helper method: compare three-part version number strings (e.g. "1.0.3")
- (NSComparisonResult) versionNumberCompareWithFirst:(NSString *)first second:(NSString *)second
{
	if (first != nil && second != nil)
	{
		int i;
		
		NSMutableArray *firstComponents = [NSMutableArray arrayWithCapacity:3];
		[firstComponents addObjectsFromArray:[first componentsSeparatedByString:@"."]];
		
		NSMutableArray *secondComponents = [NSMutableArray arrayWithCapacity:3];
		[secondComponents addObjectsFromArray:[second componentsSeparatedByString:@"."]];
		
		if ([firstComponents count] != [secondComponents count])
		{
			NSMutableArray *shorter;
			NSMutableArray *longer;
			if ([firstComponents count] > [secondComponents count])
			{
				shorter = secondComponents;
				longer = firstComponents;
			}
			else
			{
				shorter = firstComponents;
				longer = secondComponents;
			}
			
			NSUInteger countDiff = [longer count] - [shorter count];
			
			for (i = 0; i < countDiff; i++)
				[shorter addObject:@"0"];
		}
		
		for (i = 0; i < [firstComponents count]; i++)
		{
			int firstComponentIntVal = [[firstComponents objectAtIndex:i] intValue];
			int secondComponentIntVal = [[secondComponents objectAtIndex:i] intValue];
			if (firstComponentIntVal < secondComponentIntVal)
				return NSOrderedAscending;
			else if (firstComponentIntVal > secondComponentIntVal)
				return NSOrderedDescending;
		}
		return NSOrderedSame;
	}
	else
		return NSOrderedSame;
}



- (void) showOpenMetaSpotlightImporterInstallDialog
{
	[NSApp
	 beginSheet:installSpotlightSupportSheet
	 modalForWindow:mainWindow
	 modalDelegate:self
	 didEndSelector:NULL
	 contextInfo:nil
	];
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

- (IBAction) installSpotlightSupportSelected:(id)sender
{
	[self showOpenMetaSpotlightImporterInstallDialog];
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
		
		NSSet *tagsToAddSet = [NSSet setWithArray:(NSArray *)[tagsField objectValue]];
		
		[tagsField setEnabled:NO];
		
		DDLogInfo(@"committing...");
		DDLogInfo(@"tagsToAddSet = %@", tagsToAddSet);
		
		NSSet *originalTagsSet = [NSSet setWithArray:self.originalTags];
		BOOL tagsModified = (![originalTagsSet isEqualToSet:tagsToAddSet]);
		
		DDLogInfo(@"tagsModified = %@", ((tagsModified)?@"YES":@"NO"));
		
		if (tagsModified)
		{
			NSArray *tagsToAdd = [tagsToAddSet allObjects];
			
			NSError *setTagsErr;
			if ([self.filesToTag count] == 1)
				setTagsErr = [OpenMeta
							  setUserTags:tagsToAdd
							  path:[self.filesToTag objectAtIndex:0]
							  ];
			else
				setTagsErr = [OpenMeta
							  setCommonUserTags:self.filesToTag
							  originalCommonTags:self.originalTags
							  replaceWith:tagsToAdd
							  ];
			
			if (setTagsErr == nil)
				[OpenMetaPrefs updatePrefsRecentTags:self.originalTags newTags:tagsToAdd];
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




- (void) terminateAppSafely
{
	[OpenMetaPrefs synchPrefs];
	[OpenMetaBackup appIsTerminating];
	[NSApp terminate:self];
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
	
	// check if the Spotlight importer has been installed (we do this only
	// once for each user)
	if (![kDefaults boolForKey:kDefaultsKey_OMSpotlightImporterInstallCheckDone])
	{
		BOOL installed = [TaggerOMImporterInstallController isOpenMetaSpotlightImporterInstalled:NULL];
		if (!installed)
			[self showOpenMetaSpotlightImporterInstallDialog];
		
		[kDefaults setBool:YES forKey:kDefaultsKey_OMSpotlightImporterInstallCheckDone];
	}
	
	[progressIndicator startAnimation:self];
	
	if ([self.filesToTag count] == 0 && frontAppBundleID != nil)
	{
		// try to get the selected files in Finder or Path Finder via AppleScript
		NSDictionary *appleScriptError;
		NSString *asSource = nil;
		if ([frontAppBundleID isEqualToString:FINDER_BUNDLE_ID])
			asSource = GET_SELECTED_FINDER_ITEMS_APPLESCRIPT;
		else if ([frontAppBundleID isEqualToString:PATH_FINDER_BUNDLE_ID])
			asSource = GET_SELECTED_PATH_FINDER_ITEMS_APPLESCRIPT;
		
		if (asSource != nil)
		{
			NSAppleScript *getFinderSelectionAS = [[NSAppleScript alloc]
												   initWithSource:asSource
												   ];
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
		
		if ([self versionNumberCompareWithFirst:currentVersionString second:latestVersionString] == NSOrderedAscending)
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
