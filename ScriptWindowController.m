//
//  ScriptWindowController.m
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

#import "ScriptWindowController.h"
#import "NSArray+NSTableViewDataSource.h"

#define kCatalogURL		[NSURL URLWithString:@"http://hasseg.org/tagger/frontAppCatalog.php"]

@implementation ScriptWindowController

@synthesize installedScripts;
@synthesize repoScripts;
@synthesize loadCatalogConnection;
@synthesize catalogData;
@synthesize addedScriptPath;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	self.installedScripts = [NSMutableArray array];
	self.repoScripts = [NSMutableArray array];
	
	return self;
}

- (void) dealloc
{
	self.installedScripts = nil;
	self.repoScripts = nil;
	self.loadCatalogConnection = nil;
	self.catalogData = nil;
	self.addedScriptPath = nil;
	[super dealloc];
}


- (void) awakeFromNib
{
	[mainTabView selectTabViewItem:[mainTabView tabViewItemAtIndex:0]];
	[installedScriptsTable setDataSource:self.installedScripts];
	[repoScriptsTable setDataSource:self.repoScripts];
}


- (void) updateInstalledScripts
{
	[self.installedScripts removeAllObjects];
	
	for (NSString *appID in mainController.scriptsCatalog)
	{
		NSMutableDictionary *scriptDict = [NSMutableDictionary dictionaryWithCapacity:3];
		
		NSString *appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:appID];
		NSString *appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
		NSString *fileName = [mainController.scriptsCatalog objectForKey:appID];
		
		NSString *scriptPath = [mainController.scriptsDirPath stringByAppendingPathComponent:fileName];
		BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath:scriptPath];
		if (!scriptExists)
			continue;
		
		if (![self.installedScripts containsObject:appName])
			[scriptDict setObject:appName forKey:@"application"];
		else
			[scriptDict setObject:appID forKey:@"application"];
		
		[scriptDict setObject:fileName forKey:@"filename"];
		
		[self.installedScripts addObject:scriptDict];
	}
	
	installedScriptsUpdatedAtLeastOnce = YES;
}

- (void) updateSelectedScriptInfo
{
	if ([[repoScriptsTable selectedRowIndexes] count] == 0)
	{
		[scriptInfoTitleField setStringValue:@""];
		[scriptInfoField setStringValue:@""];
		return;
	}
	
	NSDictionary *selectedScriptDict = [self.repoScripts objectAtIndex:[repoScriptsTable selectedRow]];
	if (selectedScriptDict == nil)
	{
		[scriptInfoTitleField setStringValue:@""];
		[scriptInfoField setStringValue:@""];
		return;
	}
	
	NSString *title = [NSString
					   stringWithFormat:
					   @"%@ Script",
					   [selectedScriptDict objectForKey:@"AppName"]];
	if ([[selectedScriptDict allKeys] containsObject:@"Author"])
		title = [title stringByAppendingFormat:@" by %@", [selectedScriptDict objectForKey:@"Author"]];
	
	NSString *info = [selectedScriptDict objectForKey:@"Info"];
	if (info == nil)
		info = @"No additional info for this script.";
	
	[scriptInfoTitleField setStringValue:title];
	[scriptInfoField setStringValue:info];
}




#pragma mark -
#pragma mark Loading the catalog from the server

- (void) loadCatalogFromServer
{
	[repoScriptsProgressIndicator startAnimation:self];
	[reloadRepoButton setEnabled:NO];
	[installButton setEnabled:NO];
	[repoScriptsTable setEnabled:NO];
	
	NSURLRequest *request = [NSURLRequest
							 requestWithURL:kCatalogURL
							 cachePolicy:NSURLRequestReloadIgnoringCacheData
							 timeoutInterval:10.0
							 ];
	
	self.catalogData = [NSMutableData data];
	
	if (!self.loadCatalogConnection)
		self.loadCatalogConnection = [NSURLConnection
									   connectionWithRequest:request
									   delegate:self
									   ];
}

- (void) connection:(NSURLConnection *)connection
   didFailWithError:(NSError *)error
{
	self.loadCatalogConnection = nil;
	
	[repoScriptsProgressIndicator stopAnimation:self];
	
	NSRunAlertPanel(@"Script Repository Update Failed",
					[NSString
					 stringWithFormat:
					 @"Could not load scripts from repository. Error: %@ %@",
					 [error localizedDescription],
					 [[error userInfo] objectForKey:NSErrorFailingURLStringKey]],
					 @"OK", nil,nil);
	
	[reloadRepoButton setEnabled:YES];
	[repoScriptsTable setEnabled:YES];
	[installButton setEnabled:([[repoScriptsTable selectedRowIndexes] count] > 0)];
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
}

