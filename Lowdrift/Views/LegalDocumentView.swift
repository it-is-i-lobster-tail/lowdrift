import SwiftUI

/// A Terms of Service or Privacy Policy page. The text ships inside the app, so
/// it reads the same offline and nothing is fetched.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Effective \(LegalDocument.effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(document.summary)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal.\(document.id)")
    }
}

struct LegalDocument: Identifiable {
    struct Section: Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    let id: String
    let title: String
    let summary: String
    let sections: [Section]

    static let effectiveDate = "November 28, 2026"

    static let privacyPolicy = LegalDocument(
        id: "privacy",
        title: "Privacy Policy",
        summary: "Lowdrift collects nothing. There is no account, no tracking and no network access. Your settings stay on this iPhone.",
        sections: [
            Section(
                heading: "No data collection",
                body: "Lowdrift does not collect, store on any server, sell or share any information about you. It has no analytics, crash reporting, advertising, advertising identifiers, accounts or sign-in."
            ),
            Section(
                heading: "No network access",
                body: "Lowdrift contains no networking code and never connects to the internet. Every sound is generated live on your iPhone, and the app works the same in Airplane Mode."
            ),
            Section(
                heading: "No permissions",
                body: "Lowdrift never asks for your microphone, location, contacts, photos, Bluetooth, local network or permission to track you. It plays sound and never records it."
            ),
            Section(
                heading: "What stays on your iPhone",
                body: "To remember your preferences, Lowdrift saves the last sound you chose, your Customize sound settings for each sound, which sounds appear on the main screen, and your favorites. These are kept only in the app's own storage on this iPhone, are never sent anywhere, and are removed when you delete the app. If your device backups are turned on, Apple may include them in your backup like any other app setting."
            ),
            Section(
                heading: "Apple features",
                body: "If you use Siri, Shortcuts, the Lock Screen or Control Center with Lowdrift, those features are provided by Apple and covered by Apple's own privacy policy. Lowdrift only receives commands such as Play, Pause or a sound to select."
            ),
            Section(
                heading: "Children",
                body: "Because Lowdrift collects no information from anyone, it collects none from children."
            ),
            Section(
                heading: "Changes",
                body: "If this policy ever changes, the new version will appear here in an app update, with a new effective date. Lowdrift's promise is to stay free and private."
            ),
        ]
    )

    static let termsOfService = LegalDocument(
        id: "terms",
        title: "Terms of Service",
        summary: "Lowdrift is free to use for sleep, relaxation and focus. By using it, you agree to these terms.",
        sections: [
            Section(
                heading: "Using Lowdrift",
                body: "You may use Lowdrift for your own personal, non-commercial purposes on any Apple device you own or control, as allowed by the App Store terms. There is nothing to buy and no account to create."
            ),
            Section(
                heading: "Free forever",
                body: "Lowdrift has no ads, subscriptions or in-app purchases. It is provided without charge."
            ),
            Section(
                heading: "Listen safely",
                body: "Keep the volume at a comfortable, moderate level, especially with headphones or when listening for long periods or overnight. Do not use Lowdrift where you need to hear your surroundings, such as while driving. Keep devices and cables away from infants' sleep spaces."
            ),
            Section(
                heading: "Not medical advice",
                body: "Lowdrift is a sound generator for comfort. It is not a medical device and is not intended to diagnose, treat or prevent any condition, including sleep disorders or tinnitus. Talk to a health professional about any health concern."
            ),
            Section(
                heading: "Your privacy",
                body: "Lowdrift collects no data. See the Privacy Policy in Settings for details."
            ),
            Section(
                heading: "Ownership",
                body: "Lowdrift, its sounds, design and name belong to its developer. You may not resell the app or present it as your own."
            ),
            Section(
                heading: "No warranty",
                body: "Lowdrift is provided \"as is\" and \"as available\", without warranties of any kind, to the fullest extent permitted by law. It may not play without interruption, for example during calls, alarms or when another app uses audio."
            ),
            Section(
                heading: "Limitation of liability",
                body: "To the fullest extent permitted by law, the developer of Lowdrift is not liable for any indirect, incidental or consequential damages arising from your use of the app. Nothing in these terms limits rights you have under consumer protection laws that cannot be waived."
            ),
            Section(
                heading: "Apple",
                body: "These terms are between you and the developer of Lowdrift, not Apple. Apple's standard Licensed Application End User License Agreement also applies, and Apple has no obligation to provide support for the app."
            ),
            Section(
                heading: "Changes",
                body: "These terms may be updated in a future version of the app. The updated terms will appear here with a new effective date."
            ),
        ]
    )
}
