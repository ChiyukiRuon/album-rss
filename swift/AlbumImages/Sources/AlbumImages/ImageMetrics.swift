import CoreGraphics
import Foundation
import ImageIO
import Nuke

public enum ImageMetrics {
  /// 原图显示时的像素尺寸：EXIF 方向为 5–8（旋转 90°）时交换宽高，与浏览器的 naturalWidth/Height 一致。
  /// 只读取文件头，不解码像素。
  public static func pixelSize(of data: Data) -> CGSize? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  /// 查看器里解码的最长边：控制在约 1600 万像素以内，长图按宽度保持清晰
  public static func viewerMaxPixelSize(for size: CGSize?, maxPixels: Double = 16_000_000) -> Float {
    guard let size, size.width > 0, size.height > 0 else { return 4096 }
    let scale = min(1, (maxPixels / (size.width * size.height)).squareRoot())
    return Float(max(size.width, size.height) * scale)
  }
}

public enum ImageRequests {
  /// 卡片与缩略图：按显示框（点）填充裁切的缩略图，解码时就缩小，不解码原图
  public static func thumbnail(_ url: String, size: CGSize) -> ImageRequest? {
    guard let url = URL(string: url), size.width > 0, size.height > 0 else { return nil }
    var request = ImageRequest(url: url)
    request.thumbnail = ImageRequest.ThumbnailOptions(size: size, unit: .points, contentMode: .aspectFill)
    return request
  }

  /// 查看器：按原图尺寸限制解码大小；尺寸未知时最长边 4096
  public static func viewer(_ url: String, originalSize: CGSize?) -> ImageRequest? {
    guard let url = URL(string: url) else { return nil }
    var request = ImageRequest(url: url, priority: .high)
    request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: ImageMetrics.viewerMaxPixelSize(for: originalSize))
    return request
  }

  /// 原始数据：测量尺寸、保存与分享
  public static func original(_ url: String) -> ImageRequest? {
    URL(string: url).map { ImageRequest(url: $0) }
  }
}
