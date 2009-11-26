
#import "HGUtils.h"


NSString *appVersionString()
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
}


NSInteger OSVersion()
{
	static NSInteger cachedValue = 0;
	
	if (cachedValue > 0)
		return cachedValue;
	
	SInt32 major, minor, bugfix;
	
	if (Gestalt(gestaltSystemVersionMajor, &major) ||
		Gestalt(gestaltSystemVersionMinor, &minor) ||
		Gestalt(gestaltSystemVersionBugFix, &bugfix))
		return 0;
	
	cachedValue = ((major * 100) + minor) * 100 + bugfix;
	return cachedValue;
}


NSString* boolStr(BOOL value)
{
	return (value) ? @"YES" : @"NO";
}


NSRect rectForStringDrawing(NSString *aString, NSFont *aFont, CGFloat maxWidth)
{
	CGFloat width = (maxWidth <= 0) ? FLT_MAX : maxWidth;
	
	static NSTextStorage *textStorage = nil;
	static NSTextContainer *textContainer = nil;
	static NSLayoutManager *layoutManager = nil;
	
	BOOL cacheIsCold = (textStorage == nil);
	
	if (textStorage == nil)
		textStorage = [[NSTextStorage alloc] initWithString:aString];
	else
		[textStorage
		 replaceCharactersInRange:NSMakeRange(0, [textStorage length])
		 withString:aString];
	
	if (textContainer == nil)
		textContainer = [[NSTextContainer alloc]
						 initWithContainerSize:NSMakeSize(width, FLT_MAX)];
	else
		[textContainer setContainerSize:NSMakeSize(width, FLT_MAX)];
	
	if (layoutManager == nil)
		layoutManager = [[NSLayoutManager alloc] init];
	
	if (cacheIsCold)
	{
		[layoutManager addTextContainer:textContainer];
		[textStorage addLayoutManager:layoutManager];
	}
	
	[textStorage addAttribute:NSFontAttributeName
						value:aFont
						range:NSMakeRange(0, [textStorage length])];
	[textContainer setLineFragmentPadding:0.0];
	
	(void) [layoutManager glyphRangeForTextContainer:textContainer];
	return [layoutManager usedRectForTextContainer:textContainer];
}


NSString *stringFromBytes(CGFloat aSize)
{
    CGFloat size = aSize;
	
	// Finder uses SI prefixes on Snow Leopard and the IEC 60027-2
	// binary prefixes on earlier OS X versions for file sizes
	// and disk capacities so we'll do the same here.
	// 
	CGFloat kilo = (OSVersion() >= kSnowLeopardOSVersion) ? 1000.0 : 1024.0;
	NSString *bytesSuffix = (kilo == 1000.0) ? @"B" : @"iB";
	
    if (size < kilo)
        return([NSString stringWithFormat:@"%1.0f bytes",size]);
    size = size / kilo;
    if (size < kilo)
        return([NSString stringWithFormat:@"%1.1f K%@",size,bytesSuffix]);
    size = size / kilo;
    if (size < kilo)
        return([NSString stringWithFormat:@"%1.1f M%@",size,bytesSuffix]);
    size = size / kilo;
    if (size < kilo)
        return([NSString stringWithFormat:@"%1.1f G%@",size,bytesSuffix]);
    size = size / kilo;
	
    return([NSString stringWithFormat:@"%1.1f T%@",size,bytesSuffix]);
}



NSImage *blankFileIcon()
{
	static NSImage *cachedBlankFileIcon = nil;
	if (cachedBlankFileIcon == nil)
		cachedBlankFileIcon = [[NSWorkspace sharedWorkspace] iconForFileType:nil];
	
	return cachedBlankFileIcon;
}



NSUInteger linesInString(NSString *str)
{
	NSUInteger thisLineNum = 1;
	NSRange searchRange = NSMakeRange(0, [str length]);
	NSRange foundRange = NSMakeRange(NSNotFound, 0);
	do
	{
		foundRange = [str rangeOfString:@"\n" options:NSLiteralSearch range:searchRange];
		if (foundRange.location != NSNotFound)
			thisLineNum++;
		searchRange = NSMakeRange(NSMaxRange(foundRange),
								  NSMaxRange(searchRange) - NSMaxRange(foundRange)
								  );
	}
	while (foundRange.location != NSNotFound);
	
	return thisLineNum;
}





