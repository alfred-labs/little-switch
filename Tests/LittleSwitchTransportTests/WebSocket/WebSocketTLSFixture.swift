import NIOSSL

/// Synthetic loopback material generated for these tests; never trusted by the default client.
enum WebSocketTLSFixture {
    static func contexts(wrongHostname: Bool = false) throws -> (server: NIOSSLContext, client: NIOSSLContext) {
        let certificate = try NIOSSLCertificate(
            bytes: Array((wrongHostname ? wrongHostnameCertificate : loopbackCertificate).utf8), format: .pem)
        let key = try NIOSSLPrivateKey(bytes: Array(privateKey.utf8), format: .pem)
        let server = try NIOSSLContext(
            configuration: .makeServerConfiguration(
                certificateChain: [.certificate(certificate)], privateKey: .privateKey(key)))
        var client = TLSConfiguration.makeClientConfiguration()
        client.trustRoots = .certificates([certificate])
        return (server, try NIOSSLContext(configuration: client))
    }

    private static let loopbackCertificate = """
        -----BEGIN CERTIFICATE-----
        MIIBoTCCAUegAwIBAgIJAOrIy8XgIaIuMAoGCCqGSM49BAMCMCoxKDAmBgNVBAMM
        H0xpdHRsZVN3aXRjaCBsb29wYmFjayB0ZXN0IG9ubHkwIBcNMjYwOTI4MTMyNjQ5
        WhgPMjEyNjA5MDQxMzI2NDlaMCoxKDAmBgNVBAMMH0xpdHRsZVN3aXRjaCBsb29w
        YmFjayB0ZXN0IG9ubHkwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAS8vfMpszZb
        uxpf6wIbe+wMCCCUpWcBf+IDWw0/X3LnR5RgMhWHUtGtb2e8BkQ9tVOHpJFpX9MK
        5wYkPBTCwmLHo1QwUjAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwDwYDVR0T
        AQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAoQwEwYDVR0lBAwwCgYIKwYBBQUHAwEw
        CgYIKoZIzj0EAwIDSAAwRQIgElDSs2wRcTwHIRRM5bY1zBTMX4ugwGoF6jMeSIkw
        28sCIQDUDTFsqfa2HlLGtvZzCczfCBjGGvCRokzHs8qUH/YOtg==
        -----END CERTIFICATE-----
        """

    private static let wrongHostnameCertificate = """
        -----BEGIN CERTIFICATE-----
        MIIBrjCCAVOgAwIBAgIJAOw/yjRjG3WtMAoGCCqGSM49BAMCMDAxLjAsBgNVBAMM
        JUxpdHRsZVN3aXRjaCB3cm9uZyBob3N0bmFtZSB0ZXN0IG9ubHkwIBcNMjYwOTI4
        MTMyNjQ5WhgPMjEyNjA5MDQxMzI2NDlaMDAxLjAsBgNVBAMMJUxpdHRsZVN3aXRj
        aCB3cm9uZyBob3N0bmFtZSB0ZXN0IG9ubHkwWTATBgcqhkjOPQIBBggqhkjOPQMB
        BwNCAAS8vfMpszZbuxpf6wIbe+wMCCCUpWcBf+IDWw0/X3LnR5RgMhWHUtGtb2e8
        BkQ9tVOHpJFpX9MK5wYkPBTCwmLHo1QwUjAaBgNVHREEEzARgg9pbnZhbGlkLmV4
        YW1wbGUwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAoQwEwYDVR0lBAww
        CgYIKwYBBQUHAwEwCgYIKoZIzj0EAwIDSQAwRgIhAL0VtB/gZgxcLs4dNZdepLez
        /5t/kpYPGv8Te7/pnFmbAiEAse5sz0qHlnbhzi9fH/aLoZBhCVcdxOL9MvWP64R5
        A8I=
        -----END CERTIFICATE-----
        """

    private static let privateKey = """
        -----BEGIN EC PRIVATE KEY-----
        MHcCAQEEIGJpK+Pwoxi4acNyJfGNRV4vRYnJJoUvhY5QsTtPYEY9oAoGCCqGSM49
        AwEHoUQDQgAEvL3zKbM2W7saX+sCG3vsDAgglKVnAX/iA1sNP19y50eUYDIVh1LR
        rW9nvAZEPbVTh6SRaV/TCucGJDwUwsJixw==
        -----END EC PRIVATE KEY-----
        """
}
