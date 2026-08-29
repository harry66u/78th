import CryptoKit
import Foundation
import ScheduleEngine

/// Verifying and describing the shared rotation file.
///
/// The rotation is the one thing the server tells the app that changes what it
/// displays, so it is signed. An unverified file is discarded, not applied with
/// a warning: a wrong rotation is exactly the failure this app cannot have.
enum RotationSync {

    /// Decodes the payload only after the Ed25519 signature checks out against
    /// the public key compiled into the app.
    static func verifiedRotation(from signed: SignedRotationFile) throws -> RotationFile {
        guard let publicKeyData = SupabaseConfiguration.rotationPublicKey() else {
            throw RotationFileError.unknownKey(signed.keyID)
        }
        guard let payload = signed.payloadData, let signature = signed.signatureData else {
            throw RotationFileError.malformedPayload
        }

        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard key.isValidSignature(signature, for: payload) else {
            throw RotationFileError.badSignature
        }

        return try RotationFile.decoder.decode(RotationFile.self, from: payload)
    }

    static func describe(_ report: RotationMergeReport) -> String {
        var parts: [String] = []
        if report.datesUpdated > 0 {
            parts.append("\(report.datesUpdated) \(report.datesUpdated == 1 ? "date" : "dates") updated")
        }
        if !report.templatesUpdated.isEmpty {
            parts.append("bell times updated for \(report.templatesUpdated.joined(separator: ", "))")
        }
        if !report.templatesAdded.isEmpty {
            parts.append("added \(report.templatesAdded.joined(separator: ", "))")
        }
        if !report.unresolvedTemplateNames.isEmpty {
            parts.append("could not match \(report.unresolvedTemplateNames.joined(separator: ", ")), so those dates were left alone")
        }
        guard !parts.isEmpty else { return "Nothing changed." }
        return parts.joined(separator: ", ") + "."
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case RotationFileError.badSignature:
            return "That calendar file did not verify, so it was not applied."
        case RotationFileError.malformedPayload:
            return "That calendar file could not be read."
        case RotationFileError.unknownKey:
            return "This build cannot verify calendar files yet."
        case SocialBackendError.notConfigured:
            return "This build has no school calendar to fetch."
        default:
            return "Could not fetch the school calendar: \(error.localizedDescription)"
        }
    }
}
