//
//  TaggerController.m
//  Tagger
//
// Copyright (C) 2008-2010 Ali Rantakari
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
// - Add SFBCrashReporter (first make it so that it only zips up the
//   crash logs if there are more than one)
// 
// - Rewrite the built-in applescripts in the same format as the
//   front app scripts and use the same code to interpret them
// 
// - Recently used tags as clickable elements (user ref: Michael H.)
// 
// - Fix the HUD Token Field caret problem: http://code.google.com/p/bghudappkit/issues/detail?id=27
// 
// - Make the token field colors more pleasant
// 
// - OpenMeta allows commas in tag names -- how to handle?
// 
// - Allow storing .webloc files under dated paths? (e.g. /YYYY-MM-DD/.) (user ref: Christian F)


// BUGS TO FIX:
// 


#import "TaggerController.h"
#import "NSArray+NSTableViewDataSource.h"
#import "PFMoveApplication.h"
#import "HGVersionNumberCompare.h"
#import "ScriptWindowController.h"
#import "TaggerAppleScripts.h"

#import <Sparkle/Sparkle.h>
#import <Sparkle/HGNoStatusUIUpdateDriverDelegate.h>


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
@synthesize customTitle;
@synthesize weblocFilesFolderPath;
@synthesize appDataDirPath;
@synthesize scriptsDirPath;
@synthesize scriptsCatalog;
@synthesize installUpdateInvocation;


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
	self.customTitle = nil;
	
	allowManualUpdateCheck = YES;
	
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
			self.customTitle = titleArg;
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
	
	BOOL weblocDirIsDir = NO;
	BOOL weblocDirExists = [[NSFileManager defaultManager]
							fileExistsAtPath:self.weblocFilesFolderPath
							isDirectory:&weblocDirIsDir];
	if (weblocDirExists && !weblocDirIsDir)
	{
		NSLog(@"ERROR: a file exists where the webloc storage folder should be: %@", self.weblocFilesFolderPath);
		[[NSAlert
		 alertWithMessageText:@"Error in Web Location Storage Folder"
		 defaultButton:@"Quit"
		 alternateButton:nil
		 otherButton:nil
		 informativeTextWithFormat:@"A file exists where the application's web internet location file storage folder should be: %@ Please move this file to the trash and retry.", self.weblocFilesFolderPath
		 ] runModal];
		[self terminateAppSafely];
	}
	else if (!weblocDirExists)
	{
		NSError *createWeblocDirError = nil;
		BOOL success = [[NSFileManager defaultManager]
						createDirectoryAtPath:self.weblocFilesFolderPath
						withIntermediateDirectories:YES
						attributes:nil
						error:&createWeblocDirError
						];
		if (!success || createWeblocDirError != nil)
		{
			NSLog(@"ERROR: could not create webloc folder: %@", self.weblocFilesFolderPath);
			[NSAlert alertWithError:createWeblocDirError];
			[self terminateAppSafely];
		}
	}
	
	
	// determine the scripts folder path & create it if
	// necessary
	// 
	self.appDataDirPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																NSUserDomainMask,
																YES
																) objectAtIndex:0] 
						   stringByAppendingPathComponent:[[NSProcessInfo processInfo]
														   processName]
						   ];
	self.scriptsDirPath = [self.appDataDirPath stringByAppendingPathComponent:@"Scripts"];
	
	BOOL scriptsDirIsDir = NO;
	BOOL scriptsDirExists = [[NSFileManager defaultManager]
							 fileExistsAtPath:self.scriptsDirPath
							 isDirectory:&scriptsDirIsDir];
	if (scriptsDirExists && !scriptsDirIsDir)
	{
		NSLog(@"ERROR: a file exists in the app data directory's scripts folder location: %@", self.scriptsDirPath);
		[[NSAlert
		  alertWithMessageText:@"Error in Application Support Scripts Folder"
		  defaultButton:@"Quit"
		  alternateButton:nil
		  otherButton:nil
		  informativeTextWithFormat:@"A file exists where the application's scripts folder should be: %@ Please move this file to the trash and retry.", self.scriptsDirPath
		  ] runModal];
		[self terminateAppSafely];
	}
	else if (!scriptsDirExists)
	{
		NSError *createScriptsDirError = nil;
		BOOL success = [[NSFileManager defaultManager]
						createDirectoryAtPath:self.scriptsDirPath
						withIntermediateDirectories:YES
						attributes:nil
						error:&createScriptsDirError
						];
		if (!success || createScriptsDirError != nil)
		{
			NSLog(@"ERROR: could not create app data directory's scripts folder: %@", self.scriptsDirPath);
			[NSAlert alertWithError:createScriptsDirError];
			[self terminateAppSafely];
		}
	}
	
	
	// read scripts catalog file
	NSString *catalogFilePath = [self.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	// we get nil if file doesn't exist:
	self.scriptsCatalog = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	
	
	
	
	
	[kDefaults
	 registerDefaults:
	 [NSDictionary
	  dictionaryWithObjectsAndKeys:
	  [NSNumber numberWithBool:YES], kDefaultsKey_ShowFrontAppIcon,
	  [NSNumber numberWithBool:NO], kDefaultsKey_SaveChangesOnDoubleReturn,
	  [NSNumber numberWithBool:NO], kDefaultsKey_AutomaticallyCheckForUpdates,
	  [NSNumber numberWithBool:NO], kDefaultsKey_HaveAskedAboutAutoUpdates,
	  nil]];
	
	
	return self;
}

