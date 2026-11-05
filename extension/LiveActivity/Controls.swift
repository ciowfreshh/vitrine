// Controls for Control Center, the lock screen and the Action button (iOS 18): Like, Sing and the sleep
// timer. Each runs one of LiveActivityShared.swift's shortcut intents, which perform inside Spotify. They are
// buttons, not toggles: what Sing is doing lives in Spotify, and this extension shares no container with it
// to read it from, so a toggle's on and off would be a guess.
import AppIntents
import SwiftUI
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)

@available(iOS 18.0, *)
struct SGLikeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "spotifyglass.control.like") {
            ControlWidgetButton(action: SGLikeIntent()) {
                Label { Text("Like This Song", tableName: "Vitrine") } icon: { Image(systemName: "heart") }
                    .controlWidgetActionHint(LocalizedStringResource("Like", table: "Vitrine", locale: SGUIL10n.locale))
            }
            .tint(green)
        }
        .displayName(LocalizedStringResource("Like This Song", table: "Vitrine", locale: SGUIL10n.locale))
        .description(LocalizedStringResource("Adds the song playing in Spotify to Liked Songs.", table: "Vitrine", locale: SGUIL10n.locale))
    }
}

@available(iOS 18.0, *)
struct SGSingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "spotifyglass.control.sing") {
            ControlWidgetButton(action: SGSingIntent(.toggle)) {
                Label { Text("Karaoke", tableName: "Vitrine") } icon: { Image(systemName: "music.mic") }
                    .controlWidgetActionHint(LocalizedStringResource("Turn Karaoke On or Off", table: "Vitrine", locale: SGUIL10n.locale))
            }
            .tint(green)
        }
        .displayName(LocalizedStringResource("Karaoke", table: "Vitrine", locale: SGUIL10n.locale))
        .description(LocalizedStringResource("Turns the vocals down in Spotify so you can sing along, or brings them back.", table: "Vitrine", locale: SGUIL10n.locale))
    }
}

// Which length the sleep timer control sets, picked when it is added.
@available(iOS 18.0, *)
struct SGSleepTimerControlConfiguration: ControlConfigurationIntent {
    static let title = LocalizedStringResource("Sleep Timer", table: "Vitrine", locale: SGUIL10n.locale)
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Length", table: "Vitrine", locale: SGUIL10n.locale), default: .thirty)
    var length: SGSleepTimerLength
}

@available(iOS 18.0, *)
struct SGSleepTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "spotifyglass.control.sleeptimer", intent: SGSleepTimerControlConfiguration.self) { configuration in
            ControlWidgetButton(action: SGSleepTimerIntent(configuration.length)) {
                Label {
                    Text("Sleep Timer", tableName: "Vitrine")
                    Text(SGSleepTimerLength.caseDisplayRepresentations[configuration.length]?.title ?? "")
                } icon: {
                    Image(systemName: "moon.zzz")
                }
                .controlWidgetActionHint(configuration.length == .off ? LocalizedStringResource("Turn Off the Sleep Timer", table: "Vitrine", locale: SGUIL10n.locale) : LocalizedStringResource("Start the Sleep Timer", table: "Vitrine", locale: SGUIL10n.locale))
            }
            .tint(green)
        }
        .displayName(LocalizedStringResource("Sleep Timer", table: "Vitrine", locale: SGUIL10n.locale))
        .description(LocalizedStringResource("Pauses Spotify after the length you pick, or at the end of the track or the album.", table: "Vitrine", locale: SGUIL10n.locale))
        .promptsForUserConfiguration()
    }
}
