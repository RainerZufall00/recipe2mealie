import Foundation

struct MultipartForm {
    let boundary = "MealieImporter-\(UUID().uuidString)"
    private var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    var body: Data { parts + Data("--\(boundary)--\r\n".utf8) }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        parts.append(data)
        append("\r\n")
    }

    private mutating func append(_ string: String) {
        parts.append(Data(string.utf8))
    }
}
