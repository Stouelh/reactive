import SwiftUI

/// Singleton bridge so Toolbox.swift can trigger sign-in on the ViewModel
@Observable
final class ChattViewModelHolder {
    static let shared = ChattViewModelHolder()
    private init() {}
    var vm: ChattViewModel? = nil
}
