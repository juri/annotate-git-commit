//
//  MessageUpdaterTests.swift
//  git-branch-commitTests
//
//  Created by Juri Pakaste on 14/11/2018.
//

import XCTest
@testable import GitAnnotateTicketKit

let regexp = try! NSRegularExpression(pattern: "\\b(ch\\d+)\\b", options: [])
let matchingBranch = "feature/ch1234/foo"
let nonMatchingBranch = "feature/no-ticket-here"

class MessageUpdaterTests: XCTestCase {
    func testUpdateEmpty() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .abort,
                branchReader: { matchingBranch }))
        XCTAssertEqual(try messageUpdater(""), "\nTicket: ch1234\n")
    }

    func testUpdateNonEmpty() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .abort,
                branchReader: { matchingBranch }))
        XCTAssertEqual(try messageUpdater("lines\nof\ntext\n"), "lines\nof\ntext\n\nTicket: ch1234\n")
    }

    func testUpdateNonEmptyNoExtraLines() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .abort,
                branchReader: { matchingBranch }))
        XCTAssertEqual(try messageUpdater("lines\nof\ntext\n\n"), "lines\nof\ntext\n\nTicket: ch1234\n")
    }

    func testUpdateNonMatchingBranchAbort() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .abort,
                branchReader: { nonMatchingBranch }))
        XCTAssertThrowsError(try messageUpdater(""))
    }

    func testUpdateNonMatchingBranchOmit() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .omit,
                branchReader: { nonMatchingBranch }))
        XCTAssertThrowsError(try messageUpdater("hello"), "hello")
    }

    func testUpdateNonMatchingBranchPlaceholder() throws {
        let messageUpdater = makeMessageUpdater(
            regexp: regexp,
            ticketReader: makeTicketReader(
                errorHandling: .placeholder("No ticket"),
                branchReader: { nonMatchingBranch }))
        XCTAssertEqual(try messageUpdater("hello"), "hello\nTicket: No ticket\n")
    }

    static var allTests = [
        ("testUpdateEmpty", testUpdateEmpty),
        ("testUpdateNonEmpty", testUpdateNonEmpty),
        ("testUpdateNonEmptyNoExtraLines", testUpdateNonEmptyNoExtraLines),
    ]
}
