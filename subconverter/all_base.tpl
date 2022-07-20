{% if request.target == "clash" or request.target == "clashr" %}
# port: 7890                           #本地http代理端口
# socks-port: 7891                     #本地socks5代理端口
mixed-port: {{ default(global.clash.mixed-port, "7891") }}                       #本地混合代理(http和socks5合并）端口
redir-port: 7892                       #本地Linux/macOS Redir代理端口
# tproxy-port: 7893                    #本地Linux Tproxy代理端口
# authentication:                      # 本地SOCKS5/HTTP(S)代理端口认证设置
#  - "user1:pass1"
#  - "user2:pass2"

allow-lan: true                        #允许局域网连接(false/true)
bind-address:                          #监听IP白名单（当allow-lan：true），只允许列表设备
  '*'                                  #全部设备
  # 192.168.122.11                     #单个ip4地址
  # "[aaaa::a8aa:ff:fe09:57d8]"        #单个ip6地址
mode: rule                             #clash工作模式（rule/global/direct,meta暂不支持script）
log-level: info                        #日志等级（info/warning/error/debug/silent）
ipv6: false                            #ip6开关，当为false时，停止解析hostanmes为ip6地址
external-controller: 0.0.0.0:9090      #控制器监听地址
external-ui: ui                        #http服务路径，可以放静态web网页，如yacd的控制面板
# secret: ""                           #控制器登录密码
tun:
  enable: true
{% if default(request.clashmeta, "false") == "true" %}
  device: utun
{% endif %}
  stack: system
  dns-hijack:
    - 'any:53'
  auto-route: false
  auto-detect-interface: false
interface-name: ens18                 #出口网卡名称
routing-mark: 6666                     #流量标记(仅Linux)
profile:                               #缓存设置(文件位置./cache.db)
  store-selected: true                 #节点状态记忆（若不同配置有同代理名称,设置值共享）
  store-fake-ip: true                  #fake-ip缓存

{% if default(request.clashmeta, "false") == "true" %}
geodata-mode: true                     #【Meta专属】使用geoip.dat数据库(默认：false使用mmdb数据库)
tcp-concurrent: true                   #【Meta专属】TCP连接并发，如果域名解析结果对应多个IP，
                                       # 并发所有IP，选择握手最快的IP进行连接
sniffer:                               #【Meta专属】sniffer域名嗅探器
  enable: true                         #嗅探开关
  sniffing:                            #嗅探协议对象：目前支持tls/http
    - tls
    - http
  skip-domain:                         #列表中的sni字段，保留mapping结果，不通过嗅探还原域名
                                       #优先级比force-domain高
    - 'Mijia Cloud'                    #米家设备，建议加
    - 'dlg.io.mi.com'
    - '+.apple.com'                    #苹果域名，建议加
  # - '*.baidu.com'                    #支持通配符
  force-domain:                        #需要强制嗅探的域名，默认只对IP嗅探
  # - '+'                              #去掉注释后等于全局嗅探
    - 'google.com'
{% endif %}
hosts:                                 #host，支持通配符（非通配符域名优先级高于通配符域名）
  # '*.clash.dev': 127.0.0.1           #例如foo.example.com>*.example.com>.example.com
  # '.dev': 127.0.0.1
  # 'alpha.clash.dev': '::1'
dns:
  enable: true                         #DNS开关(false/true)
  listen: 0.0.0.0:5352                 #DNS监听地址
  default-nameserver:                  #解析非IP的dns用的dns服务器,只支持纯IP
    - 114.114.114.114
    - 223.5.5.5
  # nameserver-policy:                 #指定域名使用自定义DNS解析
  # 'www.baidu.com': 'https://223.5.5.5/dns-query'
  # '+.internal.crop.com': '114.114.114.114'
  enhanced-mode: {{ default(global.clash.enhanced-mode, "fake-ip") }}                #DNS模式(redir-host/fake-ip)
                                       #【Meta专属】redir-host传递域名，可远程解析
  fake-ip-range: 198.18.0.1/16         #Fake-IP解析地址池
  use-hosts: true                      #查询hosts配置并返回真实IP
  fake-ip-filter:                      #Fake-ip过滤，列表中的域名返回真实ip
    - connect.rom.miui.com
    - localhost.ptlogin2.qq.com
    - +.msftnsci.com
    - +.msftconnecttest.com
    - +.gstatic.com
    - +.stun.*.*
    - +.stun.*.*.*
    - +.stun.*.*.*.*
    - +.time.*
    - +.time.*.*
    - +.time.*.*.*
    - +.ntp.*
    - +.ntp.*.*
    - +.ntp.*.*.*
{% if default(request.clashmeta, "false") == "true" %}
  proxy-server-nameserver:             #【Meta专属】解析代理服务器域名的dns
  # - tls://1.0.0.1:853                # 不写时用nameserver解析
    - https://dns.alidns.com/dns-query
{% endif %}
  nameserver:                          #默认DNS服务器，支持udp/tcp/dot/doh/doq
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
    # - dhcp://en0                     #dns from dhcp
  fallback:                            #回落DNS服务器，支持udp/tcp/dot/doh/doq
    - https://dns.adguard.com/dns-query
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
  fallback-filter:                     #回落DNS服务器过滤
    geoip: true                        #为真时，不匹配为geoip规则的使用fallback返回结果
    geoip-code: CN                     #geoip匹配区域设定
{% if default(request.clashmeta, "false") == "true" %}
    geosite:                           #【Meta专属】设定geosite某分类使用fallback返回结果
      - GFW
      - GREATFIRE
{% endif %}
    # ipcidr:                            #列表中的ip使用fallback返回解析结果
    #   - 240.0.0.0/4
    # domain:                            #列表中的域名使用fallback返回解析结果
    #   - '+.google.com'
    #   - '+.facebook.com'
    #   - '+.youtube.com'

{% endif %}
