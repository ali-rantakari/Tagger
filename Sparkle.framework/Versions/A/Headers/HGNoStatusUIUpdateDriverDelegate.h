
@interface NSObject (HGNoStatusUIUpdateDriverDelegateInformalProtocol)

- (void)updateDriverWillStartDownloadingUpdate;
- (void)updateDriverDidReceiveExpectedDownloadLength:(double)length;
- (void)updateDriverDidDownloadDataOfLength:(double)length;

- (void)updateDriverWillStartExtractingUpdate;
- (void)updateDriverDidReceiveExpectedExtractionLength:(double)length;
- (void)updateDriverDidExtractDataOfLength:(double)length;

- (void)updateDriverReadyToInstallUpdateWithInvocation:(NSInvocation *)invocation;
- (void)updateDriverWillStartInstallingUpdate;

- (void)updateDriverDidAbortUpdate;

@end
