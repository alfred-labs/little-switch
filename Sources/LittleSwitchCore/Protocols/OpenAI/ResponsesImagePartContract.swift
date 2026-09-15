/// The generated Responses and Chat content projections deliberately leave image
/// parts opaque. These keys belong to the bounded image conversion, not a model capability.
enum ResponsesImagePartContract {
    enum Field: String {
        case imageURL = "image_url"
        case fileID = "file_id"
        case detail
        case url
    }

    enum Kind: String {
        case inputImage = "input_image"
        case chatImage = "image_url"
        case chatText = "text"
    }
}
