//
//  BOXFolderItemsRequestTests.m
//  BoxContentSDK
//
//  Created by Boris Suvorov on 4/1/15.
//  Copyright (c) 2015 Box. All rights reserved.
//

#import "BOXRequestTestCase.h"
#import "BOXFolderItemsRequest.h"
#import "NSURL+BOXURLHelper.h"

#import "BOXBookmark.h"
#import "BOXFile.h"
#import "BOXFolder.h"
#import "BOXItem.h"


@interface BOXFolderItemsRequestTests : BOXRequestTestCase
@end

@interface BOXFolderItemsRequest ()
- (void)performPaginatedRequestWithCompletion:(BOXItemArrayCompletionBlock)completionBlock;
- (NSUInteger)rangeStep;

+ (NSString *)uniqueHashForItem:(BOXItem *)item;
+ (NSArray *)dedupeItemsByBoxID:(NSArray *)items;

@end


@implementation BOXFolderItemsRequestTests

- (void)test_dedupeItemsByBoxID_dedupes_items
{
    BOXFile *file1 = [[BOXFile alloc] init];
    file1.modelID = @"1";
    BOXFolder *folder1 = [[BOXFolder alloc] init];
    folder1.modelID = @"1";
    BOXBookmark *bookmark2 = [[BOXBookmark alloc] init];
    bookmark2.modelID = @"2";

    BOXFolder *folder2 = [[BOXFolder alloc] init];
    folder2.modelID = @"2";
    
    NSArray *itemsWithDupes = [[NSArray alloc] initWithObjects:file1, bookmark2, folder1, folder2, 
                                                               file1, bookmark2, folder1, nil];    
    NSArray *expectedItems = [NSArray arrayWithObjects:file1, bookmark2, folder1, folder2, nil];
    
    NSArray *mergedItems = [BOXFolderItemsRequest dedupeItemsByBoxID:itemsWithDupes];
    XCTAssert(mergedItems.count == 4, @"merged array contains non unique items");
    
    for (NSUInteger i = 0; i < mergedItems.count ; i++) {
        [self assertModel:mergedItems[i] isEquivalentTo:expectedItems[i]];
    }
}

- (void)test_unique_item_hash_generation_does_not_collide_for_different_item_classes
{
    NSString *modelID = @"abbabeefabba";
    BOXFolder *folder = [[BOXFolder alloc] init];
    folder.modelID = modelID;
    
    BOXBookmark *bookmark = [[BOXBookmark alloc] init];
    bookmark.modelID = modelID;
    
    BOXFile *file = [[BOXFile alloc] init];
    file.modelID = modelID;
    
    NSString *folderHash = [BOXFolderItemsRequest uniqueHashForItem:folder];
    NSString *fileHash = [BOXFolderItemsRequest uniqueHashForItem:file];
    NSString *bookmarkHash = [BOXFolderItemsRequest uniqueHashForItem:bookmark];

    XCTAssertNotEqualObjects(folderHash, fileHash);
    XCTAssertNotEqualObjects(folderHash, bookmarkHash);
    XCTAssertNotEqualObjects(fileHash, bookmarkHash);    
}

