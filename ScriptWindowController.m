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
#import "TaggerDefines.h"
#import "NSData+SHA1.h"
#import "HGUtils.h"




@implementation ScriptWindowController

@synthesize installedScripts;
@synthesize repoScripts;
@synthesize loadCatalogConnection;
@synthesize catalogData;
@synthesize addedScriptPath;
@synthesize scriptDownloadConnection;
@synthesize downloadedScriptData;
@synthesize downloadedScriptCatalogInfo;


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
	self.scriptDownloadConnection = nil;
	self.downloadedScriptData = nil;
	self.downloadedScriptCatalogInfo = nil;
	[super dealloc];
}


- (void) awakeFromNib
{
	[mainTabView selectTabViewItem:[mainTabView tabViewItemAtIndex:0]];
	[installedScriptsTable setDataSource:self.installedScripts];
	[repoScriptsTable setDataSource:self.repoScripts];
	
	// register window for drag & drop operations
	[scriptsWindow registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
}


- (void) updateInstalledScripts
{
	[self.installedScripts removeAllObjects];
	
	for (NSString *appID in mainController.scriptsCatalog)
	{
		NSMutableDictionary *scriptDict = [NSMutableDictionary dictionaryWithCapacity:4];
		[scriptDict setObject:appID forKey:@"id"];
		
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
		
		NSString *hashString = [[[NSData dataWithContentsOfFile:scriptPath] SHA1Digest] hexStringValue];
		[scriptDict setObject:hashString forKey:@"hash"];
		
		[self.installedScripts addObject:scriptDict];
	}
	
	installedScriptsUpdatedAtLeastOnce = YES;
}

- (void) updateSelectedScriptInfo
{
	if ([[repoScriptsTable selectedRowIndexes] count] == 0)
	{
		[scriptInfoTitleField setStringValue:@""];
		[scriptInfoField setString:@""];
		[youAlreadyHaveThisInfoField setHidden:YES];
		[installButton setEnabled:NO];
		return;
	}
	
	NSDictionary *selectedScriptDict = [self.repoScripts objectAtIndex:[repoScriptsTable selectedRow]];
	if (selectedScriptDict == nil)
	{
		[scriptInfoTitleField setStringValue:@""];
		[scriptInfoField setString:@""];
		[youAlreadyHaveThisInfoField setHidden:YES];
		[installButton setEnabled:NO];
		return;
	}
	
	
	NSString *title = [NSString
					   stringWithFormat:
					   @"%@ Script",
					   [selectedScriptDict objectForKey:kScriptRepoDataKey_appName]];
	if ([[selectedScriptDict allKeys] containsObject:kScriptRepoDataKey_author])
		title = [title stringByAppendingFormat:@" by %@", [selectedScriptDict objectForKey:kScriptRepoDataKey_author]];
	
	NSString *info = [selectedScriptDict objectForKey:kScriptRepoDataKey_info];
	if (info == nil)
		info = @"No additional info for this script.";
	
	[scriptInfoTitleField setStringValue:title];
	[scriptInfoField setString:info];
	
	NSString *hash = [selectedScriptDict objectForKey:kScriptRepoDataKey_hash];
	NSString *appID = [selectedScriptDict objectForKey:kScriptRepoDataKey_appID];
	BOOL exists = [self scriptExistsWithHash:hash forAppID:appID];
	[youAlreadyHaveThisInfoField setHidden:!exists];
	[installButton setEnabled:!exists];
}


- (BOOL) scriptExistsWithHash:(NSString *)hash
					 forAppID:(NSString *)appID
{
	for (NSDictionary *installedScriptInfo in self.installedScripts)
	{
		if ([[installedScriptInfo objectForKey:@"id"] isEqualToString:appID] &&
			[[installedScriptInfo objectForKey:@"hash"] isEqualToString:hash]
			)
			return YES;
	}
	return NO;
}




#pragma mark -
#pragma mark Loading stuff from the server

- (void) loadCatalogFromServer
{
	[repoScriptsProgressIndicator startAnimation:self];
	[reloadRepoButton setEnabled:NO];
	[installButton setEnabled:NO];
	[repoScriptsTable setEnabled:NO];
	
	NSURLRequest *request = [NSURLRequest
							 requestWithURL:kScriptRepoURL
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
	if ([connection isEqual:self.loadCatalogConnection])
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
	}
	else if ([connection isEqual:self.scriptDownloadConnection])
	{
		self.scriptDownloadConnection = nil;
		self.downloadedScriptData = nil;
		self.downloadedScriptCatalogInfo = nil;
		[scriptDownloadProgressIndicator stopAnimation:self];
		[downloadInfoField setStringValue:@""];
		
		NSRunAlertPanel(@"Failed to download script",
						[NSString
						 stringWithFormat:
						 @"Could not download script from repository. Error: %@ %@",
						 [error localizedDescription],
						 [[error userInfo] objectForKey:NSErrorFailingURLStringKey]],
						@"OK", nil,nil);
		
		[self closeDownloadProgressSheet];
	}
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
	if ([connection isEqual:self.loadCatalogConnection])
		[self.catalogData appendData:data];
	else if ([connection isEqual:self.scriptDownloadConnection])
	{
		[self.downloadedScriptData appendData:data];
		[downloadInfoField
		 setStringValue:[NSString
						 stringWithFormat:
						 @"Downloaded %@",
						 stringFromBytes([self.downloadedScriptData length])]];
	}
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
	if ([connection isEqual:self.loadCatalogConnection])
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
			
			if (![[dict allKeys] containsObject:kScriptRepoDataKey_appName])
				continue;
			if (![[dict allKeys] containsObject:kScriptRepoDataKey_appID])
				continue;
			if (![[dict allKeys] containsObject:kScriptRepoDataKey_downloadURL])
				continue;
			if (![[dict allKeys] containsObject:kScriptRepoDataKey_author])
				[dict setObject:@"?" forKey:@"table-Author"];
			else
				[dict setObject:[dict objectForKey:kScriptRepoDataKey_author] forKey:@"table-Author"];
			if (![[dict allKeys] containsObject:@"Version"])
				[dict setObject:@"?" forKey:@"table-Version"];
			else
				[dict setObject:[dict objectForKey:@"Version"] forKey:@"table-Version"];
			
			[self.repoScripts addObject:dict];
		}
		
		[repoScriptsTable setEnabled:YES];
		[repoScriptsTable reloadData];
		catalogLoadedAtLeastOnce = YES;
		self.catalogData = nil;
	}
	else if ([connection isEqual:self.scriptDownloadConnection])
	{
		NSString *appID = [self.downloadedScriptCatalogInfo objectForKey:kScriptRepoDataKey_appID];
		NSString *appName = [self.downloadedScriptCatalogInfo objectForKey:kScriptRepoDataKey_appName];
		
		self.scriptDownloadConnection = nil;
		self.downloadedScriptCatalogInfo = nil;
		[scriptDownloadProgressIndicator stopAnimation:self];
		[self closeDownloadProgressSheet];
		[downloadInfoField setStringValue:@""];
		
		[self
		 addScriptForAppID:appID
		 appName:appName
		 withScriptData:self.downloadedScriptData
		 replacingWithoutAsking:replaceDownloadedScriptWithoutAsking];
		
		self.downloadedScriptData = nil;
		[self updateSelectedScriptInfo];
	}
}




