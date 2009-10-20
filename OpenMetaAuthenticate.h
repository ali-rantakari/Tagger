//
//  OpenMetaAuthenticate.h
//  leap
//
//  Created by Tom Andersen on 19/05/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OpenMeta.h"


@interface OpenMeta (Authenticated) 

+(NSError*)authenticatedSetXAttr:(id)plistObject forKey:(NSString*)inKeyName path:(NSString*)path;

@end