- (void) dealloc
{
	self.filesToTag = nil;
	self.originalTags = nil;
	self.customTitle = nil;
	self.weblocFilesFolderPath = nil;
	self.appDataDirPath = nil;
	self.scriptsDirPath = nil;
	self.scriptsCatalog = nil;
	self.installUpdateInvocation = nil;
	
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
	
	// register window for drag & drop operations
	[mainWindow registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
}





#pragma mark -
#pragma mark Helper, Utility etc. methods


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



- (void) ensureScriptsCatalogFileExists
{
	// create the catalog file if it doesn't exist
	NSString *catalogFilePath = [self.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	
	BOOL catalogFileIsDir = NO;
	BOOL catalogFileExists = [[NSFileManager defaultManager]
							  fileExistsAtPath:catalogFilePath
							  isDirectory:&catalogFileIsDir];
	if (catalogFileExists && catalogFileIsDir)
	{
		NSLog(@"ERROR: a folder exists in the app data directory's scripts catalog file location: %@", catalogFilePath);
		[[NSAlert
		  alertWithMessageText:@"Error Creating Front App Scripts Catalog File"
		  defaultButton:@"OK"
		  alternateButton:nil
		  otherButton:nil
		  informativeTextWithFormat:@"A folder exists where the application's scripts catalog file should be: %@ Please move this folder to the trash and retry.", catalogFilePath
		  ] runModal];
	}
	else if (!catalogFileExists)
	{
		NSDictionary *emptyDict = [NSDictionary dictionary];
		BOOL success = [emptyDict writeToFile:catalogFilePath atomically:YES];
		
		if (!success)
		{
			NSLog(@"ERROR: could not create app data directory's scripts folder catalog file: %@", catalogFilePath);
			[[NSAlert
			  alertWithMessageText:@"Error Creating Front App Scripts Catalog File"
			  defaultButton:@"OK"
			  alternateButton:nil
			  otherButton:nil
			  informativeTextWithFormat:@"Could not write catalog file: %@", catalogFilePath
			  ] runModal];
		}
	}
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




#pragma mark -
#pragma mark Dealing with .webloc files

// ensures that the file exists
- (NSString *) getWeblocCatalogFilePath
{
	NSString *catalogFilePath = [self.appDataDirPath stringByAppendingPathComponent:WEBLOC_FILES_CATALOG_FILENAME];
	if (![[NSFileManager defaultManager] fileExistsAtPath:catalogFilePath])
		[[NSDictionary dictionary] writeToFile:catalogFilePath atomically:NO];
	return catalogFilePath;
}

- (BOOL) saveWeblocFilenameToCatalog:(NSString *)filename
							  forURL:(NSString *)url
{
	NSString *catalogFilePath = [self getWeblocCatalogFilePath];
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	[dict setObject:filename forKey:url];
	return [dict writeToFile:catalogFilePath atomically:YES];
}

- (BOOL) removeURLFromWeblocCatalog:(NSString *)url
{
	NSString *catalogFilePath = [self getWeblocCatalogFilePath];
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	[dict removeObjectForKey:url];
	return [dict writeToFile:catalogFilePath atomically:YES];
}

- (NSString *) getWeblocFilenameFromCatalogForURL:(NSString *)url
{
	NSString *catalogFilePath = [self getWeblocCatalogFilePath];
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	NSString *filename = [dict objectForKey:url];
	if (filename == nil)
		return nil;
	
	// make sure the file exists
	NSString *filePath = [self.weblocFilesFolderPath
						  stringByAppendingPathComponent:filename];
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
		// we have an entry for this URL but the we can't find
		// the file it points to. in desperation, go through
		// the .webloc files folder and try to find a .webloc file
		// that points to the same URL (this would happen if the
		// user had manually renamed the file)
		// 
		NSString *renamedFilename = nil;
		NSArray *weblocFolderContents = [[NSFileManager defaultManager]
										 contentsOfDirectoryAtPath:self.weblocFilesFolderPath
										 error:NULL];
		if (weblocFolderContents != nil)
		{
			for (NSString *aFileName in weblocFolderContents)
			{
				NSString *aFilePath = [self.weblocFilesFolderPath stringByAppendingPathComponent:aFileName];
				
				if (![[[aFilePath pathExtension] lowercaseString] isEqualToString:@"webloc"])
					continue;
				
				NSDictionary *weblocDict = [NSDictionary dictionaryWithContentsOfFile:aFilePath];
				NSString *weblocTargetURL = [weblocDict objectForKey:@"URL"];
				
				if([url isEqualToString:weblocTargetURL])
				{
					renamedFilename = aFileName;
					break;
				}
			}
		}
		
		if (renamedFilename != nil)
		{
			// update catalog entry
			[dict setObject:renamedFilename forKey:url];
			[dict writeToFile:catalogFilePath atomically:YES];
			return renamedFilename;
		}
		
		// remove entry from catalog
		[dict removeObjectForKey:url];
		[dict writeToFile:catalogFilePath atomically:YES];
		return nil;
	}
	
	return filename;
}


- (NSString *) getWeblocFilePathForTitle:(NSString *)title
									 URL:(NSString *)aUrl
{
	NSURL *url = [NSURL URLWithString:aUrl];
	NSString *urlStr = [url absoluteString];
	
	if ([url scheme] == nil)
		urlStr = [@"http://" stringByAppendingString:urlStr];
	
	// remove the anchor part of the URL (we want to consider only
	// 'full' pages, not parts thereof)
	NSRange hashRange = [urlStr rangeOfString:@"#" options:NSBackwardsSearch];
	if (hashRange.location != NSNotFound)
		urlStr = [urlStr substringToIndex:hashRange.location];
	
	// check if we already have a catalog entry for this URL
	NSString *filenameFromCatalog = [self getWeblocFilenameFromCatalogForURL:urlStr];
	if (filenameFromCatalog != nil)
		return [self.weblocFilesFolderPath
				stringByAppendingPathComponent:filenameFromCatalog];
	
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
	
	// 'primary' filename =   "Page Title.webloc"
	// 'secondary' filename = "Page Title (http::host:path).webloc"
	// 
	// we try to use the primary version but in case of
	// filename collisions we use the secondary one.
	// 
	NSString *primaryPath = [self.weblocFilesFolderPath
							 stringByAppendingPathComponent:
							 [primaryFilename stringByAppendingString:@".webloc"]
							 ];
	
	NSString *urlForSecondaryFilename = [urlStr
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
		if ([[d objectForKey:@"URL"] isEqual:urlStr])
		{
			[self saveWeblocFilenameToCatalog:[primaryPath lastPathComponent] forURL:urlStr];
			return primaryPath;
		}
		newWeblocPath = secondaryPath;
	}
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:secondaryPath])
	{
		// make sure the URL matches as well:
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:secondaryPath];
		if ([[d objectForKey:@"URL"] isEqual:urlStr])
		{
			[self saveWeblocFilenameToCatalog:[secondaryPath lastPathComponent] forURL:urlStr];
			return secondaryPath;
		}
		newWeblocPath = nil;
	}
	
	if (newWeblocPath != nil)
	{
		NSDictionary *weblocContentsDict = [NSDictionary
											dictionaryWithObject:urlStr
											forKey:@"URL"
											];
		[weblocContentsDict writeToFile:newWeblocPath atomically:YES];
		[self saveWeblocFilenameToCatalog:[newWeblocPath lastPathComponent] forURL:urlStr];
		return newWeblocPath;
	}
	
	// both the primary and secondary filenames/paths already exist
	// but point to different URLs, so we don't know what to do.
	// this shouldn't happen.
	// 
	// todo: add an incrementing number to the end of the filename to deal with this
	// 
	return nil;
}



