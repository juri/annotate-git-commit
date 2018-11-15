import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(GitAnnotateTicketTests.allTests),
        testCase(MessageUpdaterTests.allTests)
    ]
}
#endif