- (void) connection:(NSURLConnection *)connection
	 didReceiveData:(NSData *)data
{
	[self.catalogData appendData:data];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
	self.loadCatalogConnection = nil;
	[repoScriptsProgressIndicator stopAnimation:self];
	[reloadRepoButton setEnabled:YES];
	
	NSString *deSerializationError = nil;
	NSArray *scripts = [NSPropertyListSerialization
						propertyListFromData:self.catalogData
						mutabilityOption:0
						format:NULL
						errorDescription:&deSerializationError];
	
	if (deSerializationError != nil)
	{
		NSRunAlertPanel(@"Script Repository Update Failed",
						[NSString
						 stringWithFormat:
						 @"Could not deserialize server response. Error: %@",
						 deSerializationError],
						@"OK", nil,nil);
		return;
	}
	else if (scripts == nil)
	{
		NSRunAlertPanel(@"Script Repository Update Failed",
						@"Could not deserialize server response -- not in correct format.",
						@"OK", nil,nil);
		return;
	}
	
	[self.repoScripts removeAllObjects];
	for (NSDictionary *scriptDict in scripts)
	{
		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:scriptDict];
		
		if (![[dict allKeys] containsObject:@"AppName"])
			continue;
		if (![[dict allKeys] containsObject:@"AppID"])
			continue;
		if (![[dict allKeys] containsObject:@"DownloadURL"])
			continue;
		if (![[dict allKeys] containsObject:@"Author"])
			[dict setObject:@"?" forKey:@"table-Author"];
		else
			[dict setObject:[dict objectForKey:@"Author"] forKey:@"table-Author"];
		if (![[dict allKeys] containsObject:@"Version"])
			[dict setObject:@"?" forKey:@"table-Version"];
		else
			[dict setObject:[dict objectForKey:@"Version"] forKey:@"table-Version"];
		
		[self.repoScripts addObject:dict];
	}
	
	[repoScriptsTable setEnabled:YES];
	[repoScriptsTable reloadData];
	[installButton setEnabled:([[repoScriptsTable selectedRowIndexes] count] > 0)];
	catalogLoadedAtLeastOnce = YES;
}





- (IBAction) uninstallButtonSelected:(id)sender
{
	// todo: this
}

- (IBAction) installButtonSelected:(id)sender
{
	// todo: this
}

- (IBAction) reloadRepoButtonSelected:(id)sender
{
	[self loadCatalogFromServer];
}






#pragma mark -
#pragma mark Adding new Front App Scripts

- (void) showAddScriptDialog
{
	[NSApp
	 beginSheet:addScriptSheet
	 modalForWindow:scriptsWindow
	 modalDelegate:self
	 didEndSelector:NULL
	 contextInfo:nil
	 ];
}

- (void) closeAddScriptDialog
{
	[addScriptSheet orderOut:nil];
	[NSApp endSheet:addScriptSheet];
}


- (NSString *) idOfApplication:(NSString *)appName
{
	NSString *identifier = nil;
	
	NSString *appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:appName];
	NSString *appInfoPlistPath = [appPath stringByAppendingPathComponent:@"Contents/Info.plist"];
	NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:appInfoPlistPath];
	if (infoDict != nil)
		identifier = [infoDict objectForKey:(NSString *)kCFBundleIdentifierKey];
	
	// confirm
	if ([[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:identifier] == nil)
		return nil;
	
	return identifier;
}


- (void) suggestAddFrontAppScript:(NSString *)filePath
{
	self.addedScriptPath = filePath;
	
	NSString *fileName = [filePath lastPathComponent];
	[scriptFilenameField setStringValue:fileName];
	
	NSString *guessedAppID = [self idOfApplication:[fileName stringByDeletingPathExtension]];
	
	if (guessedAppID != nil)
		[appIDField setStringValue:guessedAppID];
	else
		[appIDField setStringValue:@""];
	
	[self showAddScriptDialog];
}

