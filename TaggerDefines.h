//
//  TaggerDefines.h
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


#define kDefaults											[NSUserDefaults standardUserDefaults]
#define kDefaultsKey_OMSpotlightImporterInstallCheckDone	@"OMSpotlightImporterInstallCheckDone"
#define kDefaultsKey_SaveChangesOnDoubleReturn				@"saveChangesOnDoubleReturn"

#ifdef _DEBUG_TARGET
#define DEBUG_LEVEL 4
#else
#define DEBUG_LEVEL 0
#endif

#define DEBUG_ERROR   (DEBUG_LEVEL >= 1)
#define DEBUG_WARN    (DEBUG_LEVEL >= 2)
#define DEBUG_INFO    (DEBUG_LEVEL >= 3)
#define DEBUG_VERBOSE (DEBUG_LEVEL >= 4)

#define DDLogError(format, ...)		if(DEBUG_ERROR)   \
										NSLog((format), ##__VA_ARGS__)
#define DDLogWarn(format, ...)		if(DEBUG_WARN)    \
										NSLog((format), ##__VA_ARGS__)
#define DDLogInfo(format, ...)		if(DEBUG_INFO)    \
										NSLog((format), ##__VA_ARGS__)
#define DDLogVerbose(format, ...)	if(DEBUG_VERBOSE) \
										NSLog((format), ##__VA_ARGS__)


