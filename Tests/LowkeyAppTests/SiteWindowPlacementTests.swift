import AppKit
import Testing
@testable import Lowkey

/// No visible windows, synthetic keypresses, real aliases or real website profiles.
@MainActor @Suite(.serialized) struct SiteWindowPlacementTests {
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func restoresSizeAndPositionForTheSameSite() {
        let siteID = UUID()
        let placement = SiteWindowPlacement(siteID: siteID)
        defer { NSWindow.removeFrame(usingName: placement.name) }
        let first = makeWindow()
        placement.restore(first)
        let frame = NSRect(x: 220, y: 180, width: 700, height: 460)
        first.setFrame(frame, display: false)
        placement.save(first)
        first.close()

        let reopened = makeWindow()
        // A new persistence object models a recreated controller or a fresh app process.
        SiteWindowPlacement(siteID: siteID).restore(reopened)
        #expect(reopened.frame == frame)
        reopened.close()
    }

    @Test func differentSitesKeepIndependentFrames() {
        let a = SiteWindowPlacement(siteID: UUID())
        let b = SiteWindowPlacement(siteID: UUID())
        defer { NSWindow.removeFrame(usingName: a.name); NSWindow.removeFrame(usingName: b.name) }
        let window = makeWindow()
        a.restore(window)
        let frameA = NSRect(x: 120, y: 150, width: 600, height: 400)
        window.setFrame(frameA, display: false)
        a.save(window)
        b.restore(window)
        let frameB = NSRect(x: 260, y: 200, width: 800, height: 500)
        window.setFrame(frameB, display: false)
        b.save(window)

        a.restore(window)
        #expect(window.frame == frameA)
        b.restore(window)
        #expect(window.frame == frameB)
        window.close()
    }

    @Test func fullScreenTransitionDoesNotReplaceNormalFrame() {
        let siteID = UUID()
        let placement = SiteWindowPlacement(siteID: siteID)
        defer { NSWindow.removeFrame(usingName: placement.name) }
        let window = makeWindow()
        placement.restore(window)
        let normal = NSRect(x: 160, y: 160, width: 640, height: 440)
        window.setFrame(normal, display: false)
        placement.save(window)
        placement.willEnterFullScreen()
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        placement.save(window)

        let check = makeWindow()
        SiteWindowPlacement(siteID: siteID).restore(check)
        #expect(check.frame == normal)
        check.close()

        placement.willExitFullScreen()
        window.setFrame(normal, display: false)
        placement.didExitFullScreen(window)
        let changed = NSRect(x: 180, y: 180, width: 680, height: 450)
        window.setFrame(changed, display: false)
        placement.save(window)
        placement.restore(window)
        #expect(window.frame == changed)
        window.close()
    }
}
