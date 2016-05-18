//
//  MapOverlayChildTableCell.h
//  DICE
//
//  Created by Brian Osborn on 3/2/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MapOverlayActiveSwitch.h"

/**
 *  Overlay child table view cell
 */
@interface MapOverlayChildTableCell : UITableViewCell

@property (weak, nonatomic) IBOutlet MapOverlayActiveSwitch *active;
@property (weak, nonatomic) IBOutlet UIImageView *tableType;
@property (weak, nonatomic) IBOutlet UILabel *name;
@property (weak, nonatomic) IBOutlet UILabel *info;

@end
