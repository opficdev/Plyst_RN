//
//  ClipImageCodec.swift
//  Plyst
//
//  Created by opfic on 11/6/26.
//

import CoreGraphics
import Foundation
import ImageIO
import PlystCore
import UniformTypeIdentifiers

/// 이미지 형식과 크기 판독, 저장 전 검증, 축소본 생성
/// 파일 경로 규칙과 파일 쓰기는 소유하지 않음
/// 코어가 부르는 구현은 모든 오류를 선언된 코덱 오류로 변환
final class ClipImageCodec: ClipImageCoder {
    /// 저장 전 검증에서 축소 디코딩하는 긴 변의 최대 픽셀 수
    /// 검증이 원본 해상도 비트맵을 만들지 않게 함
    private static let validationPixelDimension = 64

    /// 파일을 메모리에 복사하지 않고 매핑해 읽음
    /// 코어가 순서 잠금을 쥔 동안 부르므로 읽는 도중 파일이 바뀌지 않음
    func properties(path: String) throws -> ClipImagePropertiesValue {
        do {
            return try Self.validated(Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped))
        } catch {
            throw Self.codecError(error)
        }
    }

    func thumbnail(
        path: String,
        image: ClipImageValue,
        maximumPixelDimension: Int64
    ) throws -> Data {
        do {
            return try Self.thumbnail(
                of: URL(fileURLWithPath: path),
                contentType: image.contentType,
                pixelWidth: Int(image.pixelWidth),
                pixelHeight: Int(image.pixelHeight),
                maximumPixelDimension: Int(maximumPixelDimension)
            )
        } catch {
            throw Self.codecError(error)
        }
    }

    /// 저장 전 검증
    /// 검증을 통과한 이미지의 형식과 크기를 코어 값으로 반환
    static func validated(_ data: Data) throws -> ClipImagePropertiesValue {
        // UniFFI 바이트 인자의 길이가 Int32이므로 초과분은 호출 전에 거부
        guard data.count <= Int32.max else { throw ClipImageFileError.writeFailed }
        let properties = try properties(of: data)
        return ClipImagePropertiesValue(
            contentType: properties.type,
            pixelWidth: Int64(properties.size.width),
            pixelHeight: Int64(properties.size.height)
        )
    }

    private static func codecError(_ error: any Error) -> ClipCodecError {
        if error is CancellationError { return .Cancelled }
        if let error = error as? ClipCodecError { return error }
        guard let error = error as? ClipImageFileError else { return .ReadFailed }
        return switch error {
        case .invalidImage, .unsupportedImage, .corruptedImage: .Corrupted
        case .readFailed: .ReadFailed
        default: .Unexpected
        }
    }

    private static func properties(of data: Data) throws -> (type: String, size: (width: Int, height: Int)) {
        try Task.checkCancellation()
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) else { throw ClipImageFileError.invalidImage }
        let type = identifier as String
        let supported = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        guard supported.contains(type), UTType(type)?.conforms(to: .image) == true else { throw ClipImageFileError.unsupportedImage }
        // ImageIO는 잘린 GIF도 남은 프레임만으로 statusComplete를 반환하므로 종료 바이트(0x3B)로 잘림을 판별
        if type == UTType.gif.identifier, data.last != 0x3B { throw ClipImageFileError.invalidImage }
        let count = CGImageSourceGetCount(source)
        guard 0 < count else { throw ClipImageFileError.invalidImage }
        // 원본 해상도 비트맵을 만들지 않도록 크기는 속성으로 읽고 무결성은 축소 디코딩으로 확인
        let validationOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: validationPixelDimension
        ] as CFDictionary
        var size = (width: 0, height: 0)
        for index in 0..<count {
            try Task.checkCancellation()
            // 프레임마다 즉시 디코딩하고 캐시를 해제하여 모든 프레임의 픽셀을 동시에 보관하지 않음
            let dimensions = try autoreleasepool {
                defer { CGImageSourceRemoveCacheAtIndex(source, index) }
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?,
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      0 < width, 0 < height,
                      CGImageSourceCreateThumbnailAtIndex(source, index, validationOptions) != nil,
                      CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else { throw ClipImageFileError.invalidImage }
                return (width: width, height: height)
            }
            if index == 0 { size = dimensions }
        }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw ClipImageFileError.invalidImage }
        return (type, size)
    }

    /// 원본을 Data로 적재하지 않고 첫 프레임을 표시 크기로 축소
    /// 저장된 파일은 변경하지 않음
    private static func thumbnail(
        of original: URL,
        contentType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        maximumPixelDimension: Int
    ) throws -> Data {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(original as CFURL, options),
              CGImageSourceGetType(source) as String? == contentType,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              properties[kCGImagePropertyPixelWidth] as? Int == pixelWidth,
              properties[kCGImagePropertyPixelHeight] as? Int == pixelHeight else {
            throw ClipCodecError.Corrupted
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw ClipCodecError.Corrupted
        }
        try Task.checkCancellation()
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipImageFileError.readFailed }
        return output as Data
    }
}
