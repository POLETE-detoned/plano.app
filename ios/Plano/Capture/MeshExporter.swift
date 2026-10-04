import ARKit

/// Exporta las `ARMeshAnchor` de la sesión a un PLY binario en coordenadas de mundo,
/// con la clasificación de ARKit por cara (ver docs/FORMATO_PLANO.md).
enum MeshExporter {
    @discardableResult
    static func writePLY(anchors: [ARMeshAnchor], to url: URL) throws -> Bool {
        guard !anchors.isEmpty else { return false }

        var vertexData = Data()
        var faceData = Data()
        var vertexCount = 0
        var faceCount = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let base = UInt32(vertexCount)

            let vertices = geometry.vertices
            let vPointer = vertices.buffer.contents()
            for i in 0..<vertices.count {
                let p = vPointer.advanced(by: vertices.offset + vertices.stride * i)
                    .assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let world = anchor.transform * SIMD4<Float>(p.0, p.1, p.2, 1)
                append(&vertexData, world.x)
                append(&vertexData, world.y)
                append(&vertexData, world.z)
            }
            vertexCount += vertices.count

            let faces = geometry.faces
            let fPointer = faces.buffer.contents()
            let classification = geometry.classification
            for i in 0..<faces.count {
                faceData.append(UInt8(3))
                for k in 0..<3 {
                    let offset = (i * faces.indexCountPerPrimitive + k) * faces.bytesPerIndex
                    let index: UInt32 = faces.bytesPerIndex == 4
                        ? fPointer.advanced(by: offset).assumingMemoryBound(to: UInt32.self).pointee
                        : UInt32(fPointer.advanced(by: offset).assumingMemoryBound(to: UInt16.self).pointee)
                    append(&faceData, base + index)
                }
                var label: UInt8 = 0
                if let classification {
                    label = classification.buffer.contents()
                        .advanced(by: classification.offset + classification.stride * i)
                        .assumingMemoryBound(to: UInt8.self).pointee
                }
                faceData.append(label)
            }
            faceCount += faces.count
        }

        let header = """
        ply
        format binary_little_endian 1.0
        comment Plano · ARKit mesh, world coordinates (Y up, metres)
        element vertex \(vertexCount)
        property float x
        property float y
        property float z
        element face \(faceCount)
        property list uchar uint vertex_indices
        property uchar classification
        end_header

        """
        var data = Data(header.utf8)
        data.append(vertexData)
        data.append(faceData)
        try data.write(to: url, options: .atomic)
        return true
    }

    private static func append<T>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) } // arm64: little-endian
    }
}