- (void) deleteWeblocFilesIfNecessary
{
	DDLogInfo(@"deleteWeblocFilesIfNecessary called.");
	
	// check if any of the tagged files are .webloc files we've
	// created, and delete them if they don't have any tags
	
	if ([self.filesToTag count] == 0)
		return;
	
	for (NSString *filePath in self.filesToTag)
	{
		DDLogInfo(@"webloc delete check: %@", filePath);
		
		// don't delete files that don't have the extension ".webloc"
		if (![[[filePath pathExtension] lowercaseString] isEqualToString:@"webloc"])
			continue;
		DDLogInfo(@"has webloc ext...");
		
		// don't delete files that aren't in our webloc files folder
		if (![[filePath stringByStandardizingPath]
			  hasPrefix:[self.weblocFilesFolderPath stringByStandardizingPath]
			  ])
			continue;
		DDLogInfo(@"is in webloc folder...");
		
		// don't delete files that have tags (or if we for some
		// reason can't read its tags)
		NSError *getTagsError = nil;
		NSArray *tags = [OpenMeta getUserTags:filePath error:&getTagsError];
		DDLogInfo(@"getTagsError = %@", getTagsError);
		DDLogInfo(@"tags = %@", tags);
		if (getTagsError != nil || (tags != nil && [tags count] > 0))
			continue;
		DDLogInfo(@"has no tags -> can delete.");
		
		// ok so now we've determined that we can delete
		// this file
		
		NSDictionary *weblocDict = [NSDictionary dictionaryWithContentsOfFile:filePath];
		NSString *weblocTargetURL = [weblocDict objectForKey:@"URL"];
		
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
		else if (weblocTargetURL != nil)
			[self removeURLFromWeblocCatalog:weblocTargetURL];
	}
}







#pragma mark -
#pragma mark Misc. UI Handlers etc.

