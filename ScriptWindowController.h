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
	IBOutlet NSTextField *scriptInfoField;
	IBOutlet NSButton *installButton;
	
	IBOutlet NSWindow *addScriptSheet;
	IBOutlet NSTextField *appIDField;
	IBOutlet NSTextField *scriptFilenameField;
	
	NSMutableArray *installedScripts;
	NSMutableArray *repoScripts;
	NSURLConnection *loadCatalogConnection;
	NSMutableData *catalogData;
	
	NSString *addedScriptPath;
	
	BOOL installedScriptsUpdatedAtLeastOnce;
	BOOL catalogLoadedAtLeastOnce;
}

@property(retain) NSMutableArray *installedScripts;
@property(retain) NSMutableArray *repoScripts;
@property(retain) NSURLConnection *loadCatalogConnection;
@property(retain) NSMutableData *catalogData;
@property(copy) NSString *addedScriptPath;

- (void) updateInstalledScripts;

- (void) suggestAddFrontAppScript:(NSString *)filePath;

- (IBAction) uninstallButtonSelected:(id)sender;
- (IBAction) installButtonSelected:(id)sender;
- (IBAction) reloadRepoButtonSelected:(id)sender;

- (IBAction) addScriptSheetSubmit:(id)sender;
- (IBAction) addScriptSheetCancel:(id)sender;

@end
