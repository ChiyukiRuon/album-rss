#if os(iOS)
  import AlbumCore
  import Foundation
  import ImageIO
  import Nuke
  import Photos
  import UniformTypeIdentifiers

  /// 保存到相册：从端点的图片管线取原始数据（通常已经在缓存里），逐张写入。
  /// 相册不认识的格式（WebP、AVIF 等）先转成 JPEG。
  public struct PhotoLibrarySaver: ImageSaver {
    let pipeline: @MainActor @Sendable (Endpoint) -> ImagePipeline

    public init(pipeline: @escaping @MainActor @Sendable (Endpoint) -> ImagePipeline) {
      self.pipeline = pipeline
    }

    public func save(_ images: [ImageAsset], endpoint: Endpoint, progress: @escaping @Sendable (Int) -> Void)
      async throws
    {
      let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      guard status == .authorized || status == .limited else {
        throw APIError("没有相册的写入权限。请在系统“设置 → Album RSS → 照片”里允许添加照片")
      }
      let pipeline = await pipeline(endpoint)
      for (index, image) in images.enumerated() {
        guard let request = ImageRequests.original(image.url) else { throw APIError("图片地址无效") }
        let data: Data
        do {
          (data, _) = try await pipeline.data(for: request)
        } catch {
          throw APIError("图片下载失败，请检查网络后重试", isNetwork: true)
        }
        let (payload, type) = try Self.photoCompatible(data)
        do {
          try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = type
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: payload, options: options)
          }
        } catch {
          throw APIError("写入相册失败：\(error.localizedDescription)")
        }
        progress(index + 1)
      }
    }

    static func photoCompatible(_ data: Data) throws -> (Data, String) {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else {
        throw APIError("来源没有返回图片")
      }
      let identifier = type as String
      let supported: Set<String> = [
        UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, UTType.gif.identifier,
        UTType.tiff.identifier,
      ]
      if supported.contains(identifier) { return (data, identifier) }
      guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw APIError("无法读取这张图片") }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw APIError("无法转换图片格式") }
      var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
      properties[kCGImageDestinationLossyCompressionQuality] = 0.92
      CGImageDestinationAddImage(destination, image, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { throw APIError("无法转换图片格式") }
      return (output as Data, UTType.jpeg.identifier)
    }
  }
#endif