- (BOOL) respondsToSelector:(SEL)aSelector
{
	if (aSelector == @selector(checkForUpdates:))
		return allowManualUpdateCheck;
	return [super respondsToSelector:aSelector];
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

- (IBAction) readAboutFrontAppScriptsSelected:(id)sender
{
	[[NSWorkspace sharedWorkspace]
	 openURL:[NSURL URLWithString:kFrontAppScriptsInfoURL]
	 ];
}

- (IBAction) revealScriptsFolderSelected:(id)sender
{
	[[NSWorkspace sharedWorkspace]
	 selectFile:nil
	 inFileViewerRootedAtPath:self.scriptsDirPath
	 ];
}

- (IBAction) showScriptsWindowSelected:(id)sender
{
	[scriptsWindow center];
	[scriptsWindow makeKeyAndOrderFront:self];
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










#pragma mark -
#pragma mark Starting up, getting the file(s) to tag

- (void) getFilesFromFrontAppUsingBuiltinMethods
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
			// descriptive).
			
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
					self.customTitle = [NSString
										stringWithFormat:
										@"Email: %@",
										emailSubject];
				else
					self.customTitle = @"1 Email";
			}
			else
			{
				self.customTitle = [NSString
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
			 [frontAppBundleID isEqualToString:CAMINO_BUNDLE_ID] ||
			 [frontAppBundleID isEqualToString:CHROME_BUNDLE_ID] ||
			 [frontAppBundleID isEqualToString:CHROMIUM_BUNDLE_ID] ||
			 [frontAppBundleID isEqualToString:OMNIWEB_BUNDLE_ID]
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
		else if ([frontAppBundleID isEqualToString:OMNIWEB_BUNDLE_ID])
		{
			getPageTitleASSource = GET_CURRENT_OMNIWEB_PAGE_TITLE_APPLESCRIPT;
			getPageURLASSource = GET_CURRENT_OMNIWEB_PAGE_URL_APPLESCRIPT;
		}
		else if ([frontAppBundleID isEqualToString:CHROME_BUNDLE_ID])
		{
			getPageTitleASSource = GET_CURRENT_CHROME_PAGE_TITLE_APPLESCRIPT;
			getPageURLASSource = GET_CURRENT_CHROME_PAGE_URL_APPLESCRIPT;
		}
		else if ([frontAppBundleID isEqualToString:CHROMIUM_BUNDLE_ID])
		{
			getPageTitleASSource = GET_CURRENT_CHROMIUM_PAGE_TITLE_APPLESCRIPT;
			getPageURLASSource = GET_CURRENT_CHROMIUM_PAGE_URL_APPLESCRIPT;
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
						self.customTitle = [weblocFileName substringToIndex:dotRange.location];
					else
						self.customTitle = weblocFileName;
				}
			}
		}
	}
	else if ([frontAppBundleID isEqualToString:TAGLISTS_BUNDLE_ID])
	{
		// try to get the selected files in TagLists
		NSDictionary *appleScriptError = nil;
		NSString *getTagListsSelectionASSource = TAGLISTS_GET_SELECTED_FILES_APPLESCRIPT;
		
		if (getTagListsSelectionASSource != nil)
		{
			NSAppleScript *getTagListsSelectionAS = [[NSAppleScript alloc] initWithSource:getTagListsSelectionASSource];
			NSAppleEventDescriptor *ret = [getTagListsSelectionAS executeAndReturnError:&appleScriptError];
			
			if (appleScriptError != nil)
			{
				NSString *errorMsg = [appleScriptError objectForKey:NSAppleScriptErrorMessage];
				
				NSRunAlertPanel(@"Error getting files to tag from TagLists",
								errorMsg,
								@"Quit", nil, nil);
				[self terminateAppSafely];
			}
			
			NSUInteger recordCount = [ret numberOfItems];
			if (recordCount > 0)
			{
				NSUInteger i;
				for (i = 1; i <= recordCount; i++)
				{
					[self addFileToTag:[[ret descriptorAtIndex:i] stringValue]];
				}
			}
			
			[getTagListsSelectionAS release];
		}
	}
}




