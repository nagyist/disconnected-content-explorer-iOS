//
//  UnzipOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 7/31/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import <OCMockito/OCMockito.h>

#import <OCMock/OCMock.h>

#import "UnzipOperation.h"
#import "ZipException.h"
#import "ZipReadStream.h"


@interface BadZipFile : ZipFile

@end

@implementation BadZipFile

- (void)goToFirstFileInZip
{
    @throw [[ZipException alloc] initWithError:99 reason:@"Bad zip file"];
}

@end


@interface SpecificException : NSException

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo;

@end


@interface ThrowException : NSObject

- (void)throwException;

@end


@interface ExceptionTest : NSOperation

@property ThrowException *thrower;
@property NSException *exception;

- (instancetype)initWithThrower:(ThrowException *)thrower;

- (void)catchException;

@end


@implementation ExceptionTest

- (instancetype)initWithThrower:(ThrowException *)thrower
{
    self = [super init];
    _thrower = thrower;
    return self;
}

- (void)main
{
    @autoreleasepool {
        @try {
            [self doIt];
        }
        @catch (SpecificException *exception) {
            self.exception = exception;
        }
        @catch (ZipException *exception) {
            self.exception = exception;
        }
        @catch (NSException *exception) {
            self.exception = exception;
        }
        @finally {
            self.thrower = nil;
        }
    }
}

- (void)catchException
{
    @autoreleasepool {
        @try {
            [self doIt];
        }
        @catch (SpecificException *exception) {
            self.exception = exception;
        }
        @catch (ZipException *exception) {
            self.exception = exception;
        }
        @catch (NSException *exception) {
            self.exception = exception;
        }
        @finally {
            self.thrower = nil;
        }
    }
}

- (void)doIt
{
    [self.thrower throwException];
}

@end


@implementation ThrowException

- (instancetype)init
{
    return (self = [super init]);
}

- (void)throwException
{

}

@end


@implementation SpecificException

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo
{
    return (self = [super initWithName:aName reason:aReason userInfo:aUserInfo]);
}

@end


SpecBegin(UnzipOperation)

