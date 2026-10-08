import Foundation

@main
enum SystemProxyEnvironmentTests {
    static func main() {
        let settings: [String: Any] = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7890,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7891,
            "ExceptionsList": ["localhost", "*.example.com", "10.0.0.0/8", "<local>"]
        ]
        let resolved = SystemProxyEnvironment.resolve(inherited: ["PATH": "/usr/bin"], settings: settings)
        precondition(resolved["HTTP_PROXY"] == "http://127.0.0.1:7890")
        precondition(resolved["http_proxy"] == resolved["HTTP_PROXY"])
        precondition(resolved["HTTPS_PROXY"] == "http://127.0.0.1:7891")
        precondition(resolved["https_proxy"] == resolved["HTTPS_PROXY"])
        precondition(resolved["NO_PROXY"] == "localhost,.example.com,10.0.0.0/8")
        precondition(resolved["PATH"] == "/usr/bin")

        for key in ["HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy"] {
            for value in ["explicit", ""] {
                let result = SystemProxyEnvironment.resolve(inherited: [key: value], settings: settings)
                precondition(result[key] == value, "Explicit \(key) must be preserved")
                precondition(result[key == key.lowercased() ? key.uppercased() : key.lowercased()] == nil)
            }
        }
        for key in ["ALL_PROXY", "all_proxy"] {
            let inherited = [key: "socks5://localhost:1080"]
            precondition(SystemProxyEnvironment.resolve(inherited: inherited, settings: settings) == inherited)
        }
        for configuration: [String: Any] in [
            [:],
            ["HTTPEnable": 0, "HTTPProxy": "localhost", "HTTPPort": 7890],
            ["HTTPEnable": 1, "HTTPProxy": "", "HTTPPort": 7890],
            ["HTTPEnable": 1, "HTTPProxy": "localhost", "HTTPPort": 0],
            ["HTTPEnable": 1, "HTTPProxy": "localhost", "HTTPPort": 65536],
            ["HTTPEnable": 1, "HTTPProxy": "localhost"],
            ["ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "http://localhost/proxy.pac"],
            ["SOCKSEnable": 1, "SOCKSProxy": "localhost", "SOCKSPort": 1080]
        ] {
            precondition(SystemProxyEnvironment.resolve(inherited: [:], settings: configuration).isEmpty)
        }
        let fingerprint = SystemProxyEnvironment.proxyValues(in: resolved)
        var changed = settings
        changed["HTTPPort"] = 8080
        precondition(fingerprint != SystemProxyEnvironment.proxyValues(in:
            SystemProxyEnvironment.resolve(inherited: [:], settings: changed)))
        precondition(fingerprint != SystemProxyEnvironment.proxyValues(in: [:]))
        var unrelatedChange = resolved
        unrelatedChange["PATH"] = "/bin"
        precondition(fingerprint == SystemProxyEnvironment.proxyValues(in: unrelatedChange))
        print("System proxy environment tests passed")
    }
}
