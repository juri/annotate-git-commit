import Foundation
import SwiftCLI

private let ticketPrefix = "Ticket: "

struct AnnotatorError: Error {
    let message: String
}

extension AnnotatorError: CustomStringConvertible {
    var description: String {
        return self.message
    }
}


func messageHasTicket(_ message: String) -> Bool {
    return message.split(separator: "\n").first(where: { $0.hasPrefix(ticketPrefix) }) != nil
}

func readBranch() throws -> String {
    return try capture("git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"]).stdout
}

func extractFirstMatch(of regexp: NSRegularExpression, in string: String) -> String? {
    let fullNSRange = NSRange(location: 0, length: string.utf16.count)
    guard
        let result = regexp.firstMatch(in: string, options: [], range: fullNSRange),
        result.numberOfRanges == 2,
        let range = Range(result.range(at: 1), in: string)
    else {
        return nil
    }
    return String(string[range])
}

func makeTicketReader(branchReader: @escaping () throws -> String) -> (NSRegularExpression) throws -> String? {
    return { regexp in
        let branch = try branchReader()
        guard let ticket = extractFirstMatch(of: regexp, in: branch) else {
            throw AnnotatorError(message: "Couldn't find ticket in branch '\(branch)' with regexp '\(regexp.pattern)'")
        }
        return ticket
    }
}

func makeMessageUpdater(
    regexp: NSRegularExpression,
    ticketReader: @escaping (NSRegularExpression) throws -> String?) -> (String) throws -> String
{
    return { message in
        guard !messageHasTicket(message) else { return message }
        guard let ticket = try ticketReader(regexp) else {
            throw AnnotatorError(message: "Couldn't match ticket name in branch")
        }

        let messageWithTicket = message + (message.hasSuffix("\n\n") ? "" : "\n") + ticketPrefix + ticket + "\n"
        return messageWithTicket
    }
}

func updateFile(at url: URL, with updater: (String) throws -> String) throws {
    let messageData = try Data(contentsOf: url)
    guard let message = String(bytes: messageData, encoding: .utf8) else {
        throw AnnotatorError(message: "Couldn't parse commit message in \(url)")
    }
    let updatedMessage = try updater(message)
    try Data(updatedMessage.utf8).write(to: url, options: .atomic)
}

func parseRegexp(raw: String) throws -> NSRegularExpression {
    let regexp = try NSRegularExpression(pattern: raw, options: [])
    guard regexp.numberOfCaptureGroups == 1 else {
        throw AnnotatorError(message: "Regexp must have one capture group for matching the ticket name")
    }
    return regexp
}

class AddTicket: Command {
    let name = "add-ticket"
    let rawRegexp = Parameter()
    let file = Parameter()

    func execute() throws {
        try updateFile(
            at: URL(fileURLWithPath: file.value, isDirectory: false),
            with: makeMessageUpdater(
                regexp: try parseRegexp(raw: rawRegexp.value),
                ticketReader: makeTicketReader(branchReader: readBranch)))
    }
}

public func runAnnotator() {
    let argv = ProcessInfo.processInfo.arguments
    let annotator = CLI(name: argv[0])
    annotator.commands = [AddTicket()]
    exit(annotator.go())
}
