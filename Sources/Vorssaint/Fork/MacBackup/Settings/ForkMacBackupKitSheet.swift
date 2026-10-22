// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// « Kit de récupération » (plan §9): its state, the PDF to print, the file
/// with the secrets sealed by a passphrase, the reminder, and the way in
/// from another Mac.
struct ForkMacBackupKitSheet: View {
    @ObservedObject var context: ForkMacBackupSettingsContext
    let open: (ForkMacBackupSheet) -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var includeSecrets = false
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var warning: String?
    @State private var busy = false
    @State private var importedKit: ForkMacBackupKitFile?
    @State private var kitPassphrase = ""
    @State private var kitProblem: String?

    private var text: ForkMacBackupSettingsStrings { .strings(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        ForkMacBackupSheetScaffold(symbol: "lifepreserver.fill", color: .orange, title: text.kitTitle, subtitle: text.kitSubtitle,
                                   done: text.done) {
            statusSection
            if context.repository != nil {
                createSection
                reminderSection
            }
            otherMacSection
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(statusColor)
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    ForkMacBackupCaption(statusCaption)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var statusSymbol: String {
        switch context.kitStatus {
        case .upToDate: return "checkmark.seal.fill"
        case .missing: return "lifepreserver"
        case .repositoryChanged, .reminderDue: return "exclamationmark.arrow.circlepath"
        }
    }

    private var statusColor: Color {
        if case .upToDate = context.kitStatus { return .green }
        return .orange
    }

    private var statusTitle: String {
        switch context.kitStatus {
        case .missing: return context.repository == nil ? text.kitNeedsConnection : text.kitMissing
        case .upToDate(let date): return String(format: text.kitUpToDate, ForkMacBackupDay.text(date, locale: locale, now: context.services.now()))
        case .repositoryChanged: return text.kitStaleChanged
        case .reminderDue(let date): return String(format: text.kitStaleOld, ForkMacBackupDay.text(date, locale: locale, now: context.services.now()))
        }
    }

    private var statusCaption: String {
        switch context.kitStatus {
        case .repositoryChanged: return text.kitStaleChangedCaption
        default: return text.kitWhy
        }
    }

    // MARK: Create

    private var passphraseIssue: String? {
        guard includeSecrets else { return nil }
        if passphrase.count < 8 { return text.passphraseTooShort }
        if passphrase != confirmation { return text.passphraseMismatch }
        return nil
    }

    private var createSection: some View {
        Section {
            Toggle(isOn: $includeSecrets) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.kitIncludeSecrets)
                    ForkMacBackupCaption(text.kitIncludeSecretsCaption)
                }
            }
            if includeSecrets {
                SecureField(text.passphrase, text: $passphrase)
                SecureField(text.passphraseConfirm, text: $confirmation)
                if let issue = passphraseIssue, !passphrase.isEmpty {
                    ForkMacBackupCaption(issue, color: .orange)
                }
            }
            HStack(spacing: 8) {
                Button {
                    savePDF()
                } label: {
                    Label(text.kitSavePDF, systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
                .tint(ForkMacBackupStyle.accent)
                Button {
                    printPDF()
                } label: {
                    Label(text.kitPrint, systemImage: "printer")
                }
                Button {
                    saveFile()
                } label: {
                    Label(text.kitSaveFile, systemImage: "doc.badge.gearshape")
                }
                .disabled(passphraseIssue != nil || busy)
            }
            Button(text.kitCopyFields) { copyFields() }
                .buttonStyle(.link)
            if busy {
                ProgressView().controlSize(.small)
            }
            if let message {
                ForkMacBackupCaption(message, color: .green)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(text.kitCreateHeader)
        } footer: {
            ForkMacBackupCaption(text.kitWhereFooter)
        }
    }

    // MARK: Reminder

    private var reminderSection: some View {
        Section {
            if let remind = context.kitRemindAt {
                LabeledContent(text.kitNextReminder, value: ForkMacBackupDay.text(remind, locale: locale, now: context.services.now()))
            }
            Button(text.kitChecked) {
                context.kitChecked(at: context.services.now())
            }
            .disabled(context.kitCreatedAt == nil)
        } header: {
            Text(text.kitReminderHeader)
        } footer: {
            ForkMacBackupCaption(text.kitReminderFooter)
        }
    }

    // MARK: Other Mac

    private var otherMacSection: some View {
        Section {
            Button(text.kitOpenOther) { openKit() }
            ForkMacBackupCaption(text.kitOpenOtherCaption)
            if let kit = importedKit {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: text.kitFoundFor, kit.repository.clientIdentity.description,
                                ForkMacBackupDay.text(kit.createdAt, locale: locale, now: context.services.now())))
                        .font(.callout)
                    if kit.secrets != nil {
                        SecureField(text.passphrase, text: $kitPassphrase)
                    }
                    HStack {
                        Spacer()
                        Button(text.continueAction) { continueWithKit(kit) }
                            .buttonStyle(.borderedProminent)
                            .tint(ForkMacBackupStyle.accent)
                            .disabled(kit.secrets != nil && kitPassphrase.isEmpty)
                    }
                    if let kitProblem {
                        ForkMacBackupCaption(kitProblem, color: .orange)
                    }
                }
            }
        } header: {
            Text(text.kitOtherHeader)
        }
    }

