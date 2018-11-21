import Foundation
import SwiftCLI

private let ticketPrefix = "Ticket: "

struct AnnotatorError: Error {
    let message: String
}

struct QuietError: Error {}

extension AnnotatorError: CustomStringConvertible {
    var description: String {
        return self.message
    }
}

enum ErrorHandling {
    case abort
    case omit
    case placeholder(String)

    static func fromFlags(abort: Flag, omit: Flag, placeholder: Key<String>) -> ErrorHandling {
        if let message = placeholder.value {
            return .placeholder(message)
        } else if abort.value {
            return .abort
        }
        return .omit
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

func makeTicketReader(
    errorHandling: ErrorHandling,
    branchReader: @escaping () throws -> String) -> (NSRegularExpression) throws -> String
{
    return { regexp in
        do {
            let branch = try branchReader()
            guard let ticket = extractFirstMatch(of: regexp, in: branch) else {
                throw AnnotatorError(message: "Couldn't find ticket in branch '\(branch)' with regexp '\(regexp.pattern)'")
            }
            return ticket
        } catch {
            switch errorHandling {
            case .abort: throw error
            case .omit: throw QuietError()
            case .placeholder(let placeholder): return placeholder
            }
        }
    }
}

func makeMessageUpdater(
    regexp: NSRegularExpression,
    ticketReader: @escaping (NSRegularExpression) throws -> String) -> (String) throws -> String
{
    return { message in
        guard !messageHasTicket(message) else { return message }
        let ticket = try ticketReader(regexp)
        let newlines = message.count > 2 ? message.reversed().prefix(while: { $0 == "\n" }).count : Int.max
        let messageWithTicket = message + (String(repeating: "\n", count: max(0, 2 - newlines))) + ticketPrefix + ticket + "\n"
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
    let shortDescription = "Add ticket information from branch to commit"

    let rawRegexp = Parameter()
    let file = Parameter()
    let abortOnError = Flag(
        "-a", "--abort", description: "Abort execution on ticket parse error with a message and error status")
    let omitOnError = Flag("-o", "--omit", description: "Omit ticket line on ticket parse error (default)")
    let placeholderOnError = Key<String>("-p", "--placeholder", description: "Use placeholder on ticket parse error")

    var optionGroups: [OptionGroup] {
        let errorHandling = OptionGroup.atMostOne(self.omitOnError, self.abortOnError, self.placeholderOnError)
        return [errorHandling]
    }

    func execute() throws {
        let errorHandling = ErrorHandling.fromFlags(
            abort: self.abortOnError, omit: self.omitOnError, placeholder: self.placeholderOnError)
        do {
            try updateFile(
                at: URL(fileURLWithPath: self.file.value, isDirectory: false),
                with: makeMessageUpdater(
                    regexp: try parseRegexp(raw: self.rawRegexp.value),
                    ticketReader: makeTicketReader(
                        errorHandling: errorHandling,
                        branchReader: readBranch)))
        } catch is QuietError {}
    }
}

class TestRegexp: Command {
    let name = "test-regexp"
    let shortDescription = "Test regular expression against a branch name"
    let longDescription = """
    Outputs what add-ticket would determine to be the ticket name given a
    regexp and a branch name.

    A non-matching branch name will cause an error with test-regexp. When
    using add-ticket, errors by default will only cause the branch name to
    be omitted from the commit message.

    Parameters:
        - regexp:     A regular expression. It must contain a capture
                      group, i.e. a part surrounded by parentheses.
        - branchName: A branch name to test against. It doesn't have to
                      exist in your repo. It's only used for text
                      matching.
    """

    let regexp = Parameter()
    let branchName = Parameter()

    func execute() throws {
        let compiledRegexp = try parseRegexp(raw: self.regexp.value)
        let ticketReader = makeTicketReader(errorHandling: .abort, branchReader: { self.branchName.value })
        let ticket = try ticketReader(compiledRegexp)
        stdout <<< "Ticket: \(ticket)"
    }
}


public func runAnnotator() {
    let argv = ProcessInfo.processInfo.arguments
    let annotator = CLI(name: argv[0])
    annotator.commands = [AddTicket(), TestRegexp()]
    exit(annotator.go())
}
