
#import "HGVersionNumberCompare.h"


// helper method: compare three-part version number strings (e.g. "1.0.13")
NSComparisonResult versionNumberCompare(NSString *first, NSString *second)
{
	if (first != nil && second != nil)
	{
		int i;
		
		NSMutableArray *firstComponents = [NSMutableArray arrayWithCapacity:3];
		[firstComponents addObjectsFromArray:[first componentsSeparatedByString:@"."]];
		
		NSMutableArray *secondComponents = [NSMutableArray arrayWithCapacity:3];
		[secondComponents addObjectsFromArray:[second componentsSeparatedByString:@"."]];
		
		if ([firstComponents count] != [secondComponents count])
		{
			NSMutableArray *shorter;
			NSMutableArray *longer;
			if ([firstComponents count] > [secondComponents count])
			{
				shorter = secondComponents;
				longer = firstComponents;
			}
			else
			{
				shorter = firstComponents;
				longer = secondComponents;
			}
			
			NSUInteger countDiff = [longer count] - [shorter count];
			
			for (i = 0; i < countDiff; i++)
				[shorter addObject:@"0"];
		}
		
		for (i = 0; i < [firstComponents count]; i++)
		{
			int firstComponentIntVal = [[firstComponents objectAtIndex:i] intValue];
			int secondComponentIntVal = [[secondComponents objectAtIndex:i] intValue];
			if (firstComponentIntVal < secondComponentIntVal)
				return NSOrderedAscending;
			else if (firstComponentIntVal > secondComponentIntVal)
				return NSOrderedDescending;
		}
		return NSOrderedSame;
	}
	else
		return NSOrderedSame;
}
