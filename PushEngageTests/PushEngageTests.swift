//
//  PushEngageTests.swift
//  PushEngageTests
//
//  Created by Abhishek on 07/04/21.
//

import XCTest
@testable import PushEngage

class PushEngageTests: XCTestCase {

    var response: Any?
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testRemoteNotificationRegisteration() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func testAddSubscriber() {
        
        
    }
}
