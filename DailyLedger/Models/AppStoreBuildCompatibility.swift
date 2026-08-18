import Foundation

// App Store build compatibility helpers shared by reporting code.
extension StringProtocol {
    var nilIfEmpty: String? {
        isEmpty ? nil : String(self)
    }
}

extension AccountNature {
    // Receivable/payable presentation is derived dynamically from the sign of
    // payment/control account balances. These aliases preserve the report
    // builder's generic classification checks without storing extra account types.
    static var receivable: AccountNature { .control }
    static var payable: AccountNature { .control }
}
