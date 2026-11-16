import CoreGraphics

/// Crop rectangle (in source pixel coordinates) that fills `target` aspect ratio, centered.
public func aspectFillRect(source: CGSize, target: CGSize) -> CGRect {
    guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return .zero }
    let targetAspect = target.width / target.height
    let sourceAspect = source.width / source.height
    if sourceAspect > targetAspect {
        let w = (source.height * targetAspect).rounded()
        return CGRect(x: ((source.width - w) / 2).rounded(), y: 0, width: w, height: source.height)
    } else {
        let h = (source.width / targetAspect).rounded()
        return CGRect(x: 0, y: ((source.height - h) / 2).rounded(), width: source.width, height: h)
    }
}
