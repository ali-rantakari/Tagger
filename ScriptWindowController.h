//
//  ScriptWindowController.h
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

#import <Cocoa/Cocoa.h>
#import "TaggerController.h"


@interface ScriptWindowController : NSObject
{
	IBOutlet TaggerController *mainController;
	IBOutlet NSWindow *scriptsWindow;
	IBOutlet NSTabView *mainTabView;
	
	IBOutlet NSTableView *installedScriptsTable;
	IBOutlet NSButton *uninstallButton;
	
	IBOutlet NSTableView *repoScriptsTable;
	IBOutlet NSProgressIndicator *repoScriptsProgressIndicator;
	IBOutlet NSButton *reloadRepoButton;
	IBOutlet NSTextField *scriptInfoTitleField;
	IBOutlet NSTextView *scriptInfoField;
	IBOutlet NSButton *installButton;
	IBOutlet NSTextField *youAlreadyHaveThisInfoField;
	
	IBOutlet NSWindow *addScriptSheet;
	IBOutlet NSTextField *appIDField;
	IBOutlet NSTextField *scriptFilenameField;
	
	IBOutlet NSWindow *scriptDownloadPanel;
	IBOutlet NSProgressIndicator *scriptDownloadProgressIndicator;
	IBOutlet NSButton *scriptDownloadCancelButton;
	IBOutlet NSTextField *downloadInfoField;
	
	NSMutableArray *installedScripts;
	NSMutableArray *repoScripts;
	NSURLConnection *loadCatalogConnection;
	NSMutableData *catalogData;
	
	NSString *addedScriptPath;
	
	NSURLConnection *scriptDownloadConnection;
	NSMutableData *downloadedScriptData;
	NSDictionary *downloadedScriptCatalogInfo;
	
	BOOL installedScriptsUpdatedAtLeastOnce;
	BOOL catalogLoadedAtLeastOnce;
	BOOL replaceDownloadedScriptWithoutAsking;
}

@property(retain) NSMutableArray *installedScripts;
@property(retain) NSMutableArray *repoScripts;
@property(retain) NSURLConnection *loadCatalogConnection;
@property(retain) NSMutableData *catalogData;
@property(copy) NSString *addedScriptPath;
@property(retain) NSURLConnection *scriptDownloadConnection;
@property(retain) NSMutableData *downloadedScriptData;
@property(copy) NSDictionary *downloadedScriptCatalogInfo;

- (void) updateInstalledScripts;

- (BOOL) scriptExistsWithHash:(NSString *)hash
					 forAppID:(NSString *)appID;

- (BOOL) addScriptForAppID:(NSString *)appID
				   appName:(NSString *)appName
			withScriptData:(NSData *)scriptData
	replacingWithoutAsking:(BOOL)replaceWithoutAsking;

- (void) suggestAddFrontAppScript:(NSString *)filePath;

- (IBAction) uninstallButtonSelected:(id)sender;
- (IBAction) installButtonSelected:(id)sender;
- (IBAction) reloadRepoButtonSelected:(id)sender;

- (IBAction) cancelDownloadSelected:(id)sender;

- (void) showDownloadProgressSheet;
- (void) closeDownloadProgressSheet;

- (IBAction) addScriptSheetSubmit:(id)sender;
- (IBAction) addScriptSheetCancel:(id)sender;

@end