- (void) getFilesFromFrontAppUsingUserScripts
{
	NSString *scriptForFrontAppFilename = [self.scriptsCatalog objectForKey:frontAppBundleID];
	if (scriptForFrontAppFilename == nil ||
		[scriptForFrontAppFilename length] == 0
		)
		return;
	
	NSString *scriptForFrontAppPath = [self.scriptsDirPath stringByAppendingPathComponent:scriptForFrontAppFilename];
	
	BOOL isDir = NO;
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:scriptForFrontAppPath isDirectory:&isDir];
	if (!exists)
	{
		// the front app ID has an entry in the catalog but the
		// specified file doesn't exist -> remove entry from
		// the catalog
		NSString *catalogFilePath = [self.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
		[self.scriptsCatalog removeObjectForKey:frontAppBundleID];
		[self.scriptsCatalog writeToFile:catalogFilePath atomically:YES];
		return;
	}
	
	if (isDir)
		return;
	
	NSDictionary *asInitErrorInfo = nil;
	NSAppleScript *userScriptAS = [[NSAppleScript alloc]
								   initWithContentsOfURL:[NSURL fileURLWithPath:scriptForFrontAppPath]
								   error:&asInitErrorInfo];
	if (asInitErrorInfo != nil)
	{
		NSLog(@"Error loading script \"%@\": %@", scriptForFrontAppPath, asInitErrorInfo);
		NSRunAlertPanel(@"Error Loading User Script",
						[NSString stringWithFormat:
						 @"There was an error loading the user script: %@ -- See the system log for more info.",
						 scriptForFrontAppFilename],
						@"Quit",
						nil,
						nil);
		[self terminateAppSafely];
	}
	
	DDLogInfo(@"Executing: %@", scriptForFrontAppPath);
	NSDictionary *asExecuteErrorInfo = nil;
	NSAppleEventDescriptor *asOutput = [userScriptAS executeAndReturnError:&asExecuteErrorInfo];
	
	if (asExecuteErrorInfo != nil)
	{
		NSString *errorTitle = nil;
		NSString *errorMsg = [asExecuteErrorInfo objectForKey:NSAppleScriptErrorMessage];
		
		if (errorMsg == nil || [errorMsg length] == 0)
		{
			errorMsg = [NSString
						stringWithFormat:
						@"There was an error running the user script: %@ -- See the system log for more info.",
						scriptForFrontAppFilename];
			errorTitle = [NSString
						  stringWithFormat:
						  @"Error Running Script %@:",
						  scriptForFrontAppFilename];
			NSLog(@"Error while running script \"%@\": %@", scriptForFrontAppPath, asExecuteErrorInfo);
		}
		else
		{
			errorTitle = [NSString
						  stringWithFormat:
						  @"Error Message from Script %@:",
						  scriptForFrontAppFilename];
		}
		
		NSRunAlertPanel(errorTitle,
						errorMsg,
						@"Quit",
						nil,
						nil);
		[self terminateAppSafely];
	}
	
	if (asOutput == nil)
		return;
	
	asOutput = [asOutput descriptorForKeyword:keyASUserRecordFields];
	
	NSUInteger recordCount = [asOutput numberOfItems];
	
	// We store the title of the given weblink (or something like "%d Web links"
	// if there are more than one) here so that we can use this instead as
	// the custom GUI title if no top-level 'title' property is given in
	// the user script
	NSString *weblinkCustomTitle = nil;
	
	// NSAppleEventDescriptor uses 1-based indexes and the keys and
	// values are stored side by side in the same 'list': key 1, value 1,
	// key 2, value 2...
	NSUInteger i;
    for (i = 1; i <= recordCount; i+=2)
	{
		NSString *key = [[[asOutput descriptorAtIndex:i] stringValue] lowercaseString];
		DDLogInfo(@"  key = %@", key);
		
		// {filepaths:{"path1", "path2"}}
		if ([key isEqualToString:@"filepaths"])
		{
			NSAppleEventDescriptor *fileListDescriptor = [asOutput descriptorAtIndex:i+1];
			NSUInteger fileListCount = [fileListDescriptor numberOfItems];
			NSUInteger j;
			for (j = 1; j <= fileListCount; j++)
			{
				[self addFileToTag:[[fileListDescriptor descriptorAtIndex:j] stringValue]];
			}
		}
		// {weblinks:{ {link:"http://url", title:"page"}, {link:"http://another-url", title:"another page"} }}
		else if ([key isEqualToString:@"weblinks"])
		{
			DDLogInfo(@"  key is weblinks");
			NSAppleEventDescriptor *webLinkListDescriptor = [asOutput descriptorAtIndex:i+1];
			NSUInteger webLinkListCount = [webLinkListDescriptor numberOfItems];
			if (webLinkListCount > 1)
				weblinkCustomTitle = [NSString stringWithFormat:@"%d Web links", webLinkListCount];
			NSUInteger k;
			for (k = 1; k <= webLinkListCount; k++)
			{
				NSString *URLStr = nil;
				NSString *titleStr = nil;
				
				NSAppleEventDescriptor *linkPropsDescriptor = [[webLinkListDescriptor descriptorAtIndex:k]
																   descriptorForKeyword:keyASUserRecordFields];
				NSUInteger linkPropsCount = [linkPropsDescriptor numberOfItems];
				DDLogInfo(@"    webLinkListDescriptor = %@", webLinkListDescriptor);
				DDLogInfo(@"    weblinks item #%i (count %i)", k, linkPropsCount);
				NSUInteger m;
				for (m = 1; m <= linkPropsCount; m+=2)
				{
					NSString *linkPropsKey = [[[linkPropsDescriptor descriptorAtIndex:m] stringValue] lowercaseString];
					DDLogInfo(@"    linkPropsKey = %@", linkPropsKey);
					if ([linkPropsKey isEqualToString:@"link"])
						URLStr = [[linkPropsDescriptor descriptorAtIndex:m+1] stringValue];
					else if ([linkPropsKey isEqualToString:@"title"])
						titleStr = [[linkPropsDescriptor descriptorAtIndex:m+1] stringValue];
				}
				
				if (URLStr == nil || titleStr == nil)
					continue;
				
				NSString *weblocFilePath = [self
											getWeblocFilePathForTitle:titleStr
											URL:URLStr
											];
				if (weblocFilePath == nil)
					continue;
				
				[self addFileToTag:weblocFilePath];
				
				if (weblinkCustomTitle != nil)
					continue;
				NSString *weblocFileName = [weblocFilePath lastPathComponent];
				NSRange dotRange = [weblocFileName rangeOfString:@"." options:NSBackwardsSearch];
				if (dotRange.location != NSNotFound)
					weblinkCustomTitle = [weblocFileName substringToIndex:dotRange.location];
				else
					weblinkCustomTitle = weblocFileName;
			}
		}
		// {title:"3 MyApp documents"}
		else if ([key isEqualToString:@"title"])
		{
			self.customTitle = [[asOutput descriptorAtIndex:i+1] stringValue];
		}
	}
	
	if (self.customTitle == nil && weblinkCustomTitle != nil)
		self.customTitle = weblinkCustomTitle;
}




