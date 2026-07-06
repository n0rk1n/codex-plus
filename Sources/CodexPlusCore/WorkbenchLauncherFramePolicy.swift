import CoreGraphics

public enum WorkbenchLauncherFramePolicy {
    public static func frame(
        cachedFrame: CGRect?,
        defaultFrame: CGRect,
        visibleFrames: [CGRect]
    ) -> CGRect {
        guard
            let cachedFrame,
            cachedFrame.width > 0,
            cachedFrame.height > 0,
            visibleFrames.contains(where: { $0.contains(cachedFrame) })
        else {
            return defaultFrame
        }

        return cachedFrame
    }
}
