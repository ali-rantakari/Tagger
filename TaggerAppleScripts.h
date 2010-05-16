//
//  TaggerAppleScripts.h
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


#define FINDER_BUNDLE_ID		@"com.apple.finder"
#define MAIL_BUNDLE_ID			@"com.apple.mail"
#define SAFARI_BUNDLE_ID		@"com.apple.Safari"
#define FIREFOX_BUNDLE_ID		@"org.mozilla.firefox"
#define CAMINO_BUNDLE_ID		@"org.mozilla.camino"
#define OPERA_BUNDLE_ID			@"com.operasoftware.Opera"
#define OMNIWEB_BUNDLE_ID		@"com.omnigroup.OmniWeb5"
#define PATH_FINDER_BUNDLE_ID	@"com.cocoatech.PathFinder"
#define TAGLISTS_BUNDLE_ID		@"org.hasseg.TagLists"


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
	@"tell application \"Opera\" to return name of front document as string"
#define GET_CURRENT_OPERA_PAGE_URL_APPLESCRIPT \
	@"tell application \"Opera\" to return URL of front document as string"

#define GET_CURRENT_OMNIWEB_PAGE_TITLE_APPLESCRIPT \
	@"tell application \"OmniWeb\" to return title of active tab of front browser"
#define GET_CURRENT_OMNIWEB_PAGE_URL_APPLESCRIPT \
	@"tell application \"OmniWeb\" to return address of active tab of front browser"

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

#define TAGLISTS_GET_SELECTED_FILES_APPLESCRIPT \
	@"tell application \"TagLists\" to return selection"
