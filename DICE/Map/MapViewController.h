//
//  MapViewController.h
//  InteractiveReports
//


#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

#import "OfflineMapUtility.h"
#import "Report.h"
#import "ReportCollectionView.h"
#import "ReportMapAnnotation.h"
#import "HTMLViewController.h"


@interface MapViewController : UIViewController <ReportCollectionView, MKMapViewDelegate, UIGestureRecognizerDelegate>

@property (strong, nonatomic) NSArray *reports;
@property (strong, nonatomic) id<ReportCollectionViewDelegate> delegate;
@property (strong, nonatomic) IBOutlet MKMapView *mapView;
@property (strong, nonatomic) Report *selectedReport;

@end
