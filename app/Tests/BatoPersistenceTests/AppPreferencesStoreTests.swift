import BatoCore
import Foundation
import Testing
@testable import BatoPersistence

struct AppPreferencesStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString)")
    }

    @Test func defaultsToDuckDuckGoWithoutAFile() {
        let store = AppPreferencesStore(directory: directory())
        #expect(store.current().searchProvider == .duckDuckGo)
    }

    @Test func searchSuggestionsDefaultOnAndPersistWhenTurnedOff() throws {
        let dir = directory()
        #expect(AppPreferencesStore(directory: dir).current().searchSuggestions)
        try AppPreferencesStore(directory: dir).update { $0.searchSuggestions = false }
        #expect(!AppPreferencesStore(directory: dir).current().searchSuggestions)
    }

    @Test func fileWithoutTheSuggestionsKeyKeepsThemOn() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppPreferencesStore(directory: dir)
        try Data(#"{"searchProvider":"google"}"#.utf8).write(to: store.fileURL)
        #expect(store.current().searchSuggestions)
    }

    @Test func chosenProviderSurvivesANewStore() throws {
        let dir = directory()
        try AppPreferencesStore(directory: dir).update { $0.searchProvider = .brave }
        #expect(AppPreferencesStore(directory: dir).current().searchProvider == .brave)
    }

    @Test func unknownProviderFallsBackToDefaultAndKeepsTheFile() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppPreferencesStore(directory: dir)
        try Data(#"{"searchProvider":"nonesuch"}"#.utf8).write(to: store.fileURL)
        #expect(store.current().searchProvider == .duckDuckGo)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func corruptFileIsSetAsideAndDefaultsUsed() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppPreferencesStore(directory: dir)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.current().searchProvider == .duckDuckGo)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("corrupt").path))
        try store.update { $0.searchProvider = .google }
        #expect(AppPreferencesStore(directory: dir).current().searchProvider == .google)
    }

    @Test func commandBarUsesTheStoredProvider() throws {
        let store = AppPreferencesStore(directory: directory())
        try store.update { $0.searchProvider = .google }
        let result = CommandBarInput.resolve("swift concurrency", provider: store.current().searchProvider)
        #expect(result == .search(URL(string: "https://www.google.com/search?q=swift%20concurrency")!))
    }
}

struct OnboardingPreferencesTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString)")
    }

    @Test func onboardingIsPendingUntilCompletedAndAppearanceDefaultsToSystem() throws {
        let dir = directory()
        let fresh = AppPreferencesStore(directory: dir).current()
        #expect(!fresh.onboardingCompleted)
        #expect(fresh.appearance == .system)
        try AppPreferencesStore(directory: dir).update { $0.onboardingCompleted = true; $0.appearance = .dark }
        let reloaded = AppPreferencesStore(directory: dir).current()
        #expect(reloaded.onboardingCompleted)
        #expect(reloaded.appearance == .dark)
    }

    @Test func oldFileWithoutTheNewKeysStillLoads() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppPreferencesStore(directory: dir)
        try Data(#"{"searchProvider":"google","appearance":"sepia"}"#.utf8).write(to: store.fileURL)
        #expect(store.current().appearance == .system)
        #expect(store.current().searchProvider == .google)
    }
}