    // MARK: Actions

    private var document: ForkMacBackupKitDocument? {
        guard let repository = context.repository else { return nil }
        return ForkMacBackupKitDocument(text: text, repository: repository, profileName: context.profile?.name,
                                        appName: ForkMacBackupAppName.current, createdAt: context.services.now(),
                                        locale: locale)
    }

    private func savePDF() {
        guard let document, let data = ForkMacBackupKitDocument.pdf(document) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = text.kitFileName + ".pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            write(data, to: url)
        }
    }

    private func printPDF() {
        guard let document, let data = ForkMacBackupKitDocument.pdf(document), let pdf = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.showsPrintPanel = true
        operation.run()
        context.kitMade(at: context.services.now())
    }

    private func saveFile() {
        guard let repository = context.repository else { return }
        let make: (ForkMacBackupSealedSecrets?) -> Void = { sealed in
            let file = ForkMacBackupKitFile(createdAt: context.services.now(),
                                            createdBy: ForkMacBackupAppName.current,
                                            kopiaVersion: ForkMacBackupKit.kopiaVersion, repository: repository,
                                            profileName: context.profile?.name, secrets: sealed)
            guard let data = file.encoded() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupKitFile.fileExtension) ?? .json]
            panel.nameFieldStringValue = text.kitFileName + "." + ForkMacBackupKitFile.fileExtension
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                write(data, to: url)
            }
        }
        guard includeSecrets else {
            make(nil)
            return
        }
        busy = true
        let phrase = passphrase
        context.readSecrets { secrets in
            guard let secrets else {
                busy = false
                warning = text.kitSecretsUnavailable
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let sealed = try? ForkMacBackupKitCrypto.seal(secrets, passphrase: phrase)
                DispatchQueue.main.async {
                    busy = false
                    guard let sealed else {
                        warning = text.kitSecretsUnavailable
                        return
                    }
                    make(sealed)
                }
            }
        }
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            context.kitMade(at: context.services.now())
            message = String(format: text.kitSaved, url.lastPathComponent)
            warning = isInsideSource(url) ? text.kitInsideBackup : nil
        } catch {
            warning = text.fileNotSaved
        }
    }

    /// Plan §9.1: a kit only inside a folder that is backed up is no kit.
    private func isInsideSource(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/Volumes/") { return false }
        return context.effectiveSources.contains { path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
    }

    private func copyFields() {
        guard let repository = context.repository else { return }
        let lines = ForkMacBackupKitDocument.fields(text: text, repository: repository).map { "\($0.0): \($0.1)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        message = text.kitCopied
    }

    private func openKit() {
        kitProblem = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ForkMacBackupKitFile.fileExtension) ?? .json, .json]
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let kit = ForkMacBackupKitFile.decode(data) else {
                kitProblem = text.kitUnreadable
                return
            }
            importedKit = kit
        }
    }

    private func continueWithKit(_ kit: ForkMacBackupKitFile) {
        guard let sealed = kit.secrets else {
            open(.wizard(.kit(kit, nil)))
            return
        }
        busy = true
        let phrase = kitPassphrase
        DispatchQueue.global(qos: .userInitiated).async {
            let secrets = ForkMacBackupKitCrypto.open(sealed, passphrase: phrase)
            DispatchQueue.main.async {
                busy = false
                guard let secrets else {
                    kitProblem = text.passphraseWrong
                    return
                }
                open(.wizard(.kit(kit, secrets)))
            }
        }
    }
}

