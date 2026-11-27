import Contacts
import ContactsUI
import SwiftUI

struct PickedContactInfo: Sendable {
    let identifier: String
    let fullName: String
    let phone: String?
    let email: String?
    let birthdayComponents: DateComponents?
    let imageData: Data?
}

struct ContactPickerSheet: UIViewControllerRepresentable {
    let onSelect: (PickedContactInfo) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (PickedContactInfo) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (PickedContactInfo) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let fullName = [contact.givenName, contact.familyName]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let resolvedName = fullName.isEmpty ? contact.organizationName : fullName
            let info = PickedContactInfo(
                identifier: contact.identifier,
                fullName: resolvedName,
                phone: contact.phoneNumbers.first?.value.stringValue,
                email: contact.emailAddresses.first?.value as String?,
                birthdayComponents: contact.birthday,
                imageData: contact.thumbnailImageData ?? contact.imageData
            )
            onSelect(info)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
