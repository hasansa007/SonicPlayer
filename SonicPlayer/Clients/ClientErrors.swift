import Foundation

/// What the clients throw, and what the user is told about it (#65).
///
/// **Every one of these was an `NSError` whose `localizedDescription` was an English sentence built
/// by interpolation** — and every path from a client to the screen ends in
/// `operationError = error.localizedDescription`, so the sentence *was* the alert. That produced the
/// reported bug, an alert reading:
///
/// ```
/// Access Denied: /Users/…/Containers/Data/Application/E083EBEA-… is not in /Users/…/Documents
/// ```
///
/// Two container paths, about 200 characters each, in a dialog. It also meant six user-facing
/// strings sat outside `Localizable.xcstrings` entirely, so every error in the app was English in
/// all nine languages.
///
/// **The split is the fix**: `errorDescription` is for the person and says what to do about it;
/// `logDescription` keeps the paths and the underlying error for the console. Nothing that names a
/// container directory reaches a screen.
protocol LoggableError: LocalizedError {
    /// The detail worth printing and never worth showing — paths, underlying errors, filenames.
    var logDescription: String { get }
}

/// Reading, importing and organising files.
enum FileError: LoggableError {
    /// A directory outside the app's Documents folder. Not reachable by an ordinary gesture; it
    /// means a stale bookmark or a URL from another app.
    case outsideLibrary(attempted: URL, root: URL)
    case unreadableSource(URL)
    case importFailed(name: String, underlying: Error)
    case corruptImport(name: String)

    var errorDescription: String? {
        switch self {
        case .outsideLibrary:
            String(localized: "That folder is not in your library.")
        case .unreadableSource:
            String(localized: "That file could not be read.")
        case .importFailed(let name, _):
            String(localized: "\(name) could not be imported.")
        case .corruptImport(let name):
            String(localized: "\(name) is not an audio file this app can play.")
        }
    }

    var logDescription: String {
        switch self {
        case .outsideLibrary(let attempted, let root):
            "outside library: \(attempted.path) not under \(root.path)"
        case .unreadableSource(let url):
            "unreadable source: \(url.path)"
        case .importFailed(let name, let underlying):
            "import failed for \(name): \(underlying)"
        case .corruptImport(let name):
            "corrupt or unplayable import: \(name)"
        }
    }
}

/// Playback.
enum PlaybackError: LoggableError {
    case cannotLoad(URL?)

    var errorDescription: String? {
        String(localized: "That recording could not be played. It may have been moved or deleted.")
    }

    var logDescription: String {
        switch self {
        case .cannotLoad(let url): "cannot load: \(url?.path ?? "no url")"
        }
    }
}

/// Capture.
enum RecordingError: LoggableError {
    case cannotStart

    var errorDescription: String? {
        String(localized: "Recording could not start. Check that the microphone is available.")
    }

    var logDescription: String { "recorder failed to start" }
}

/// **Says the human half on screen and keeps the rest for the console** (#65).
///
/// Every client error used to arrive as an `NSError` whose message was an interpolated English
/// sentence, and every one of these call sites assigned it straight to an alert — which is how two
/// 200-character container paths ended up in a dialog. `LoggableError` splits the two, and this is
/// the one place that has to remember to print the half nobody should read.
func userMessage(_ error: Error) -> String {
    if let loggable = error as? any LoggableError {
        print("[\(type(of: loggable))] \(loggable.logDescription)")
    } else {
        print("[error] \(error)")
    }
    return error.localizedDescription
}