describe(@"UnzipOperation", ^{

    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"it throws an exception if zip file is nil", ^{
        __block UnzipOperation *op;

        expect(^{
            op = [[UnzipOperation alloc] initWithZipFile:nil destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        }).to.raiseWithReason(@"IllegalArgumentException", @"zipFile is nil");

        expect(op).to.beNil;
    });

    it(@"is not ready until dest dir is set", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:nil fileManager:[NSFileManager defaultManager]];

        id observer = observer = OCMStrictClassMock([NSObject class]);
        [observer setExpectationOrderMatters:YES];

        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"destDir" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"destDir" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"destDir" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.destDir).to.beNil;

        op.destDir = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);

        [observer stopMocking];
    });

    it(@"is not ready until dependencies are finished", ^{
        ZipFile *zipFile = OCMClassMock([ZipFile class]);
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        NSPredicate *isFinished = [NSPredicate predicateWithFormat:@"finished = YES"];
        [self expectationForPredicate:isFinished evaluatedWithObject:holdup handler:nil];
        [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
            expect(op.ready).to.equal(YES);
        }];

        [(id)zipFile stopMocking];
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:[NSURL URLWithString:@"/tmp/"] fileManager:[NSFileManager defaultManager]];
        UnzipOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.destDir = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.destDir.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change destDir after UnzipOperation has started");

        expect(op.destDir).to.equal([NSURL URLWithString:@"/tmp/"]);

        [(id)mockOp stopMocking];
    });

    it(@"unzips with base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"test_base_dir" ofType:@"zip"];
        ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipFilePath mode:ZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        [op start];

        expect(op.wasSuccessful).to.equal(YES);

        destDir = [destDir URLByAppendingPathComponent:@"test"];

        NSMutableDictionary *expectedContents = [NSMutableDictionary dictionaryWithDictionary:@{
            [destDir URLByAppendingPathComponent:@"100_zero_bytes.dat" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSData *contents = [NSData dataWithContentsOfURL:entry];
                expect(contents.length).to.equal(100);
                for (unsigned char i = 0; i < 100; i++) {
                    expect(*((char *)contents.bytes + i)).to.equal(0);
                }
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"hello.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"Hello, test!\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"empty_dir" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                NSArray *contents = [fm contentsOfDirectoryAtURL:entry includingPropertiesForKeys:nil options:0 error:nil];
                expect(contents.count).to.equal(0);
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1/sub1.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub1\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"sub2" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub2/sub2.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub2\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
        }];

        NSDateComponents *comps = [[NSDateComponents alloc] init];
        [comps setDay:1];
        [comps setMonth:8];
        [comps setYear:2015];
        [comps setHour:12];
        NSDate *modDate = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] dateFromComponents:comps];

        NSDirectoryEnumerator *extractedContents = [fm enumeratorAtURL:destDir
            includingPropertiesForKeys:@[
                NSURLIsDirectoryKey,
                NSURLIsRegularFileKey,
                NSURLContentModificationDateKey,
            ]
            options:0 errorHandler:nil];

        NSArray *allEntries = [extractedContents allObjects];
        expect(allEntries.count).to.equal(expectedContents.count);

        for (NSURL *entry in allEntries) {
            expect([fm fileExistsAtPath:entry.path]).to.equal(YES);

            NSMutableDictionary *attrs = [[fm attributesOfItemAtPath:entry.path error:nil] mutableCopy];
            attrs[@"path"] = entry.path;

            expect(attrs).notTo.beNil;
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil;
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"unzips without base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"test_no_base_dir" ofType:@"zip"];
        ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipFilePath mode:ZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        [op start];

        expect(op.wasSuccessful).to.equal(YES);

        NSMutableDictionary *expectedContents = [NSMutableDictionary dictionaryWithDictionary:@{
            [destDir URLByAppendingPathComponent:@"100_zero_bytes.dat" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSData *contents = [NSData dataWithContentsOfURL:entry];
                expect(contents.length).to.equal(100);
                for (unsigned char i = 0; i < 100; i++) {
                    expect(*((char *)contents.bytes + i)).to.equal(0);
                }
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"hello.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"Hello, test!\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"empty_dir" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                NSArray *contents = [fm contentsOfDirectoryAtURL:entry includingPropertiesForKeys:nil options:0 error:nil];
                expect(contents.count).to.equal(0);
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1/sub1.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub1\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"sub2" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub2/sub2.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub2\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
        }];

        NSDateComponents *comps = [[NSDateComponents alloc] init];
        [comps setDay:1];
        [comps setMonth:8];
        [comps setYear:2015];
        [comps setHour:12];
        NSDate *modDate = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] dateFromComponents:comps];

        NSDirectoryEnumerator *extractedContents = [fm enumeratorAtURL:destDir
            includingPropertiesForKeys:@[
                NSURLIsDirectoryKey,
                NSURLIsRegularFileKey,
                NSURLContentModificationDateKey,
            ]
            options:0 errorHandler:nil];

        NSArray *allEntries = [extractedContents allObjects];
        expect(allEntries.count).to.equal(expectedContents.count);

        for (NSURL *entry in allEntries) {
            expect([fm fileExistsAtPath:entry.path]).to.equal(YES);

            NSMutableDictionary *attrs = [[fm attributesOfItemAtPath:entry.path error:nil] mutableCopy];
            attrs[@"path"] = entry.path;

            expect(attrs).notTo.beNil;
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil;
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"reports unzip progress on the main thread for percentage changes", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"10x128_bytes" ofType:@"zip"];
        ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipFilePath mode:ZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        id<UnzipDelegate> unzipDelegate = OCMProtocolMock(@protocol(UnzipDelegate));
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        op.bufferSize = 64;
        op.delegate = unzipDelegate;

        __block BOOL wasMainThread = YES;
        NSMutableArray *percentUpdates = [NSMutableArray array];
        [[OCMStub([unzipDelegate unzipOperation:op didUpdatePercentComplete:0]) ignoringNonObjectArgs] andDo:^(NSInvocation *invocation) {
            wasMainThread = wasMainThread && [NSThread currentThread] == [NSThread mainThread];
            NSUInteger percent = 0;
            [invocation getArgument:&percent atIndex:3];
            [percentUpdates addObject:[NSNumber numberWithUnsignedInteger:percent]];
        }];

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [op start];
        });

        NSPredicate *isFinished = [NSPredicate predicateWithFormat:@"SELF[SIZE] = 20"];
        [self expectationForPredicate:isFinished evaluatedWithObject:percentUpdates handler:nil];
        [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
            expect(wasMainThread).to.equal(YES);
            expect(percentUpdates.count).to.equal(20);
            [percentUpdates enumerateObjectsUsingBlock:^(NSNumber *percent, NSUInteger idx, BOOL *stop) {
                expect(percent.unsignedIntegerValue).to.equal((idx + 1) * 5);
            }];
        }];

    });

    it(@"is unsuccessful when unzipping raises an exception", ^{
        ZipFile *zipFile = OCMClassMock([ZipFile class]);
        ZipException *zipError = [[ZipException alloc] initWithError:99 reason:@"test error"];

        [OCMStub([zipFile goToFirstFileInZip]) andThrow:zipError];

        expect(zipError).to.beInstanceOf([ZipException class]);
        OCMStub([zipFile close]);

        NSURL *destDir = [NSURL fileURLWithPath:@"/tmp/test"];
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];

        [op start];

        expect(op.wasSuccessful).to.equal(NO);
        expect(op.errorMessage).to.equal(@"Error reading zip file: test error");
        OCMVerify([zipFile close]);

        [(id)zipFile stopMocking];
    });

    /*
     These tests are for a weird condition in which the catch block 
     for ZipException gets skipped and drops through to NSException.
     Maybe we can revisit this later, but for now, just check the 
     name on the NSException that actually gets caught.
     */

    it(@"catches ZipException", ^{
        ZipFile *zipFile = OCMClassMock([ZipFile class]);
        ZipException *ze = [[ZipException alloc] initWithError:99 reason:@"test error"];
        [OCMStub([zipFile goToFirstFileInZip]) andThrow:ze];

        @try {
            [zipFile goToFirstFileInZip];
        }
        @catch (ZipException *exception) {
            expect(exception).to.beInstanceOf([ZipException class]);
            return;
        }

        failure(@"did not catch exception");
    });

    it(@"can mock throw exceptions", ^{
        ThrowException *thrower = OCMClassMock([ThrowException class]);
        ExceptionTest *test = [[ExceptionTest alloc] initWithThrower:thrower];

        ZipException *zipError = [[ZipException alloc] initWithError:99 reason:@"test error"];
        NSException *err = [[SpecificException alloc] initWithName:@"Test" reason:@"Testing" userInfo:nil];
        [OCMStub([thrower throwException]) andThrow:zipError];

        [test start];

        expect([test.exception class]).to.equal([ZipException class]);

        [(id)thrower stopMocking];
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd