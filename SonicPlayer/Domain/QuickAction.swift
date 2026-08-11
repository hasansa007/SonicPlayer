import Foundation

/// A Home-screen quick action, identified by the string iOS hands back in
/// `UIApplicationShortcutItem.type`.
///
/// A type rather than two string literals in a `switch` because those literals are **duplicated
/// into `Info.plist`**, where `UIApplicationShortcutItemType` declares the same values. Nothing
/// checks that the two agree: a typo in either produces a shortcut that appears on the Home screen,
/// is tappable, and does nothing at all. `QuickActionTests` reads the plist and asserts every
/// declared type resolves here, which is the only place that mismatch can be caught without a
/// device.
enum QuickAction: String, CaseIterable {
    case record = "com.hasan.sonicplayer.record"
    case importMedia = "com.hasan.sonicplayer.import"
}