// NSApplication delegate method: receive file to open (drag & drop or
// dbl-click if set as handler for a file type.) Gets called once for
// each file if several "opened" at once
- (BOOL) application:(NSApplication *)anApplication
			openFile:(NSString *)aFileName
{
	[self addFileToTag:aFileName];
	return NO;
}


- (void) applicationWillFinishLaunching:(NSNotification *)notification
{
	// On first launch: ask the user if they want to use automatic
	// updates or not.
	// We don't want to delegate this to Sparkle because we want
	// the automatic updates to use Sparkle's SUProbingUpdateDriver
	// (which doesn't pop up the update dialog when it finds updates)
	// instead of SUScheduledUpdateDriver (which does pop up the
	// dialog, and which Sparkle would use for this if we let it
	// handle the automatic update checking). We want to display the
	// small update button in the main window instead of popping up
	// the dialog like Sparkle does, so we do this manually by calling
	// Sparkle's -checkForUpdateInformation (which uses
	// SUProbingUpdateDriver) in our -checkForUpdatesSilently method.
	// 
	if (![kDefaults boolForKey:kDefaultsKey_HaveAskedAboutAutoUpdates])
	{
		NSInteger choice = NSRunInformationalAlertPanel(@"Check for updates automatically?",
														@"Should Tagger automatically check for updates? You can always check for updates manually from the Tagger menu.",
														@"Yes",
														@"No",
														nil);
		if (choice == NSAlertDefaultReturn)
			[kDefaults setBool:YES forKey:kDefaultsKey_AutomaticallyCheckForUpdates];
		[kDefaults setBool:YES forKey:kDefaultsKey_HaveAskedAboutAutoUpdates];
	}
	
	[self checkForUpdatesSilently];
	
	// If not in /Applications, offer to move it there
	PFMoveToApplicationsFolderIfNecessary();
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	DDLogInfo(@"applicationDidFinishLaunching");
	DDLogInfo(@"frontAppBundleID = %@", frontAppBundleID);
	
	BOOL filesToTagAreFromFrontApp = ([self.filesToTag count] == 0);
	
	[progressIndicator startAnimation:self];
	
	if (frontAppBundleID != nil)
	{
		if ([self.filesToTag count] == 0)
			[self getFilesFromFrontAppUsingUserScripts];
		
		if ([self.filesToTag count] == 0)
			[self getFilesFromFrontAppUsingBuiltinMethods];
	}
	
	if ([self.filesToTag count] == 0 && frontAppDocumentURLString != nil)
	{
		NSURL *frontAppDocumentURL = [NSURL URLWithString:frontAppDocumentURLString];
		[self addFileToTag:[frontAppDocumentURL path]];
	}
	
	if ([kDefaults boolForKey:kDefaultsKey_ShowFrontAppIcon] &&
		[self.filesToTag count] > 0 &&
		filesToTagAreFromFrontApp &&
		frontAppBundleID != nil
		)
	{
		NSString *frontAppPath = [[NSWorkspace sharedWorkspace]
								  absolutePathForAppBundleWithIdentifier:
								  frontAppBundleID];
		[appIconImageView setImage:[[NSWorkspace sharedWorkspace]
									iconForFile:frontAppPath]];
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
			if (self.customTitle != nil)
				[filenameLabel setStringValue:self.customTitle];
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
			
			if (self.customTitle != nil)
				[filenameLabel setStringValue:self.customTitle];
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
			if ([kDefaults boolForKey:kDefaultsKey_ShowFrontAppIcon])
				[appIconImageView setHidden:NO];
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




#pragma mark -
#pragma mark Getting the file thumbnail/icon

// method for setting the preview image (or icon) of a file to an imageview
// -- to be run in a thread of its own
- (void) setFileIconToView:(NSString *)pathToFile
{
	NSAutoreleasePool *setIconThreadAutoReleasePool = [[NSAutoreleasePool alloc] init];
	
	BOOL isDir = NO;
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:pathToFile isDirectory:&isDir];
	
	NSImage *icon = nil;
	
	if (exists)
	{
		BOOL isPackage = [[NSWorkspace sharedWorkspace] isFilePackageAtPath:pathToFile];
		BOOL useIconDecor = (!isDir || isPackage);
		
		icon = [NSImage
				imageWithPreviewOfFileAtPath:pathToFile
				ofSize:NSMakeSize(180,180)
				asIcon:useIconDecor
				];
	}
	
	[self
	 performSelectorOnMainThread:@selector(fileIconDoneHandler:)
	 withObject:icon
	 waitUntilDone:NO
	 ];
	
	[setIconThreadAutoReleasePool drain];
}


- (void) fileIconDoneHandler:(NSImage *)image
{
	if (image != nil)
		[iconImageView setImage:image];
	
	if ([kDefaults boolForKey:kDefaultsKey_ShowFrontAppIcon])
		[appIconImageView setHidden:NO];
	
	[progressIndicator stopAnimation:self];
}







#pragma mark -
#pragma mark Saving the tags, quitting

- (void) cleanUpBeforeQuitting
{
	if (cleanupStarted)
		return;
	cleanupStarted = YES;
	[OpenMetaPrefs synchPrefs];
	[OpenMetaBackup appIsTerminating];
	[self deleteWeblocFilesIfNecessary];
}

- (void) terminateAppSafely
{
	[self cleanUpBeforeQuitting];
	[NSApp terminate:self];
}



- (void) windowWillClose:(NSNotification *)notification
{
	[self terminateAppSafely];
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








#pragma mark -
# pragma mark Window drag & drop

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
	NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
	
	if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		if (sourceDragMask & NSDragOperationCopy)
			return NSDragOperationCopy;
	}
	
	return NSDragOperationNone;
}


