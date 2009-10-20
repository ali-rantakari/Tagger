//
//  TaggerOMImporterInstallController.m
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

#import "TaggerOMImporterInstallController.h"

#define SPOTLIGHT_LIB_PATH_USER			[@"~/Library/Spotlight/" stringByExpandingTildeInPath]
#define SPOTLIGHT_LIB_PATH_ALL_USERS	@"/Library/Spotlight/"
#define IMPORTER_PATH					[[NSBundle bundleForClass:[self class]] pathForResource:@"OpenMetaSpotlight" ofType:@"mdimporter"]
#define OM_IMPORTER_FILENAME			@"OpenMetaSpotlight.mdimporter"


@implementation TaggerOMImporterInstallController

@synthesize dialogText_AlreadyInstalled;
@synthesize dialogText_Default;

+ (BOOL) isOpenMetaSpotlightImporterInstalled:(NSString **)installedPath
{
	// check the standard paths
	NSString *userInstallPath = [SPOTLIGHT_LIB_PATH_USER stringByAppendingPathComponent:OM_IMPORTER_FILENAME];
	NSString *allUsersInstallPath = [SPOTLIGHT_LIB_PATH_ALL_USERS stringByAppendingPathComponent:OM_IMPORTER_FILENAME];
	
	BOOL exists = NO;
	
	exists = [[NSFileManager defaultManager]
			  fileExistsAtPath:userInstallPath
			  ];
	if (exists)
	{
		if (installedPath != NULL)
			*installedPath = userInstallPath;
		return YES;
	}
	
	exists = [[NSFileManager defaultManager]
			  fileExistsAtPath:allUsersInstallPath
			  ];
	if (exists)
	{
		if (installedPath != NULL)
			*installedPath = allUsersInstallPath;
		return YES;
	}
	
	// ask mdimport for list of installed importers
	NSString *output = [self
						runTaskWithPath:@"/bin/bash"
						withArgs:[NSArray
								  arrayWithObjects:
									@"-c",
									@"/usr/bin/mdimport -L 2>&1 | grep OpenMetaSpotlight.mdimporter | sed -e 's/[\",]//g'",
									nil
								  ]
						];
	NSRange foundRange = [output rangeOfString:OM_IMPORTER_FILENAME];
	if (foundRange.location != NSNotFound)
	{
		if (installedPath != NULL)
			*installedPath = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		return YES;
	}
	
	return NO;
}

+ (NSString *) runTaskWithPath:(NSString *)path withArgs:(NSArray *)args
{
	NSPipe *pipe;
	pipe = [NSPipe pipe];
	
	NSTask *task;
	task = [[NSTask alloc] init];
	[task setLaunchPath: path];
	[task setArguments: args];
	[task setStandardOutput: pipe];
	[task setStandardError: pipe];
	
	NSFileHandle *file;
	file = [pipe fileHandleForReading];
	
	[task launch];
	
	NSData *data;
	data = [file readDataToEndOfFile];
	
	NSString *string;
	string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
	
	[task release];
	
	return string;
}



- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	self.dialogText_Default = [[[NSAttributedString alloc]
								initWithString:@"In order to enable the feature of searching for files in Spotlight by their tags (like \"tag:todo\") Tagger needs to install a Spotlight importer for the OpenMeta tags.\n\nYou can choose to install this support for the current user (you) only, or for the whole system (all users)."
								] autorelease];
	self.dialogText_AlreadyInstalled = [[NSMutableAttributedString alloc] initWithAttributedString:self.dialogText_Default];
	[(NSMutableAttributedString*)self.dialogText_AlreadyInstalled appendAttributedString:[[[NSAttributedString alloc]
																						   initWithString:@"\n\n"]
																						  autorelease]
	];
	NSAttributedString *alreadyInstalledNote = [[[NSAttributedString alloc]
												 initWithString:@"NOTE: The Spotlight importer has already been installed onto this system."
												 attributes:[NSDictionary
															 dictionaryWithObjectsAndKeys:
															 [NSColor colorWithCalibratedRed:0.0 green:0.4 blue:0.0 alpha:1.0],
															 NSForegroundColorAttributeName,
															 [NSColor colorWithCalibratedRed:0.9 green:1.0 blue:0.9 alpha:1.0],
															 NSBackgroundColorAttributeName,
															 nil
															 ]
												 ] autorelease];
	[(NSMutableAttributedString*)self.dialogText_AlreadyInstalled appendAttributedString:alreadyInstalledNote];
	
	return self;
}

- (void) dealloc
{
	self.dialogText_Default = nil;
	self.dialogText_AlreadyInstalled = nil;
	[super dealloc];
}



- (void) awakeFromNib
{
	[infoTextField
	 setAttributedStringValue:
		[[self class] isOpenMetaSpotlightImporterInstalled:NULL]
		?self.dialogText_AlreadyInstalled
		:self.dialogText_Default
	 ];
}


- (IBAction) meOnlyButtonSelected:(id)sender
{
	[self setControlsEnabled:NO];
	[self beginInstallationToPath:SPOTLIGHT_LIB_PATH_USER];
}

