import AppKit
import Testing
import WebKit
import LowkeyCore
@testable import Lowkey

/// No windows are shown, no real profiles/config are used, and no key presses are sent.
@MainActor @Suite(.serialized) struct ProfileLocationTests {
    private func fixture() throws -> (AppController, BrowserWindowController, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-profile-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = AppController(store: Store(configURL: folder.appendingPathComponent("config.json")))
        let browser = BrowserWindowController(kind: .ordinary,
                                              startURL: URL(string: "http://127.0.0.1:1/")!,
                                              dataStore: .nonPersistent(), app: app)
        return (app, browser, folder)
    }

    @Test func forcedLocationKeepsTheExactWebViewAndProfileAndIsOneShot() throws {
        let (app, browser, folder) = try fixture()
        defer { browser.close(); try? FileManager.default.removeItem(at: folder); withExtendedLifetime(app) {} }
        let webView = browser.webView
        let dataStore = webView.configuration.websiteDataStore
        let address = URL(string: "http://127.0.0.1:1/sign-in")!
        browser.loadInCurrentProfile(address)
        #expect(browser.webView === webView)
        #expect(browser.webView.configuration.websiteDataStore === dataStore)
        #expect(!browser.consumeProfileLocation(URL(string: "http://127.0.0.1:1/other")!))
        #expect(browser.consumeProfileLocation(address))
        #expect(!browser.consumeProfileLocation(address))
        #expect(app.ordinaryWindows.isEmpty)
        #expect(app.siteWindows.isEmpty)
        #expect(browser.popups.isEmpty)
    }

    @Test func savedSiteKeepsItsProfileAndRulesForAnExternalLocation() throws {
        let (app, unused, folder) = try fixture()
        defer { unused.close(); try? FileManager.default.removeItem(at: folder) }
        let site = Site(alias: "demo", startURL: "http://localhost:1/")
        var config = app.store.config
        config.sites = [site]
        #expect(app.store.update(config).isEmpty)
        let browser = BrowserWindowController(kind: .saved(site.id), startURL: site.url!,
                                              dataStore: .nonPersistent(), app: app)
        defer { browser.close(); NSWindow.removeFrame(usingName: SiteWindowPlacement(siteID: site.id).name) }
        let dataStore = browser.webView.configuration.websiteDataStore
        let address = URL(string: "http://127.0.0.1:1/sign-in")!
        #expect(LinkPolicy.decide(linkTo: address, site: browser.site) == .openExternally)
        browser.loadInCurrentProfile(address)
        #expect(browser.consumeProfileLocation(address))
        #expect(browser.webView.configuration.websiteDataStore === dataStore)
        #expect(app.store.config.sites == [site])
        #expect(LinkPolicy.decide(linkTo: address, site: browser.site) == .openExternally)
        #expect(browser.popups.isEmpty)
        #expect(app.ordinaryWindows.isEmpty)
    }

    @Test func regularLoadClearsTheOverride() throws {
        let (app, browser, folder) = try fixture()
        defer { browser.close(); try? FileManager.default.removeItem(at: folder); withExtendedLifetime(app) {} }
        let address = URL(string: "http://127.0.0.1:1/sign-in")!
        browser.loadInCurrentProfile(address)
        browser.load(URL(string: "http://127.0.0.1:1/home")!)
        #expect(!browser.consumeProfileLocation(address))
    }

    @Test func missingTargetNeverFallsBackToAnotherProfile() throws {
        let (app, browser, folder) = try fixture()
        defer { browser.close(); try? FileManager.default.removeItem(at: folder) }
        #expect(app.submit("http://127.0.0.1:1/sign-in", target: nil, newWindow: true,
                           inCurrentProfile: true) != nil)
        #expect(app.ordinaryWindows.isEmpty)
        #expect(app.store.history.entries.isEmpty)
    }

    @Test func invalidLocationDoesNotLoadOrRecordAnything() throws {
        let (app, browser, folder) = try fixture()
        defer { browser.close(); try? FileManager.default.removeItem(at: folder) }
        #expect(app.submit("not a web address", target: browser, newWindow: false,
                           inCurrentProfile: true) != nil)
        #expect(browser.webView.url == nil)
        #expect(app.store.history.entries.isEmpty)
    }
}