- (BOOL) prepareForDragOperation:(id < NSDraggingInfo >)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
	
	if (![[pboard types] containsObject:NSFilenamesPboardType])
		return NO;
	
	NSArray *filePaths = [pboard propertyListForType:NSFilenamesPboardType];
	for (NSString *thisFilePath in filePaths)
	{
		if (![thisFilePath hasSuffix:@".scpt"])
			return NO;
	}
	return YES;
}


- (BOOL) performDragOperation:(id < NSDraggingInfo >)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
	
	if (![[pboard types] containsObject:NSFilenamesPboardType])
		return NO;
	
	NSArray *filePaths = [pboard propertyListForType:NSFilenamesPboardType];
	NSString *thisFilePath = [filePaths objectAtIndex:0];
	if ([thisFilePath hasSuffix:@".scpt"])
	{
		[self showScriptsWindowSelected:self];
		[(ScriptWindowController *)[scriptsWindow delegate] suggestAddFrontAppScript:thisFilePath];
		[NSApp activateIgnoringOtherApps:YES];
		return YES;
	}
	
	return NO;
}







#pragma mark -
#pragma mark Version check & update

- (void) checkForUpdatesSilently
{
	if (![kDefaults boolForKey:kDefaultsKey_AutomaticallyCheckForUpdates])
		return;
	
	// throttle the update checking.
	// (we just check if the last update check date was on the same day
	// as the current date; if we enforced a time interval between them
	// the user changing the system date could get us into a situation
	// where updates wouldn't be checked for for an arbitrarily long time,
	// whereas with this system our plans are not affected greatly by
	// the system date changing)
	// 
	NSDate *lastCheckDate = [kDefaults objectForKey:kDefaultsKey_LastUpdateCheckDate];
	if (lastCheckDate == nil)
		lastCheckDate = [NSDate distantPast];
	if (datesRepresentSameDay(lastCheckDate, [NSDate date]))
	{
		DDLogInfo(@"not checking for updates (time interval since last check is too low).");
		return;
	}
	
	updatesExistCheckInProgress = YES;
	shouldInformUserIfNoUpdates = NO;
	[[SUUpdater sharedUpdater] setDelegate:self];
	[[SUUpdater sharedUpdater] checkForUpdateInformation];
	DDLogInfo(@"checking for updates...");
}

  - (void) updater:(SUUpdater *)updater
didFindValidUpdate:(SUAppcastItem *)update
{
	if (!updatesExistCheckInProgress)
		return;
	
	[updateCheckLabel setHidden:YES];
	[updateProgressIndicator setHidden:YES];
	[updateProgressIndicator stopAnimation:self];
	
	NSString *currentVersionString = [self getVersionString];
	NSString *latestVersionString = [update versionString];
	
	DDLogInfo(@"update found! (latest: %@ current: %@)", latestVersionString, currentVersionString);
	[updateButton setTitle:@"Update available!"];
	[updateButton
	 setToolTip:[NSString
				 stringWithFormat:
				 @"Version %@ of Tagger is available! (you have v.%@)",
				 latestVersionString,
				 currentVersionString
				 ]
	 ];
	[updateButton setEnabled: YES];
	[updateButton setHidden: NO];
	allowManualUpdateCheck = NO;
	
	[kDefaults setObject:[NSDate date] forKey:kDefaultsKey_LastUpdateCheckDate];
}