- (IBAction) allUsersButtonSelected:(id)sender
{
	[self setControlsEnabled:NO];
	[self beginInstallationToPath:SPOTLIGHT_LIB_PATH_ALL_USERS];
}

- (IBAction) cancelButtonSelected:(id)sender
{
	[self removeSelfSheet];
}



- (void) beginInstallationToPath:(NSString *)installPath
{
	NSString *installedPath = nil;
	if ([[self class] isOpenMetaSpotlightImporterInstalled:&installedPath])
	{
		NSAlert *alert = [NSAlert
						  alertWithMessageText:@"Spotlight Importer Already Installed"
						  defaultButton:@"Don't install"
						  alternateButton:@"Install anyway"
						  otherButton:nil
						  informativeTextWithFormat:
							@"It seems the Spotlight importer for OpenMeta tags is already installed at: %@\n\nDo you still want to proceed with the installation?",
							installedPath
						  ];
		NSInteger ret = [alert runModal];
		if (ret == NSAlertDefaultReturn)
		{
			[self removeSelfSheet];
			return;
		}
	}
	
	BOOL isDir = NO;
	BOOL installPathExists = [[NSFileManager defaultManager] fileExistsAtPath:installPath isDirectory:&isDir];
	
	if (installPathExists && !isDir)
	{
		NSAlert *alert = [NSAlert
						  alertWithMessageText:@"Error Installing Spotlight Importer"
						  defaultButton:@"Ok"
						  alternateButton:nil
						  otherButton:nil
						  informativeTextWithFormat:
						  @"Can not install the Spotlight importer for OpenMeta tags: there seems to be a file where the installation directory should be: %@",
						  installPath
						  ];
		[alert runModal];
		[self removeSelfSheet];
		return;
	}
	else if (!installPathExists)
	{
		NSError *createDirError = nil;
		BOOL success = [[NSFileManager defaultManager]
						createDirectoryAtPath:installPath
						withIntermediateDirectories:YES
						attributes:nil
						error:&createDirError
						];
		if (!success || createDirError != nil)
		{
			NSString *infoText = 
				(createDirError != nil)
				? [NSString stringWithFormat:@"Can not install the Spotlight importer for OpenMeta tags: \"%@\"", [createDirError localizedDescription]]
				: @"Can not install the Spotlight importer for OpenMeta tags: unknown error";
			
			NSAlert *alert = [NSAlert
							  alertWithMessageText:@"Error Installing Spotlight Importer"
							  defaultButton:@"Ok"
							  alternateButton:nil
							  otherButton:nil
							  informativeTextWithFormat:infoText
							  ];
			[alert runModal];
			[self removeSelfSheet];
			return;
		}
	}
	
	// ----------------
	// start installing
	
	NSString *copyTargetPath = IMPORTER_PATH;
	NSString *importerFileName = [copyTargetPath lastPathComponent];
	NSString *copyDestinationPath = [installPath stringByAppendingPathComponent:importerFileName];
	DDLogInfo(@"copyTargetPath = '%@'", copyTargetPath);
	DDLogInfo(@"copyDestinationPath = '%@'", copyDestinationPath);
	
	NSError *copyError = nil;
	BOOL copySuccess = [[NSFileManager defaultManager]
						copyItemAtPath:copyTargetPath
						toPath:copyDestinationPath
						error:&copyError
						];
	if (!copySuccess || copyError != nil)
	{
		NSString *infoText = 
			(copyError != nil)
			? [NSString stringWithFormat:@"Can not install the Spotlight importer for OpenMeta tags: error occurred while copying importer bundle: \"%@\"", [copyError localizedDescription]]
			: @"Can not install the Spotlight importer for OpenMeta tags: unknown error while copying importer bundle";
		
		NSAlert *alert = [NSAlert
						  alertWithMessageText:@"Error Installing Spotlight Importer"
						  defaultButton:@"Ok"
						  alternateButton:nil
						  otherButton:nil
						  informativeTextWithFormat:infoText
						  ];
		[alert runModal];
		[self removeSelfSheet];
		return;
	}
	
	// ask mds (via mdimport) to reindex everything this importer supports
	[[self class]
	 runTaskWithPath:@"/usr/bin/mdimport"
	 withArgs:[NSArray
			   arrayWithObjects:
				@"-r",
				copyDestinationPath,
				nil
			   ]
	 ];
	
	NSAlert *alert = [NSAlert
					  alertWithMessageText:@"Spotlight Importer Successfully Installed"
					  defaultButton:@"Ok"
					  alternateButton:nil
					  otherButton:nil
					  informativeTextWithFormat:@"The Spotlight importer for OpenMeta tags has successfully been installed. You may need to restart your system before it can start working."
					  ];
	[alert runModal];
	[self removeSelfSheet];
	[infoTextField setAttributedStringValue:self.dialogText_AlreadyInstalled];
}


- (void) setControlsEnabled:(BOOL)state
{
	[meOnlyButton setEnabled:state];
	[allUsersButton setEnabled:state];
	[cancelButton setEnabled:state];
}

- (void) removeSelfSheet
{
	[installDialog orderOut:nil];
	[NSApp endSheet:installDialog];
	[self setControlsEnabled:YES];
}


@end
