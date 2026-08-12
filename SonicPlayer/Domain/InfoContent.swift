import Foundation

/// The copy behind About and How it works (#50).
///
/// **Values, not views.** Both were `ScrollView`s of hand-built cards — `AboutView` 275 lines and
/// `HelpView` 332, with ten one-off component structs between them and three of those never
/// constructed. As data they are two arrays the dial projects like any other list, and the ten
/// components stop existing rather than getting ported.
///
/// **Every string goes through `String(localized:)`, which is the point as much as the shape.** The
/// old screens reached the display through `Text(title)`, `Text(question)`, `Text(answer)` — the
/// non-localising initialiser — and contained not one `String(localized:)` between them. So they
/// rendered in English in all nine languages, including the Arabic the store listing advertises, and
/// none of the FAQ copy was in `Localizable.xcstrings` at all. A literal here is extractable; a
/// `String` variable handed to `Text` is not.
///
/// **The copy is rewritten, not moved.** The shipped Help was a manual for the app the dial replaced:
/// "In the Library tab, tap the + button", "In the Player view, tap the speed control", "Use the skip
/// buttons on either side of the play button", "Open the Recordings tab", "Try pulling to refresh".
/// None of those exist. About claimed "Library + Search" — `searchText` lives on
/// `CollectionsViewModel` and nothing surfaces it — and the dead `techStackSection` still credited
/// TCA, removed in #20. A help screen that describes a different app is worse than none, because it
/// is read by someone already confused.
enum InfoContent {

    /// One row, and the screen it opens. Both lists are made of these.
    struct Entry: Equatable, Identifiable {
        let id: String
        let icon: DialScreen.Icon
        /// The row, and the detail screen's title.
        let title: String
        /// The row's second line. `nil` on the help list, where the question is the whole row.
        let subtitle: String?
        /// What the detail screen says.
        let body: String
    }

    // MARK: - About

    static var about: [Entry] {
        [
            Entry(
                id: "purpose",
                icon: .library,
                title: String(localized: "What it is for"),
                subtitle: String(localized: "Your own audio, no ads and no algorithms"),
                body: String(localized: "Sonic Player plays the audio you already have. Import your files, organise them into folders, and listen offline. Nothing is recommended to you and nothing is streamed.")
            ),
            Entry(
                id: "dial",
                icon: .settings,
                title: String(localized: "One dial"),
                subtitle: String(localized: "Turn to move, press to play, nudge to act"),
                body: String(localized: "Everything is done with the wheel and its centre. Turn to move through your library and press the centre to play what you land on. Keep turning past the last row and you reach the buttons under the card. Push the centre up, down, left or right for the things you do most to a recording.")
            ),
            Entry(
                id: "offline",
                icon: .stats,
                title: String(localized: "Offline first"),
                subtitle: String(localized: "Your files stay on the phone"),
                body: String(localized: "Your recordings are stored on the device and never uploaded. The app needs no account and no connection, so it works the same on a plane as at home.")
            ),
            Entry(
                id: "record",
                icon: .recording,
                title: String(localized: "Record and trim"),
                subtitle: String(localized: "Capture a take, then cut it on the wheel"),
                body: String(localized: "Record from anywhere in the library, and the take is saved in the folder you were in. The editor is a wheel too: turn to move a handle, hear the selection before you commit to it, then keep it or cut it out.")
            ),
            Entry(
                id: "folders",
                icon: .newFolder,
                title: String(localized: "Folders"),
                subtitle: String(localized: "Make one, rename it, file recordings into it"),
                body: String(localized: "Make a folder, rename it, and move recordings between them. Filing something offers a brand-new folder as the first choice, so you can name one and file into it in a single step. Each folder keeps its own order.")
            ),
            Entry(
                id: "privacy",
                icon: .session,
                title: String(localized: "Privacy"),
                subtitle: String(localized: "Nothing leaves the device"),
                body: String(localized: "There is no analytics, no account and no network request. The microphone is used only while you are recording, which is the one permission the app asks for.")
            )
        ]
    }

    // MARK: - How it works

    /// **Answers written against the dial, because the wheel is the part nobody has seen before.**
    ///
    /// The features are ordinary — play, record, trim. The control is not, so every answer says which
    /// gesture, not which screen.
    static var help: [Entry] {
        [
            Entry(
                id: "add",
                icon: .importFile,
                title: String(localized: "How do I add audio?"),
                subtitle: nil,
                body: String(localized: "Turn the wheel past the last row to reach the buttons under the card, rest on Import and press. Pick files or a whole folder. You can also open an audio file from the Files app and it will be imported and played.")
            ),
            Entry(
                id: "play",
                icon: .play,
                title: String(localized: "How do I play something?"),
                subtitle: nil,
                body: String(localized: "Turn the wheel until the recording you want is highlighted, then press the centre. To see what is playing, press the centre and hold for a moment, or press the status line at the top of the card.")
            ),
            Entry(
                id: "speed",
                icon: .next,
                title: String(localized: "How do I change the speed?"),
                subtitle: nil,
                body: String(localized: "Open Settings from the button under the card, rest on Playback speed and press to cycle through the speeds. It is used the next time a track opens.")
            ),
            Entry(
                id: "record",
                icon: .recording,
                title: String(localized: "How do I record?"),
                subtitle: nil,
                body: String(localized: "Rest on Record under the card and press. The ring shows the input level, turning sets the gain, and pressing the centre stops the take. A recording started inside a folder is saved in that folder.")
            ),
            Entry(
                id: "trim",
                icon: .trim,
                title: String(localized: "How do I trim a recording?"),
                subtitle: nil,
                body: String(localized: "Rest on a recording and push the centre up to open the editor. Turn to move a handle, and push right to hear the selection before you commit to it. The centre keeps what you selected; push down to remove it instead. Either way it asks before it rewrites the recording.")
            ),
            Entry(
                id: "folders",
                icon: .newFolder,
                title: String(localized: "How do folders work?"),
                subtitle: nil,
                body: String(localized: "New folder is one of the buttons under the card. To file a recording, rest on it and push the centre left — a brand-new folder is offered first, so you can name one and move into it at once.")
            ),
            Entry(
                id: "offline",
                icon: .stats,
                title: String(localized: "Does it work offline?"),
                subtitle: nil,
                body: String(localized: "Yes, always. Your files are on the device and there is no account and no network request, so nothing about the app depends on a connection.")
            )
        ]
    }

    // MARK: - Version

    /// `3.0.0 (24)`, or as much of it as the bundle has.
    ///
    /// **The one thing the old About screen said that this one dropped.** It was a `Text` under the
    /// app name; the dial has no such slot, and the chrome's status line is where a screen states
    /// what it is about — so that is where it goes. Lost in the rewrite and put back after it was
    /// noticed on a build, which is the argument for looking at screens rather than diffs.
    static var version: String? {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        case let (nil, build?): return build
        case (nil, nil): return nil
        }
    }

    // MARK: - Lookup

    /// **One lookup for both, keyed by id.** A route carries an id rather than an index, so a list
    /// reordered later cannot point a detail screen at the wrong entry — the offset bug this codebase
    /// has already paid for twice.
    static func entry(_ id: String, in list: [Entry]) -> Entry? {
        list.first { $0.id == id }
    }
}
