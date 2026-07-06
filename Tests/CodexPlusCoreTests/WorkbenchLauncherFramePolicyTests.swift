import CoreGraphics
import CodexPlusCore

@MainActor
func runWorkbenchLauncherFramePolicyTests() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let defaultFrame = CGRect(x: 1364, y: 28, width: 48, height: 48)
    let cachedFrame = CGRect(x: 220, y: 340, width: 48, height: 48)

    expect(
        WorkbenchLauncherFramePolicy.frame(
            cachedFrame: cachedFrame,
            defaultFrame: defaultFrame,
            visibleFrames: [visibleFrame]
        ) == cachedFrame,
        "launcher frame policy restores cached frame inside the visible screen"
    )

    let offscreenCachedFrame = CGRect(x: -200, y: 340, width: 48, height: 48)
    expect(
        WorkbenchLauncherFramePolicy.frame(
            cachedFrame: offscreenCachedFrame,
            defaultFrame: defaultFrame,
            visibleFrames: [visibleFrame]
        ) == defaultFrame,
        "launcher frame policy falls back to default frame when cached frame is offscreen"
    )

    expect(
        WorkbenchLauncherFramePolicy.frame(
            cachedFrame: nil,
            defaultFrame: defaultFrame,
            visibleFrames: [visibleFrame]
        ) == defaultFrame,
        "launcher frame policy uses default frame without cached frame"
    )

    let secondaryVisibleFrame = CGRect(x: 1440, y: 0, width: 1200, height: 900)
    let secondaryCachedFrame = CGRect(x: 1600, y: 400, width: 48, height: 48)
    expect(
        WorkbenchLauncherFramePolicy.frame(
            cachedFrame: secondaryCachedFrame,
            defaultFrame: defaultFrame,
            visibleFrames: [visibleFrame, secondaryVisibleFrame]
        ) == secondaryCachedFrame,
        "launcher frame policy restores cached frame on another visible screen"
    )
}
