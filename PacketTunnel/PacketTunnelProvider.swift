//
//  PacketTunnelProvider.swift
//  PacketTunnel
//

import NetworkExtension
import NEKit
import CocoaLumberjackSwift
import Yaml

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    var interface: TUNInterface!
    var enablePacketProcessing = false
    
    var proxyPort: Int!
    
    var proxyServer: ProxyServer!
    
    var lastPath:NWPath?
    
    var started:Bool = false
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
//        DDLog.removeAllLoggers()
//        DDLog.add(DDASLLogger.sharedInstance, with: DDLogLevel.info)
        ObserverFactory.currentFactory = DebugObserverFactory()
        
        guard let conf = (protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration else{
            exit(EXIT_FAILURE)
        }
        
//        let SetConnect = UserDefaults.init(suiteName: "group.com.lightningCat")?.string(forKey: "SetConnect")
//        if SetConnect ?? "" == "0" {
//            exit(1)
//            return
//        }
        
        let ss_adder = conf["ss_address"] as! String
        let ss_port = conf["ss_port"] as! Int
//        let method = conf["ss_method"] as! String
        let password = conf["ss_password"] as!String
        
//         ss_adder = "52.229.171.150"
//         ss_port = 7702
//        //        let method = conf["ss_method"] as! String
//         password = "elina"
        // SSR Httpsimple
        //        let obfuscater = ShadowsocksAdapter.ProtocolObfuscater.HTTPProtocolObfuscater.Factory(hosts:["intl.aliyun.com","cdn.aliyun.com"], customHeader:nil)
        
        // Origin
        let obfuscater = ShadowsocksAdapter.ProtocolObfuscater.OriginProtocolObfuscater.Factory()

        var algorithm:CryptoAlgorithm
        algorithm = .AES256CFB

        let ssAdapterFactory = ShadowsocksAdapterFactory(serverHost: ss_adder, serverPort: ss_port, protocolObfuscaterFactory:obfuscater, cryptorFactory: ShadowsocksAdapter.CryptoStreamProcessor.Factory(password: password, algorithm: algorithm), streamObfuscaterFactory: ShadowsocksAdapter.StreamObfuscater.OriginStreamObfuscater.Factory())
        
        let directAdapterFactory = DirectAdapterFactory()
        
        //Get lists from conf
        let yaml_str = conf["Steamconf"] as!String
        let value = try! Yaml.load(yaml_str)
        
        var UserRules:[NEKit.Rule] = []
        
        for each in (value["rule"].array! ){
            let ruleType = each["type"].string!
            switch ruleType {
                
            case "domainlist":
                var rule_array : [NEKit.DomainListRule.MatchCriterion] = []
                for dom in each["criteria"].array!{
                    let raw_dom = dom.string!
                    let index = raw_dom.index(raw_dom.startIndex, offsetBy: 1)
                    let index2 = raw_dom.index(raw_dom.startIndex, offsetBy: 2)
                    let typeStr = raw_dom.substring(to: index)
                    let url = raw_dom.substring(from: index2)
                    
                    if typeStr == "s"{
                        rule_array.append(DomainListRule.MatchCriterion.suffix(url))
                    }else if typeStr == "k"{
                        rule_array.append(DomainListRule.MatchCriterion.keyword(url))
                    }else if typeStr == "p"{
                        rule_array.append(DomainListRule.MatchCriterion.prefix(url))
                    }else if typeStr == "r"{
                        // ToDo:
                        // shoud be complete
                    }
                }
                
                //httpgithubdirect
                var httpgithubdirect: [String] = [ ]
                httpgithubdirect = conf["httpgithubdirect"] as! Array
                do {for line in httpgithubdirect {
                    let string1 = NSString(format: "%@" , line as CVarArg)
                    rule_array.append(DomainListRule.MatchCriterion.suffix(string1 as String)) }}catch {}
                
                UserRules.append(DomainListRule(adapterFactory: directAdapterFactory, criteria: rule_array))
            case "domainlistproxy":
                var rule_array : [NEKit.DomainListRule.MatchCriterion] = []
                for dom in each["criteria"].array!{
                    let raw_dom = dom.string!
                    let index = raw_dom.index(raw_dom.startIndex, offsetBy: 1)
                    let index2 = raw_dom.index(raw_dom.startIndex, offsetBy: 2)
                    let typeStr = raw_dom.substring(to: index)
                    let url = raw_dom.substring(from: index2)
                    
                    if typeStr == "s"{
                        rule_array.append(DomainListRule.MatchCriterion.suffix(url))
                    }else if typeStr == "k"{
                        rule_array.append(DomainListRule.MatchCriterion.keyword(url))
                    }else if typeStr == "p"{
                        rule_array.append(DomainListRule.MatchCriterion.prefix(url))
                    }else if typeStr == "r"{
                        // ToDo:
                        // shoud be complete
                    }
                }
                
                //github拉取的配置
                var httpgithub: [String] = [ ]
                    httpgithub = conf["httpgithub"] as! Array
                    do {for line in httpgithub {
                        let string = NSString(format: "%@" , line as CVarArg)
                        rule_array.append(DomainListRule.MatchCriterion.suffix(string as String)) }}catch {}
                
                UserRules.append(DomainListRule(adapterFactory: ssAdapterFactory, criteria: rule_array))
                
            case "iplist":
                let ipArray = each["criteria"].array!.map{$0.string!}
                UserRules.append(try! IPRangeListRule(adapterFactory: directAdapterFactory, ranges: ipArray))
            default:
                break
            }
        }
        
        
        // Rules
        let chinaRule = CountryRule(countryCode: "CN", match: true, adapterFactory: directAdapterFactory)
        let unKnowLoc = CountryRule(countryCode: "--", match: true, adapterFactory: ssAdapterFactory)
        let dnsFailRule = DNSFailRule(adapterFactory: ssAdapterFactory)
        
        let allRule = AllRule(adapterFactory: directAdapterFactory)
        UserRules.append(contentsOf: [chinaRule,unKnowLoc,dnsFailRule,allRule])
        
        let manager = RuleManager(fromRules: UserRules, appendDirect: true)
        
        RuleManager.currentManager = manager
        proxyPort =  9090
        
        //  RawSocketFactory.TunnelProvider = self
        
        // the `tunnelRemoteAddress` is meaningless because we are not creating a tunnel.
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "8.8.8.8")
        networkSettings.mtu = 1500
        
        let ipv4Settings = NEIPv4Settings(addresses: ["192.169.89.1"], subnetMasks: ["255.255.255.0"])
        if enablePacketProcessing {
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            ipv4Settings.excludedRoutes = [
                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"),
            ]
        }
        networkSettings.iPv4Settings = ipv4Settings
        
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: proxyPort)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: proxyPort)
        proxySettings.excludeSimpleHostnames = true
        // This will match all domains
        proxySettings.matchDomains = [""]
        proxySettings.exceptionList = ["api.smoot.apple.com","configuration.apple.com","xp.apple.com","smp-device-content.apple.com","guzzoni.apple.com","captive.apple.com","*.ess.apple.com","*.push.apple.com","*.push-apple.com.akadns.net"]
        networkSettings.proxySettings = proxySettings
        
        if enablePacketProcessing {
            let DNSSettings = NEDNSSettings(servers: ["114.114.114.114","223.6.6.6"])
            DNSSettings.matchDomains = [""]
            DNSSettings.matchDomainsNoSearch = false
            networkSettings.dnsSettings = DNSSettings
        }
        
        setTunnelNetworkSettings(networkSettings) {
            error in
            guard error == nil else {
                DDLogError("Encountered an error setting up the network: \(error.debugDescription)")
                completionHandler(error)
                return
            }
            
            
            if !self.started{
                self.proxyServer = GCDHTTPProxyServer(address: IPAddress(fromString: "127.0.0.1"), port: NEKit.Port(port: UInt16(self.proxyPort)))
                try! self.proxyServer.start()
                self.addObserver(self, forKeyPath: "defaultPath", options: .initial, context: nil)
            }else{
                self.proxyServer.stop()
                try! self.proxyServer.start()
            }
            
            completionHandler(nil)
            
            
            if self.enablePacketProcessing {
                if self.started{
                    self.interface.stop()
                }
                
                self.interface = TUNInterface(packetFlow: self.packetFlow)
                
                
                let fakeIPPool = try! IPPool(range: IPRange(startIP: IPAddress(fromString: "198.18.1.1")!, endIP: IPAddress(fromString: "198.18.255.255")!))
                
                
                let dnsServer = DNSServer(address: IPAddress(fromString: "198.18.0.1")!, port: NEKit.Port(port: 53), fakeIPPool: fakeIPPool)
                
                let randomNumber:Int = Int(arc4random() % 2)
//                let DNSArr = [,"223.5.5.5","223.6.6.6"] // DNSArr[randomNumber]
                let resolver = UDPDNSResolver(address: IPAddress(fromString: "223.5.5.5")!, port: NEKit.Port(port: 53))
                
                dnsServer.registerResolver(resolver)
                self.interface.register(stack: dnsServer)
                
                DNSServer.currentServer = dnsServer
                
                let udpStack = UDPDirectStack()
                self.interface.register(stack: udpStack)
                let tcpStack = TCPStack.stack
                tcpStack.proxyServer = self.proxyServer
                self.interface.register(stack:tcpStack)
                self.interface.start()
            }
            self.started = true
            
        }
        
    }
    
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        if enablePacketProcessing {
            interface.stop()
            interface = nil
            DNSServer.currentServer = nil
        }
        
        if(proxyServer != nil){
            proxyServer.stop()
            proxyServer = nil
            RawSocketFactory.TunnelProvider = nil
        }
        completionHandler()
        
        exit(EXIT_SUCCESS)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "defaultPath" {
            if self.defaultPath?.status == .satisfied && self.defaultPath != lastPath{
                if(lastPath == nil){
                    lastPath = self.defaultPath
                }else{
                    NSLog("received network change notifcation")
                    let delayTime = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                    DispatchQueue.main.asyncAfter(deadline: delayTime) {
                        self.startTunnel(options: nil){_ in}
                    }
                }
            }else{
                lastPath = defaultPath
            }
        }
        
    }
    
}