- (void)test_that_basic_request_has_expected_URLRequest_for_the_first_iteration
{
    NSString *folderID = @"123";
    
    BOXFolderItemsRequest *request = [[BOXFolderItemsRequest alloc] initWithFolderID:folderID];
    request.requestAllItemFields = YES;
        
    NSURLRequest *URLRequest = request.urlRequest;
    
    NSString *expectedURL = [NSString stringWithFormat:@"%@/%@/folders/%@/items", BOXAPIBaseURL, BOXAPIVersion, folderID];
    NSString *requestURL = [NSString stringWithFormat:@"%@://%@%@", URLRequest.URL.scheme, URLRequest.URL.host, URLRequest.URL.path];
    
    XCTAssertEqualObjects(expectedURL, requestURL);
    XCTAssertEqualObjects(@"GET", URLRequest.HTTPMethod);
    
    NSDictionary *requestURLParameters = [URLRequest.URL box_queryDictionary];
    NSString *expectedFieldsString = [[[BOXRequest alloc] init] fullItemFieldsParameterString];
    NSString *requestFieldsString = [requestURLParameters[BOXAPIParameterKeyFields] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    XCTAssertEqualObjects(requestFieldsString, expectedFieldsString);
    
    XCTAssertEqualObjects(requestURLParameters[BOXAPIParameterKeyLimit], @"1000");
    XCTAssertEqualObjects(requestURLParameters[BOXAPIParameterKeyOffset], @"0");
}

- (void)mockPaginatedDupedDataRequestWithCompletion:(BOXItemArrayCompletionBlock)completion
{
    static NSUInteger start = 0;
    static NSUInteger len = 3;
    static NSUInteger totalCount = 5;
    
    NSData *cannedData = nil;
    NSRange range = NSMakeRange(start, len);
    if (start == 0) {
        cannedData = [self cannedResponseDataWithName:@"get_items_0_2"];        
        start += 3;
        len = 2;
        
    } else {
        cannedData = [self cannedResponseDataWithName:@"get_items_3_5_duped"];    
    }
    
    NSArray *results = [self itemsFromResponseData:cannedData];
    
    if (completion) {
        completion(results, totalCount, range, nil);
    }    
}


- (void)mockPaginatedRequestWithCompletion:(BOXItemArrayCompletionBlock)completion
{
    static NSUInteger start = 0;
    static NSUInteger len = 3;
    static NSUInteger totalCount = 5;
    
    NSData *cannedData = nil;
    NSRange range = NSMakeRange(start, len);
    if (start == 0) {
        cannedData = [self cannedResponseDataWithName:@"get_items_0_2"];        
        start += 3;
        len = 2;

    } else {
        cannedData = [self cannedResponseDataWithName:@"get_items_3_5"];    
    }
    
    NSArray *results = [self itemsFromResponseData:cannedData];

    if (completion) {
        completion(results, totalCount, range, nil);
    }    
}

- (void)test_that_expected_items_are_returned_for_folder_despite_dupe_item_in_response
{
    BOXFolderItemsRequest *request = [[BOXFolderItemsRequest alloc] initWithFolderID:@"123"];
    
    id requestMock = [OCMockObject partialMockForObject:request];
    
    [[[requestMock stub] andCall:@selector(mockPaginatedDupedDataRequestWithCompletion:) onObject:self] performPaginatedRequestWithCompletion:OCMOCK_ANY];    
    [[[requestMock stub] andReturnValue:OCMOCK_VALUE(3)] rangeStep];
    
    NSData *cannedData0_2 = [self cannedResponseDataWithName:@"get_items_0_2"];
    NSData *cannedData3_5 = [self cannedResponseDataWithName:@"get_items_3_5_duped"];
    
    NSArray *items0_2 = [self itemsFromResponseData:cannedData0_2];
    NSArray *items3_5 = [self itemsFromResponseData:cannedData3_5];
    
    NSMutableArray *expectedItems = [[NSMutableArray alloc] initWithArray:items0_2];
    [expectedItems addObjectsFromArray:items3_5];

    //last object in get_items_3_5_duped is also present in get_items_0_2
    [expectedItems removeLastObject];
    
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    
    [request performRequestWithCompletion:^(NSArray *items, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(items.count, expectedItems.count);
        for (NSUInteger i = 0; i < items.count ; i++) {
            [self assertModel:items[i] isEquivalentTo:expectedItems[i]];
        }
        
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}


- (void)test_that_expected_items_are_returned_for_folder
{
    BOXFolderItemsRequest *request = [[BOXFolderItemsRequest alloc] initWithFolderID:@"123"];
        
    id requestMock = [OCMockObject partialMockForObject:request];

    [[[requestMock stub] andCall:@selector(mockPaginatedRequestWithCompletion:) onObject:self] performPaginatedRequestWithCompletion:OCMOCK_ANY];    
    [[[requestMock stub] andReturnValue:OCMOCK_VALUE(3)] rangeStep];
    
    NSData *cannedData0_2 = [self cannedResponseDataWithName:@"get_items_0_2"];
    NSData *cannedData3_5 = [self cannedResponseDataWithName:@"get_items_3_5"];
    
    NSArray *items0_2 = [self itemsFromResponseData:cannedData0_2];
    NSArray *items3_5 = [self itemsFromResponseData:cannedData3_5];
    
    NSMutableArray *expectedItems = [[NSMutableArray alloc] initWithArray:items0_2];
    [expectedItems addObjectsFromArray:items3_5];
    
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    
    [request performRequestWithCompletion:^(NSArray *items, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqual(items.count, expectedItems.count);
        for (NSUInteger i = 0; i < items.count ; i++) {
            [self assertModel:items[i] isEquivalentTo:expectedItems[i]];
        }
        
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}


@end
