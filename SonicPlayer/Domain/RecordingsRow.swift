import Foundation

/// What row *n* of the recordings list means (#6).
///
/// The list stopped being the recordings array when Import moved into it. Import is row 0 and is
/// always there, so recording *i* is row *i + 1* — an offset that is read in eight places: `press`,
/// `doublePress`, the deferred-press decision, the stick's directions, the actions menu, the trim
/// editor, the hub's label and the row count. Every one of them indexed `content.recordings` with
/// the raw highlight before this existed.
///
/// **The offset is stated once, here, because getting it wrong anywhere is silent.** There is no
/// crash and no failed guard — the wheel lands on a recording and the hub opens the one above it,
/// or `Delete` names one file and removes another. That was the whole reason Import was a chip in
/// the first place; making it a row means paying this cost properly rather than avoiding it.
enum RecordingsRow: Equatable {

    /// Row 0. Always present, including when there is nothing to import *into* — which is the state
    /// it matters most in, and the one a row could not reach while the empty list was a message.
    case importFiles
    /// An index into `DialContent.recordings`, already un-offset. Callers must never subtract again.
    case recording(index: Int)

    /// How many rows the list has for a given number of recordings.
    static func rowCount(recordings count: Int) -> Int { count + 1 }

    /// What the highlight is pointing at, or `nil` when it points past the end.
    ///
    /// Out of range is `nil` rather than a clamp on purpose: the navigator clamps its own highlight,
    /// so a value that lands here out of range means the data moved underneath it, and the caller
    /// should feel a limit rather than act on a neighbour.
    static func at(_ highlighted: Int, recordings count: Int) -> RecordingsRow? {
        guard highlighted >= 0, highlighted < rowCount(recordings: count) else { return nil }
        return highlighted == 0 ? .importFiles : .recording(index: highlighted - 1)
    }

    /// The row a given recording sits on — the inverse, for the places holding an index that need a
    /// highlight back.
    static func row(forRecording index: Int) -> Int { index + 1 }
}