// MARK: - The PDF

/// One A4 page, printed light whatever the Mac's appearance: the repository,
/// what else is needed, and the four commands that reach the backups without
/// the app.
struct ForkMacBackupKitDocument: View {
    let text: ForkMacBackupSettingsStrings
    let repository: ForkMacBackupRepository
    let profileName: String?
    let appName: String
    let createdAt: Date
    let locale: Locale

    static let pageSize = CGSize(width: 595, height: 842)
    private static let teal = Color(red: 0.0, green: 0.55, blue: 0.58)

    static func fields(text: ForkMacBackupSettingsStrings, repository: ForkMacBackupRepository) -> [(String, String)] {
        var rows: [(String, String)] = [
            (text.kitFieldType, repository.serverFlavor == .minio ? "S3 · MinIO" : "S3"),
            (text.kitFieldEndpoint, repository.endpoint.hostAndPort + (repository.endpoint.tls ? " (HTTPS)" : " (HTTP)")),
        ]
        if !repository.endpoint.observedIPs.isEmpty {
            rows.append((text.kitFieldObserved, repository.endpoint.observedIPs.joined(separator: ", ")))
        }
        rows.append((text.kitFieldBucket, repository.bucket))
        if !repository.prefix.isEmpty { rows.append((text.kitFieldPrefix, repository.prefix)) }
        rows.append((text.kitFieldRegion, repository.region))
        rows.append((text.kitFieldAccessKey, repository.accessKeyID ?? "–"))
        rows.append((text.kitFieldUniqueID, repository.expectedUniqueID ?? "–"))
        rows.append((text.kitFieldIdentity, repository.clientIdentity.description))
        rows.append((text.kitFieldKopia, ForkMacBackupKit.kopiaVersion))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                section(text.kitPDFRepository) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(Array(Self.fields(text: text, repository: repository).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                Text(row.0)
                                    .foregroundStyle(Color.black.opacity(0.55))
                                Text(row.1)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                    .font(.system(size: 9.5))
                }
                section(text.kitPDFSecrets) {
                    VStack(alignment: .leading, spacing: 8) {
                        handwritten(text.kitFieldPassword)
                        handwritten(text.kitFieldSecretKey)
                        Text(text.kitPDFSecretsNote)
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
                section(String(format: text.kitPDFWithout, appName)) {
                    VStack(alignment: .leading, spacing: 7) {
                        let commands = ForkMacBackupKit.rescueCommands(repository, restoreFolder: "~/" + text.kitRestoredFolder)
                        ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 15, height: 15)
                                    .background(Circle().fill(Self.teal))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(text.kitStep(index))
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.black)
                                    Text(command)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.black)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.05)))
                                }
                            }
                        }
                        Text(String(format: text.kitPDFChecksum, ForkMacBackupKit.kopiaArchiveSHA256))
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
                section(String(format: text.kitPDFWith, appName)) {
                    Text(String(format: text.kitPDFWithSteps, appName))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 18)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lifepreserver.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.kitTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(String(format: text.kitPDFSubtitle, appName, ForkMacBackupFormat.dayAndTime(createdAt, locale: locale)))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            if let profileName {
                Text(profileName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Self.teal, Color(red: 0.0, green: 0.42, blue: 0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var footer: some View {
        HStack {
            Text(text.kitPDFKeepAway)
            Spacer()
            Text(String(format: text.kitPDFFingerprint, ForkMacBackupKit.fingerprint(repository)))
                .font(.system(size: 7.5, design: .monospaced))
        }
        .font(.system(size: 8))
        .foregroundStyle(Color.black.opacity(0.55))
        .padding(.horizontal, 36)
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5), alignment: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased(with: locale))
                .font(.system(size: 9, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(Self.teal)
            content()
        }
    }

    private func handwritten(_ label: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.black.opacity(0.7))
                .fixedSize()
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 0.6)
        }
        .frame(height: 16)
    }

    /// The page as a PDF, drawn by `ImageRenderer` into a PDF context.
    @MainActor
    static func pdf(_ document: ForkMacBackupKitDocument) -> Data? {
        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = ProposedViewSize(pageSize)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        renderer.render { _, draw in
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data.length > 0 ? data as Data : nil
    }
}
