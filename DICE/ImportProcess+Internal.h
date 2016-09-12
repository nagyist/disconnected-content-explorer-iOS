//
//  ImportProcess+Internal.h
//  DICE
//
//  Created by Robert St. John on 5/19/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#ifndef ImportProcess_Internal_h
#define ImportProcess_Internal_h


#import "ImportProcess.h"


@interface ImportProcess ()

@property (readwrite) NSArray<NSOperation *> *steps;
@property (readwrite) Report *report;

- (nullable instancetype)initWithReport:(nullable Report *)report;
- (void)stepWillFinish:(NSOperation *)step;
- (void)stepWillCancel:(NSOperation *)step;
- (void)cancelStepsAfterStep:(NSOperation *)step;

@end


#endif /* ImportProcess_Internal_h */
