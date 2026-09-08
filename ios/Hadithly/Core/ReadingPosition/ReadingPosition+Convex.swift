import ConvexMobile

extension ReadingPosition {
    var convexWireValue: [String: ConvexEncodable?] {
        var result: [String: ConvexEncodable?] = [
            "schemaVersion": schemaVersion,
            "anchor": [
                "provider": anchor.provider,
                "collectionSlug": anchor.collectionSlug,
                "providerHadithId": anchor.providerHadithId,
            ] as [String: ConvexEncodable?],
            "contentVersion": contentVersion,
            "volumeId": volumeId,
            "pageKey": pageKey,
            "displayPageIndex": displayPageIndex,
            "rawPageOffset": rawPageOffset,
            "normalizedOffset": normalizedOffset,
            "layoutSignature": layoutSignature,
            "updatedAt": updatedAt,
        ]
        if let chapterId { result["chapterId"] = chapterId }
        return result
    }
}