- (IBAction) addScriptSheetSubmit:(id)sender
{
	// enable the front app scripts feature
	if (![kDefaults boolForKey:kDefaultsKey_UserFrontAppScriptsEnabled])
		[kDefaults setBool:YES forKey:kDefaultsKey_UserFrontAppScriptsEnabled];
	
	[mainController ensureScriptsCatalogFileExists];
	
	NSString *appID = nil;
	NSString *appIDOrName = [appIDField stringValue];
	NSString *appPath = nil;
	NSString *errMsg = nil;
	
	if (appIDOrName == nil || [appIDOrName length] == 0)
		errMsg = @"No application identifier or name specified";
	
	if (errMsg == nil)
	{
		appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:appIDOrName];
		
		if (appPath != nil)
			appID = appIDOrName;
		else
		{
			appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:appIDOrName];
			if (appPath != nil)
				appID = [self idOfApplication:appIDOrName];
		}
		
		if (appPath == nil)
			errMsg = [NSString
					  stringWithFormat:
					  @"Can not find any application on this system matching the identifier or name: %@",
					  appIDOrName];
	}
	
	if (errMsg != nil)
	{
		NSRunAlertPanel(@"Error with Application Identifier", errMsg, @"OK", nil, nil);
		return;
	}
	
	NSString *appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
	
	// read existing catalog file, check for app ID overlap
	BOOL replaceExistingScript = NO;
	NSString *catalogFilePath = [mainController.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	NSMutableDictionary *catalog = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	if ([[catalog allKeys] containsObject:appID])
	{
		NSInteger choice = NSRunAlertPanel([NSString
											stringWithFormat:
											@"Script for %@ already exists",
											appName],
										   [NSString
											stringWithFormat:
											@"You already have a script set up for %@. Do you want to replace the existing script with this one? (The existing file won't be replaced, only the catalog file entry will be)",
											appName],
										   @"Don't replace",
										   @"Cancel",
										   @"Replace"
										   );
		if (choice == NSAlertDefaultReturn)
		{
			[self closeAddScriptDialog];
			return;
		}
		else if (choice == NSAlertAlternateReturn)
			return;
		else if (choice == NSAlertOtherReturn)
			replaceExistingScript = YES;
	}
	
	
	// copy script into Scripts folder, avoiding filename
	// collisions by appending a running number to the end
	NSString *fileName = [self.addedScriptPath lastPathComponent];
	NSString *newPath = [mainController.scriptsDirPath stringByAppendingPathComponent:fileName];
	NSUInteger numberPrefixCounter = 1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:newPath])
	{
		NSString *newFileName = [fileName stringByDeletingPathExtension];
		newFileName = [newFileName stringByAppendingFormat:@" %i.%@", numberPrefixCounter, [fileName pathExtension]];
		newPath = [mainController.scriptsDirPath stringByAppendingPathComponent:newFileName];
		numberPrefixCounter++;
	}
	
	NSError *copyError = nil;
	[[NSFileManager defaultManager]
	 copyItemAtPath:self.addedScriptPath
	 toPath:newPath
	 error:&copyError];
	
	if (copyError != nil)
	{
		NSRunAlertPanel(@"Error copying script",
						[NSString
						 stringWithFormat:
						 @"There was an error while copying the script \"%@\" into the Front Application Scripts folder: %@",
						 fileName, [copyError localizedDescription]],
						@"OK",
						nil,
						nil);
		[self closeAddScriptDialog];
		return;
	}
	
	// set the catalog entry and write the catalog file
	[catalog setObject:fileName forKey:appID];
	[catalog writeToFile:catalogFilePath atomically:YES];
	mainController.scriptsCatalog = catalog;
	
	NSRunInformationalAlertPanel(@"Script Added",
								 [NSString
								  stringWithFormat:
								  @"The script \"%@\" has successfully been added for application %@.",
								  fileName, appName],
								 @"OK",
								 nil,
								 nil);
	
	self.addedScriptPath = nil;
	[self closeAddScriptDialog];
	[self updateInstalledScripts];
}

- (IBAction) addScriptSheetCancel:(id)sender
{
	self.addedScriptPath = nil;
	[self closeAddScriptDialog];
}







#pragma mark -
#pragma mark NSWindow delegate methods

- (void) windowDidBecomeKey:(NSNotification *)notification
{
	if (!installedScriptsUpdatedAtLeastOnce)
		[self updateInstalledScripts];
	[installedScriptsTable reloadData];
}



#pragma mark -
#pragma mark NSTableView delegate methods

- (void) tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([[aNotification object] isEqual:installedScriptsTable])
	{
		[uninstallButton setEnabled:([[installedScriptsTable selectedRowIndexes] count] > 0)];
	}
	else if ([[aNotification object] isEqual:repoScriptsTable])
	{
		[installButton setEnabled:([[repoScriptsTable selectedRowIndexes] count] > 0)];
		[self updateSelectedScriptInfo];
	}
}



#pragma mark -
#pragma mark NSTabView delegate methods

	 - (void) tabView:(NSTabView *)tabView
willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if ([[tabViewItem identifier] intValue] == 2) // 'get more scripts'
	{
		if (!catalogLoadedAtLeastOnce)
			[self loadCatalogFromServer];
	}
}


@end