- (void) updaterDidNotFindUpdate:(SUUpdater *)update
{
	if (!updatesExistCheckInProgress)
		return;
	
	[updateCheckLabel setHidden:YES];
	[updateProgressIndicator setHidden:YES];
	[updateProgressIndicator stopAnimation:self];
	
	DDLogInfo(@"no update found.");
	[kDefaults setObject:[NSDate date] forKey:kDefaultsKey_LastUpdateCheckDate];
	
	if (shouldInformUserIfNoUpdates)
		NSRunAlertPanel(@"You're up to date!",
						[NSString stringWithFormat:
						 @"Tagger %@ is currently the newest version available.",
						 [self getVersionString]
						 ],
						@"OK",
						nil, nil);
}

- (void) updaterWillRelaunchApplication:(SUUpdater *)updater
{
	[self cleanUpBeforeQuitting];
}



- (IBAction) checkForUpdates:(id)sender
{
	DDLogInfo(@"searching for updates...");
	updatesExistCheckInProgress = YES;
	shouldInformUserIfNoUpdates = YES;
	[updateButton setHidden: YES];
	[updateCheckLabel setHidden:NO];
	[updateProgressIndicator setHidden:NO];
	[updateProgressIndicator startAnimation:self];
	[[SUUpdater sharedUpdater] setDelegate:self];
	[[SUUpdater sharedUpdater] checkForUpdateInformation];
}

- (IBAction) updateApp:(id)sender
{
	if (self.installUpdateInvocation != nil)
	{
		[self.installUpdateInvocation invoke];
		return;
	}
	
	if ([[SUUpdater sharedUpdater] updateInProgress])
		return;
	DDLogInfo(@"updating app");
	updatesExistCheckInProgress = NO;
	[updateButton setHidden: YES];
	[updateCheckLabel setStringValue:@"Downloading info..."];
	[updateCheckLabel setHidden:NO];
	[updateProgressIndicator setHidden:NO];
	[updateProgressIndicator startAnimation:self];
	[[SUUpdater sharedUpdater] setDelegate:self];
	[[SUUpdater sharedUpdater] checkForUpdatesWithNoStatusUIAndDriverDelegate:self];
}



- (void)updateDriverWillStartDownloadingUpdate
{
	[updateCheckLabel setStringValue:@"Downloading update..."];
	[updateProgressIndicator setIndeterminate:YES];
}

- (void)updateDriverDidReceiveExpectedDownloadLength:(double)length
{
	if (length == 0)
		return;
	[updateProgressIndicator setIndeterminate:NO];
	[updateProgressIndicator setMaxValue:length];
	[updateProgressIndicator setDoubleValue:0];
}

- (void)updateDriverDidDownloadDataOfLength:(double)length
{
	[updateProgressIndicator setDoubleValue:[updateProgressIndicator doubleValue]+length];
}

- (void)updateDriverWillStartExtractingUpdate
{
	[updateCheckLabel setStringValue:@"Extracting update..."];
	[updateProgressIndicator setIndeterminate:YES];
}

- (void)updateDriverDidReceiveExpectedExtractionLength:(double)length
{
	if (length == 0)
		return;
	[updateProgressIndicator setIndeterminate:NO];
	[updateProgressIndicator setMaxValue:length];
	[updateProgressIndicator setDoubleValue:0];
}

- (void)updateDriverDidExtractDataOfLength:(double)length
{
	[updateProgressIndicator setDoubleValue:[updateProgressIndicator doubleValue]+length];
}

- (void)updateDriverReadyToInstallUpdateWithInvocation:(NSInvocation *)invocation
{
	[updateButton setHidden:NO];
	[updateButton setTitle:@"Install update and restart"];
	[updateButton setToolTip:nil];
	[updateCheckLabel setHidden:YES];
	[updateProgressIndicator setHidden:YES];
	[updateProgressIndicator stopAnimation:self];
	self.installUpdateInvocation = invocation;
}

- (void)updateDriverWillStartInstallingUpdate
{
	[updateButton setHidden:YES];
	[updateCheckLabel setHidden:NO];
	[updateProgressIndicator setHidden:NO];
	[updateProgressIndicator setIndeterminate:YES];
	[updateProgressIndicator startAnimation:self];
	[tagsField setEnabled:NO];
	[okButton setEnabled:NO];
	[updateCheckLabel setStringValue:@"Installing..."];
}

- (void)updateDriverDidAbortUpdate
{
	[updateButton setHidden:YES];
	[updateCheckLabel setHidden:YES];
	[updateProgressIndicator setHidden:YES];
	[updateProgressIndicator stopAnimation:self];
	allowManualUpdateCheck = YES;
	self.installUpdateInvocation = nil;
}




@end