#pragma mark -
#pragma mark Install & Uninstall


- (IBAction) uninstallButtonSelected:(id)sender
{
	// confirm
	NSUInteger numSelected = [[installedScriptsTable selectedRowIndexes] count];
	NSString *scriptReference = ((numSelected==1)?@"script":[NSString stringWithFormat:@"%i scripts", numSelected]);
	NSUInteger choice = NSRunAlertPanel(@"Uninstall confirmation",
										[NSString
										 stringWithFormat:
										 @"Are you sure you want to uninstall the selected %@?",
										 scriptReference],
										@"Uninstall",
										@"Cancel",nil);
	if (choice != NSAlertDefaultReturn)
		return;
	
	// uninstall each
	NSIndexSet *selectedRows = [installedScriptsTable selectedRowIndexes];
	NSUInteger i;
	for (i = [selectedRows firstIndex]; i != NSNotFound; i = [selectedRows indexGreaterThanIndex:i])
	{
		NSDictionary *scriptInfo = [self.installedScripts objectAtIndex:i];
		NSString *appID = [scriptInfo objectForKey:@"id"];
		NSString *scriptFilename = [scriptInfo objectForKey:@"filename"];
		NSString *scriptPath = [mainController.scriptsDirPath stringByAppendingPathComponent:scriptFilename];
		
		moveFileToTrash(scriptPath);
		
		[mainController.scriptsCatalog removeObjectForKey:appID];
	}
	
	NSString *catalogPath = [mainController.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	[mainController.scriptsCatalog writeToFile:catalogPath atomically:YES];
	[self updateInstalledScripts];
	[installedScriptsTable reloadData];
	
	NSRunInformationalAlertPanel(@"Uninstallation OK",
								 [NSString
								  stringWithFormat:
								  @"The selected %@ %@ been successfully uninstalled.",
								  scriptReference, ((numSelected==1)?@"has":@"have")],
								 @"OK", nil,nil);
}


- (IBAction) installButtonSelected:(id)sender
{
	// check that the app exists on the local system
	NSDictionary *scriptDict = [self.repoScripts objectAtIndex:[repoScriptsTable selectedRow]];
	NSString *appName = [scriptDict objectForKey:kScriptRepoDataKey_appName];
	NSString *appID = [scriptDict objectForKey:kScriptRepoDataKey_appID];
	NSString *appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:appID];
	if (appPath == nil)
	{
		NSRunAlertPanel(@"Can't find application",
						[NSString
						 stringWithFormat:
						 @"Can not find this application on your system: %@ (%@)",
						 appName, appID],
						@"Cancel", nil,nil);
		return;
	}
	
	// check if we already have this script, if the server has
	// sent us a hash for the selected script
	NSString *hash = [scriptDict objectForKey:kScriptRepoDataKey_hash];
	if (hash != nil && [self scriptExistsWithHash:hash forAppID:appID])
	{
		NSRunAlertPanel([NSString
						 stringWithFormat:
						 @"You already have this script",
						 appName],
						[NSString
						 stringWithFormat:
						 @"The script you have set up for %@ is exactly the same as this one in the server repository.",
						 appName],
						@"Cancel", nil,nil);
		return;
	}
	
	// read existing catalog file
	NSString *catalogFilePath = [mainController.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	NSMutableDictionary *catalog = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	
	// check for app ID overlap
	replaceDownloadedScriptWithoutAsking = NO;
	if ([[catalog allKeys] containsObject:appID])
	{
		NSInteger choice = NSRunAlertPanel([NSString
											stringWithFormat:
											@"Script for %@ already exists",
											appName],
										   [NSString
											stringWithFormat:
											@"You already have a script set up for %@. Do you want to replace the existing script with this one?",
											appName],
										   @"Cancel",
										   @"Replace",
										   nil
										   );
		
		if (choice == NSAlertDefaultReturn) // Cancel
			return;
		else if (choice == NSAlertAlternateReturn) // Replace
			replaceDownloadedScriptWithoutAsking = YES;
	}
	
	// begin download
	self.downloadedScriptCatalogInfo = scriptDict;
	NSURL *scriptURL = [NSURL URLWithString:[scriptDict objectForKey:kScriptRepoDataKey_downloadURL]];
	NSURLRequest *request = [NSURLRequest
							 requestWithURL:scriptURL
							 cachePolicy:NSURLRequestReloadIgnoringCacheData
							 timeoutInterval:10.0
							 ];
	
	self.downloadedScriptData = [NSMutableData data];
	
	if (!self.scriptDownloadConnection)
		self.scriptDownloadConnection = [NSURLConnection
										 connectionWithRequest:request
										 delegate:self
										 ];
	[downloadInfoField setStringValue:@"Waiting..."];
	[self showDownloadProgressSheet];
	[scriptDownloadProgressIndicator startAnimation:self];
}


- (void) showDownloadProgressSheet
{
	[NSApp
	 beginSheet:scriptDownloadPanel
	 modalForWindow:scriptsWindow
	 modalDelegate:self
	 didEndSelector:NULL
	 contextInfo:nil
	 ];
}

- (void) closeDownloadProgressSheet
{
	[scriptDownloadPanel orderOut:nil];
	[NSApp endSheet:scriptDownloadPanel];
}


- (IBAction) cancelDownloadSelected:(id)sender
{
	[self.scriptDownloadConnection cancel];
	self.scriptDownloadConnection = nil;
	self.downloadedScriptData = nil;
	self.downloadedScriptCatalogInfo = nil;
	[scriptDownloadProgressIndicator stopAnimation:self];
	[downloadInfoField setStringValue:@""];
	
	NSRunAlertPanel(@"Download canceled",
					@"The script download has been canceled.",
					@"OK", nil,nil);
	
	[self closeDownloadProgressSheet];
}

- (IBAction) reloadRepoButtonSelected:(id)sender
{
	[self loadCatalogFromServer];
}






#pragma mark -
#pragma mark Adding new Front App Scripts

- (BOOL) addScriptForAppID:(NSString *)appID
				   appName:(NSString *)appName
			withScriptData:(NSData *)scriptData
	replacingWithoutAsking:(BOOL)replaceWithoutAsking
{
	[mainController ensureScriptsCatalogFileExists];
	
	// read existing catalog file
	NSString *catalogFilePath = [mainController.scriptsDirPath stringByAppendingPathComponent:SCRIPTS_CATALOG_FILENAME];
	NSMutableDictionary *catalog = [NSMutableDictionary dictionaryWithContentsOfFile:catalogFilePath];
	
	// check for app ID overlap
	BOOL deleteExisting = NO;
	if ([[catalog allKeys] containsObject:appID])
	{
		if (replaceWithoutAsking)
			deleteExisting = YES;
		else
		{
			NSInteger choice = NSRunAlertPanel([NSString
												stringWithFormat:
												@"Script for %@ already exists",
												appName],
											   [NSString
												stringWithFormat:
												@"You already have a script set up for %@. Do you want to replace the existing script with this one?",
												appName],
											   @"Don't replace",
											   @"Cancel",
											   @"Replace"
											   );
			
			if (choice == NSAlertDefaultReturn) // Don't replace
				return YES;
			else if (choice == NSAlertAlternateReturn) // Cancel
				return NO;
			else if (choice == NSAlertOtherReturn) // Replace
				deleteExisting = YES;
		}
	}
	
	if (deleteExisting)
	{
		NSString *existingScriptFileName = [catalog objectForKey:appID];
		NSString *existingScriptPath = [mainController.scriptsDirPath
										stringByAppendingPathComponent:existingScriptFileName];
		if ([[NSFileManager defaultManager] fileExistsAtPath:existingScriptPath])
			moveFileToTrash(existingScriptPath);
	}
	
	NSString *newScriptFileName = [appID stringByAppendingPathExtension:@"scpt"];
	NSString *newScriptPath = [mainController.scriptsDirPath stringByAppendingPathComponent:newScriptFileName];
	
	// write to file
	BOOL scriptWriteSuccess = [scriptData writeToFile:newScriptPath atomically:YES];
	if (!scriptWriteSuccess)
	{
		NSRunAlertPanel(@"Error writing script file",
						@"There was an error while writing the script file into the Front Application Scripts folder.",
						@"OK",
						nil,
						nil);
		return YES;
	}
	
	// set the catalog entry and write the catalog file
	[catalog setObject:newScriptFileName forKey:appID];
	BOOL catalogWriteSuccess = [catalog writeToFile:catalogFilePath atomically:YES];
	if (!catalogWriteSuccess)
	{
		NSRunAlertPanel(@"Error writing script catalog file",
						@"There was an error while writing the script catalog file into the Front Application Scripts folder.",
						@"OK",
						nil,
						nil);
		return YES;
	}
	
	mainController.scriptsCatalog = catalog;
	
	NSRunInformationalAlertPanel(@"Script Added",
								 [NSString
								  stringWithFormat:
								  @"The script has successfully been added for application %@.",
								  appName],
								 @"OK",
								 nil,
								 nil);
	[self updateInstalledScripts];
	return YES;
}


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
	
	NSData *scriptData = [NSData dataWithContentsOfFile:self.addedScriptPath];
	
	NSString *appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
	
	BOOL shouldCloseDialog = [self
							  addScriptForAppID:appID
							  appName:appName
							  withScriptData:scriptData
							  replacingWithoutAsking:NO];
	if (shouldCloseDialog)
	{
		self.addedScriptPath = nil;
		[self closeAddScriptDialog];
	}
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
# pragma mark Window drag & drop

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>)sender
{
	return [mainController draggingEntered:sender];
}

- (BOOL) prepareForDragOperation:(id < NSDraggingInfo >)sender
{
	return [mainController prepareForDragOperation:sender];
}

- (BOOL) performDragOperation:(id < NSDraggingInfo >)sender
{
	return [mainController performDragOperation:sender];
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
		[self updateSelectedScriptInfo];
	}
}


@end
