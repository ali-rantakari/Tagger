//
//  TaggerOMImporterInstallController.h
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
#import "TaggerDefines.h"

@interface TaggerOMImporterInstallController : NSObject
{
	IBOutlet NSWindow *installDialog;
	IBOutlet NSButton *meOnlyButton;
	IBOutlet NSButton *allUsersButton;
	IBOutlet NSButton *cancelButton;
	IBOutlet NSTextField *infoTextField;
	
	NSAttributedString *dialogText_AlreadyInstalled;
	NSAttributedString *dialogText_Default;
}

@property(retain) NSAttributedString *dialogText_AlreadyInstalled;
@property(retain) NSAttributedString *dialogText_Default;

+ (BOOL) isOpenMetaSpotlightImporterInstalled:(NSString **)installedPath;
+ (NSString *) runTaskWithPath:(NSString *)path withArgs:(NSArray *)args;

- (IBAction) meOnlyButtonSelected:(id)sender;
- (IBAction) allUsersButtonSelected:(id)sender;
- (IBAction) cancelButtonSelected:(id)sender;

- (void) beginInstallationToPath:(NSString *)installPath;

- (void) setControlsEnabled:(BOOL)state;
- (void) removeSelfSheet;

@end
