#import "Report.h"
#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"
#import "NotificationRecordingObserver.h"
#import "ReportStore.h"
#import "ReportType.h"
#import "TestReportType.h"
#import "DICEUtiExpert.h"


@interface ReportStoreSpec_FileManager : NSFileManager

@property NSURL *reportsDir;
@property NSMutableArray<NSString *> *baseNamesInReportsDir;

- (void)setReportsDirContentsBaseNames:(NSString *)baseName, ... NS_REQUIRES_NIL_TERMINATION;

@end

@implementation ReportStoreSpec_FileManager

- (instancetype)init
{
    self = [super init];
    self.baseNamesInReportsDir = [NSMutableArray array];
    return self;
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
    NSArray *reportsDirParts = [self.reportsDir pathComponents];
    NSArray *pathParts = [path.pathComponents subarrayWithRange:NSMakeRange(0, reportsDirParts.count)];
    return [self.baseNamesInReportsDir containsObject:path.lastPathComponent] &&
        [pathParts isEqualToArray:reportsDirParts];
}

- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSString *> *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error
{
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:self.baseNamesInReportsDir.count];
    for (NSString *baseName in self.baseNamesInReportsDir) {
        [files addObject:[self.reportsDir URLByAppendingPathComponent:baseName]];
    }
    return files;
}

- (void)setReportsDirContentsBaseNames:(NSString *)baseName, ...
{
    [self.baseNamesInReportsDir removeAllObjects];
    if (baseName == nil) {
        return;
    }
    va_list args;
    va_start(args, baseName);
    for(NSString *arg = baseName; arg != nil; arg = va_arg(args, NSString *)) {
        [self.baseNamesInReportsDir addObject:arg];
    }
    va_end(args);
}


@end

/**
 This category enables the OCHamcrest endsWith matcher to accept
 NSURL objects.
 */
@interface NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix;

@end

@implementation NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix
{
    return [self.path hasSuffix:suffix];
}

@end


SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block ReportStoreSpec_FileManager *fileManager;
    __block id<DICEArchiveFactory> archiveFactory;
    __block NSOperationQueue *importQueue;
    __block ReportStore *store;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = [[ReportStoreSpec_FileManager alloc] init];
        fileManager.reportsDir = reportsDir;
        archiveFactory = mockProtocol(@protocol(DICEArchiveFactory));
        importQueue = [[NSOperationQueue alloc] init];

        redType = [[TestReportType alloc] initWithExtension:@"red"];
        blueType = [[TestReportType alloc] initWithExtension:@"blue"];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager archiveFactory:archiveFactory utiExpert:[[DICEUtiExpert alloc] init] importQueue:importQueue];
        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        fileManager = nil;
    });

    afterAll(^{
        
    });

    describe(@"loadReports", ^{

        beforeEach(^{
        });

        it(@"creates reports for each file in reports directory", ^{
            [fileManager setReportsDirContentsBaseNames:@"report1.red", @"report2.blue", @"something.else", nil];

            id redImport = [redType enqueueImport];
            id blueImport = [blueType enqueueImport];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(3);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(((Report *)reports[2]).url).to.equal([reportsDir URLByAppendingPathComponent:@"something.else"]);

            assertWithTimeout(1.0, thatEventually(@([redImport isFinished] && [blueImport isFinished])), isTrue());
        });

        it(@"removes reports with path that does not exist and are not importing", ^{
            [fileManager setReportsDirContentsBaseNames:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = redType.enqueueImport;
            TestImportProcess *blueImport = blueType.enqueueImport;

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(redImport.isFinished && blueImport.isFinished)), isTrue());

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [fileManager setReportsDirContentsBaseNames:@"report2.blue", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves imported and importing reports in order of discovery", ^{

            [fileManager setReportsDirContentsBaseNames:@"report1.red", @"report2.blue", @"report3.red", nil];

            TestImportProcess *blueImport = [blueType.enqueueImport block];
            TestImportProcess *redImport1 = [redType enqueueImport];
            TestImportProcess *redImport2 = [redType enqueueImport];

            NSArray<Report *> *reports1 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports1.count).to.equal(3);
            expect(reports1[0].url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports1[1].url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports1[2].url).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && redImport2.isFinished)), isTrue());

            [fileManager setReportsDirContentsBaseNames:@"report2.blue", @"report3.red", @"report11.red", nil];
            redImport1 = [redType enqueueImport];

            NSArray<Report *> *reports2 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports2.count).to.equal(3);
            expect(reports2[0].url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports2[0]).to.beIdenticalTo(reports1[1]);
            expect(reports2[1].url).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            expect(reports2[1]).to.beIdenticalTo(reports1[2]);
            expect(reports2[2].url).to.equal([reportsDir URLByAppendingPathComponent:@"report11.red"]);
            expect(reports2[2]).notTo.beIdenticalTo(reports1[0]);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && blueImport.isFinished)), isTrue());
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{

            [fileManager setReportsDirContentsBaseNames:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = [redType.enqueueImport block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSArray<Report *> *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            assertWithTimeout(1.0, thatEventually(@(blueImport.isFinished)), isTrue());

            expect([reports[0] isEnabled]).to.equal(NO);
            expect([reports[1] isEnabled]).to.equal(YES);

            Report *redReport = redImport.report;
            redReport.url = [reportsDir URLByAppendingPathComponent:@"report1.transformed"];

            [fileManager setReportsDirContentsBaseNames:@"report1.transformed", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports.firstObject).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)reports.firstObject).isEnabled).to.equal(NO);

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.isFinished)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(((Report *)store.reports.firstObject).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)store.reports.firstObject).isEnabled).to.equal(YES);
        });

        it(@"sends notifications about added reports", ^{

            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            [fileManager setReportsDirContentsBaseNames:@"report1.red", @"report2.blue", nil];

            [redType.enqueueImport cancelAll];
            [blueType.enqueueImport cancelAll];

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(2));

            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = [obj notification];
                Report *report = note.userInfo[@"report"];

                expect(note.name).to.equal([ReportNotification reportAdded]);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];

            [notifications removeObserver:observer];
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{

            TestImportProcess *redImport = redType.enqueueImport;

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.isFinished)), isTrue());
            expect(redImport).toNot.beNil;
        });

        it(@"returns a report even if the url cannot be imported", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).notTo.beNil;
            expect(report.url).to.equal(url);
        });

        it(@"assigns an error message if the report type was unknown", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(report.error), isNot(nilValue()));
        });

        it(@"adds the initial report to the report list", ^{
            TestImportProcess *import = [redType.enqueueImport block];

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.beNil;
            expect(report.title).to.equal(report.url.lastPathComponent);
            expect(report.summary).to.equal(@"Importing...");
            expect(report.error).to.beNil;
            expect(report.isEnabled).to.equal(NO);

            [import unblock];

            [importQueue waitUntilAllOperationsAreFinished];
        });

        it(@"sends a notification about adding the report", ^{
            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            redType.enqueueImport;

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            Report *receivedReport = received.notification.userInfo[@"report"];

            expect(received.notification.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);

            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file it is already importing", ^{
            TestImportProcess *import = [redType.enqueueImport block];

            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [store attemptToImportReportFromResource:reportUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(report);
            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);
            expect(store.reports.count).to.equal(1);

            notificationReport = nil;
            [observer.received removeAllObjects];

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(sameReport).to.beIdenticalTo(report);
            expect(store.reports.count).to.equal(1);
            expect(observer.received.count).to.equal(0);

            [notifications removeObserver:observer];
        });

        it(@"enables the report when the import finishes", ^{
            Report *report = mock([Report class]);
            TestImportProcess *import = [[TestImportProcess alloc] initWithReport:report];

            __block BOOL enabledOnMainThread = NO;
            [givenVoid([report setIsEnabled:YES]) willDo:^id(NSInvocation *invocation) {
                BOOL enabled = NO;
                [invocation getArgument:&enabled atIndex:2];
                enabledOnMainThread = enabled && [NSThread isMainThread];
                return nil;
            }];

            [store importDidFinishForImportProcess:import];

            assertWithTimeout(1.0, thatEventually(@(enabledOnMainThread)), isTrue());
        });

        it(@"sends a notification when the import finishes", ^{

            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:nil];

            TestImportProcess *redImport = [redType enqueueImport];
            Report *importReport = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.isFinished)), isTrue());
            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            [notifications removeObserver:observer];

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(importReport);
        });

    });

});

SpecEnd
