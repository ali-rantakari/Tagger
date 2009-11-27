
//#define _BENCHMARKING

#ifdef _BENCHMARKING
#define BENCH_START(varName)			NSTimeInterval (varName) = [NSDate timeIntervalSinceReferenceDate]
#define BENCH_END(varName)				NSLog(@"Benchmark: took %.7f s", ([NSDate timeIntervalSinceReferenceDate]-(varName)))
#define BENCH_END_F(varName, formatStr)	NSLog((formatStr), ([NSDate timeIntervalSinceReferenceDate]-(varName)))
#else
#define BENCH_START(varName)			
#define BENCH_END(varName)				
#define BENCH_END_F(varName, formatStr)	
#endif


#define kTigerOSVersion			100400
#define kLeopardOSVersion		100500
#define kSnowLeopardOSVersion	100600
NSInteger OSVersion();

NSString *appVersionString();

NSString* boolStr(BOOL value);

NSRect rectForStringDrawing(NSString *aString, NSFont *aFont, CGFloat maxWidth);

NSString *stringFromBytes(CGFloat aSize);

NSImage *blankFileIcon();

NSUInteger linesInString(NSString *str);

BOOL moveFileToTrash(NSString *filePath);
