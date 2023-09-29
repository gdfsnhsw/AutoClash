#!/bin/bash
getconfig(){
  #加载配置文件
  clashdir=/srv/clash
  CFG_PATH=/srv/mark
  eth_n=$(ip --oneline link show up | grep -v "lo" | awk '{print$2;exit}' | cut -d':' -f1 | cut -d'@' -f1)
  local_ip=$(ip a 2>&1 | grep -w 'inet' | grep 'global' | grep -E '\ 1(92|0|72|00|1)\.' | sed 's/.*inet.//g' | sed 's/\/[0-9][0-9].*$//g' | head -n 1);
  #检查/读取标识文件
  [ ! -f $CFG_PATH ] && echo '#标识clash运行状态的文件，不明勿动！' > $CFG_PATH
  #检查重复行并去除
  [ -n "$(awk 'a[$0]++' $CFG_PATH)" ] && awk '!a[$0]++' $CFG_PATH > $CFG_PATH
  #使用source加载配置文件
  source $CFG_PATH
  #默认设置
  [ -z "$bindir" ] && bindir=$clashdir
  [ -z "$redir_mod" ] && [ "$USER" = "root" -o "$USER" = "admin" ] && redir_mod=混合模式
  [ -z "$dns_mod" ] && dns_mod=fake-ip
  [ -z "$mix_port" ] && mix_port=7891
  [ -z "$redir_port" ] && redir_port=7892
  [ -z "$tproxy_port" ] && tproxy_port=7893
  [ -z "$db_port" ] && db_port=9090
  [ -z "$dns_port" ] && dns_port=5352
  [ -z "$sniffer" ] && sniffer=已开启
  [ -z "$clashcore" ] && clashcore=clashpre
  [ -z "$NETFILTER_MARK" ] && NETFILTER_MARK=114514
  [ -z "$IPROUTE2_TABLE_ID" ] && IPROUTE2_TABLE_ID=100
  [ -z "$ipv6_support" ] && ipv6_support=未开启
  [ -z "$ipv6_dns" ] && ipv6_dns=未开启
  [ -z "$raw_cdn" ] && raw_cdn=已开启
  [ -z "$auto_download" ] && auto_download=已开启
}

logger(){
  [ -n "$2" ] && echo -e "\033[$2m$1\033[0m"
  echo `date "+%G-%m-%d %H:%M:%S"` $1 >> $clashdir/log
  [ "$(wc -l $clashdir/log | awk '{print $1}')" -gt 30 ] && sed -i '1,5d' $clashdir/log
}

compare(){
  if [ ! -f $1 -o ! -f $2 ];then
    return 1
  elif type cmp >/dev/null 2>&1;then
    cmp -s $1 $2
  else
    [ "$(cat $1)" = "$(cat $2)" ] && return 0 || return 1
  fi
}

setconfig(){
    #参数1代表变量名，参数2代表变量值,参数3即文件路径
    [ -z "$3" ] && configpath=${CFG_PATH} || configpath=$3
    [ -n "$(grep ${1} $configpath)" ] && sed -i "s#${1}=.*#${1}=${2}#g" $configpath || echo "${1}=${2}" >> $configpath
}

webget2(){
    #参数【$1】代表下载目录，【$2】代表在线地址
    #参数【$3】代表输出显示，【$4】不启用重定向
    if curl --version > /dev/null 2>&1;then
      [ "$3" = "echooff" ] && progress='-s' || progress='-#'
      [ -z "$4" ] && redirect='-L' || redirect=''
      result=$(curl -w %{http_code} --connect-timeout 5 $progress $redirect -ko $1 $2)
    else
      if wget --version > /dev/null 2>&1;then
        [ "$3" = "echooff" ] && progress='-q' || progress='-q --show-progress'
        [ "$4" = "rediroff" ] && redirect='--max-redirect=0' || redirect=''
        certificate='--no-check-certificate'
        timeout='--timeout=3'
      fi
    [ "$3" = "echoon" ] && progress=''
    [ "$3" = "echooff" ] && progress='-q'
    wget $progress $redirect $certificate $timeout -O $1 $2 
    [ $? -eq 0 ] && result="200"
    fi
}

getyaml(){
  getconfig
  #输出
  Https="http://127.0.0.1:25500/getprofile?name=profiles/formyairport.ini&token=password"
  echo -----------------------------------------------
  echo 正在连接服务器获取配置文件…………链接地址为：
  echo -e "\033[4;32mhttp://${local_ip}:25500/getprofile?name=profiles/formyairport.ini&token=password\033[0m"
  echo 可以手动复制该链接到浏览器打开并查看数据是否正常！
  #获取在线yaml文件
  yaml=$clashdir/config.yaml
  yamlnew=/tmp/clash_config_$USER.yaml
  rm -rf $yamlnew
  echo -e "\033[4;32m正在创建配置文件\033[0m"
  webget2 $yamlnew "http://127.0.0.1:25500/getprofile?name=profiles/formyairport.ini&token=password" rediroff
  # $0 webget $yamlnew $Https
  checkyaml
}

checkyaml(){
  getconfig
  yaml=$clashdir/config.yaml
  yamlnew=/tmp/clash_config_$USER.yaml
  #检测节点或providers
  if [ -z "$(cat $yamlnew | grep -E 'server|proxy-providers' | grep -v 'nameserver' | head -n 1)" ];then
    echo -----------------------------------------------
    logger "获取到了配置文件，但似乎并不包含正确的节点信息！" 31
    echo -----------------------------------------------
    sed -n '1,30p' $yamlnew
    echo -----------------------------------------------
    echo -e "\033[33m请检查如上配置文件信息:\033[0m"
    echo -----------------------------------------------
    exit 1
  fi
  #检测旧格式
  if cat $yamlnew | grep 'Proxy Group:' >/dev/null;then
    echo -----------------------------------------------
    logger "已经停止对旧格式配置文件的支持！！！" 31
    echo -e "请使用新格式或者使用【在线生成配置文件】功能！"
    echo -----------------------------------------------
    exit 1
  fi
  #检测不支持的加密协议
  if cat $yamlnew | grep 'cipher: chacha20,' >/dev/null;then
    echo -----------------------------------------------
    logger "已停止支持chacha20加密，请更换更安全的节点加密协议！" 31
    echo -----------------------------------------------
    exit 1
  fi
  #检测vless/hysteria协议
  if [ -n "$(cat $yamlnew | grep -oE 'type: vless|type: hysteria|type: hysteria2')" ] && [ "$clashcore" != "clashmeta" ];then
    echo -----------------------------------------------
    logger "检测到vless/hysteria协议！将改为使用clash.meta核心启动！" 33
    # rm -rf $bindir/clash
    setconfig clashcore clashmeta
    # set_clashmeta_service
    echo -----------------------------------------------
  fi
  # #检测是否存在高级版规则
  if [ "$clashcore" = "clashmeta" -a -n "$(cat $yamlnew | grep -E '^script:')" ];then
    echo -----------------------------------------------
    logger "检测到高级规则！将改为使用clashpre核心启动！" 33
    # rm -rf $bindir/clash
    setconfig clashcore clashpre
    # set_clashmeta_service
    echo -----------------------------------------------
  fi
  # # #检测并去除无效节点组
  [ -n "$url_type" ] && type xargs >/dev/null 2>&1 && {
  cat $yamlnew | grep -A 8 "\- name:" | xargs | sed 's/- name: /\n/g' | sed 's/ type: .*proxies: /#/g' | sed 's/ rules:.*//g' | sed 's/- //g' | grep -E '#DIRECT $' | awk -F '#' '{print $1}' > /tmp/clash_proxies_$USER
  while read line ;do
    sed -i "/- $line/d" $yamlnew
    sed -i "/- name: $line/,/- DIRECT/d" $yamlnew
  done < /tmp/clash_proxies_$USER
  rm -rf /tmp/clash_proxies_$USER
  }
  #使用核心内置test功能检测
  if [ -x $bindir/clash ];then
    $bindir/clash -t -d $bindir -f $yamlnew >/dev/null
    if [ "$?" != "0" ];then
      logger "配置文件加载失败！请查看报错信息！" 31
      $bindir/clash -t -d $bindir -f $yamlnew
      echo "$($bindir/clash -t -d $bindir -f $yamlnew)" >> $clashdir/log
      exit 1
    fi
  fi
  #如果不同则备份并替换文件
  if [ -f $yaml ];then
    compare $yamlnew $yaml
    [ "$?" = 0 ] || mv -f $yaml $yaml.bak && mv -f $yamlnew $yaml
  else
    mv -f $yamlnew $yaml
  fi
  echo -e "\033[32m已成功获取配置文件！\033[0m"
}

modify_yaml(){
  getconfig
##########需要变更的配置###########
  [ -z "$dns_nameserver" ] && dns_nameserver='114.114.114.114, 223.5.5.5'
  [ -z "$dns_fallback" ] && dns_fallback='1.0.0.1, 8.8.4.4'
  [ -z "$skip_cert" ] && skip_cert=已开启
  #默认fake-ip过滤列表
  fake_ft_df='"anti-ad.net","*.adtidy.org", "*.github.io", "*.lan", "time.windows.com", "time.nist.gov", "time.apple.com", "time.asia.apple.com", "*.ntp.org.cn", "*.openwrt.pool.ntp.org", "time1.cloud.tencent.com", "time.ustc.edu.cn", "pool.ntp.org", "ntp.ubuntu.com", "ntp.aliyun.com", "ntp1.aliyun.com", "ntp2.aliyun.com", "ntp3.aliyun.com", "ntp4.aliyun.com", "ntp5.aliyun.com", "ntp6.aliyun.com", "ntp7.aliyun.com", "time1.aliyun.com", "time2.aliyun.com", "time3.aliyun.com", "time4.aliyun.com", "time5.aliyun.com", "time6.aliyun.com", "time7.aliyun.com", "*.time.edu.cn", "time1.apple.com", "time2.apple.com", "time3.apple.com", "time4.apple.com", "time5.apple.com", "time6.apple.com", "time7.apple.com", "time1.google.com", "time2.google.com", "time3.google.com", "time4.google.com", "music.163.com", "*.music.163.com", "*.126.net", "musicapi.taihe.com", "music.taihe.com", "songsearch.kugou.com", "trackercdn.kugou.com", "*.kuwo.cn", "api-jooxtt.sanook.com", "api.joox.com", "joox.com", "y.qq.com", "*.y.qq.com", "streamoc.music.tc.qq.com", "mobileoc.music.tc.qq.com", "isure.stream.qqmusic.qq.com", "dl.stream.qqmusic.qq.com", "aqqmusic.tc.qq.com", "amobile.music.tc.qq.com", "*.xiami.com", "*.music.migu.cn", "music.migu.cn", "*.msftconnecttest.com", "*.msftncsi.com", "localhost.ptlogin2.qq.com", "*.*.*.srv.nintendo.net", "*.*.stun.playstation.net", "xbox.*.*.microsoft.com", "*.*.xboxlive.com", "proxy.golang.org","*.sgcc.com.cn","*.alicdn.com","*.aliyuncs.com"'
  lan='allow-lan: true'
  log='log-level: info'
  [ "$ipv6_support" = "已开启" ] && ipv6='ipv6: true' || ipv6='ipv6: false'
  [ "$ipv6_dns" = "已开启" ] && dns_v6='ipv6: true' || dns_v6=$ipv6
  external="external-controller: 0.0.0.0:$db_port"
  [ -d $clashdir/ui ] && db_ui=ui
  #默认TUN配置
  if [ "$redir_mod" = "混合模式" -o "$redir_mod" = "Tun模式" ];then
    [ "$clashcore" = 'clashmeta' ] && tun_meta=', device: utun'
    tun="tun: {enable: true, stack: system$tun_meta, auto-route: false, auto-detect-interface: false}"
  else
    tun='tun: {enable: false}'
  fi
  exper='experimental: {ignore-resolve-fail: true, interface-name: '$eth_n'}'
  #dns配置
  [ -z "$(cat $clashdir/user.yaml 2>/dev/null | grep '^dns:')" ] && { 
    [ "$clashcore" = 'clashmeta' ] && dns_default_meta=', tls://1.12.12.12:853, tls://223.5.5.5:853' && dns_fallback_filter_meta=', geoip-code: CN, geosite: [gfw]'
    dns_default="114.114.114.114, 223.5.5.5$dns_default_meta"
    dns_fallback_filter="geoip: true$dns_fallback_filter_meta"
    if [ -f $clashdir/fake_ip_filter ];then
      while read line;do
        fake_ft_ad=$fake_ft_ad,\"$line\"
      done < $clashdir/fake_ip_filter
    fi
    if [ "$dns_mod" = "fake-ip" ];then

      dns='dns: {enable: true, '$dns_v6', listen: 0.0.0.0:'$dns_port', use-hosts: true, fake-ip-range: 198.18.0.1/16, enhanced-mode: fake-ip, fake-ip-filter: ['${fake_ft_df}${fake_ft_ad}'], default-nameserver: ['$dns_default'], nameserver: ['$dns_nameserver'], fallback: ['$dns_fallback'], fallback-filter: {'$dns_fallback_filter'}}'
      profile='profile: {store-fake-ip: true}'
    else
      dns='dns: {enable: true, '$dns_v6', listen: 0.0.0.0:'$dns_port', use-hosts: true, enhanced-mode: redir-host, default-nameserver: ['$dns_default'], nameserver: ['$dns_nameserver$dns_local'], fallback: ['$dns_fallback'], fallback-filter: {'$dns_fallback_filter'}}'
      profile='profile: {store-fake-ip: false}'
    fi
  }
  #域名嗅探配置
  [ "$sniffer" = "已开启" ] && [ "$clashcore" = "clashmeta" ] && sniffer_set="sniffer: {enable: true, skip-domain: [Mijia Cloud], sniff: {tls: {ports: [443, 8443]}, http: {ports: [80, 8080-8880], override-destination: true}}}"
  [ "$clashcore" = "clashpre" ] && [ "$dns_mod" = "redir_host" ] && exper="experimental: {ignore-resolve-fail: true, interface-name: '$eth_n', sniff-tls-sni: true}"
  #设置目录
  yaml=$clashdir/config.yaml
  tmpdir=/tmp/clash_$USER
  #预读取变量
  mode=$(grep "^mode" $yaml | head -1 | awk '{print $2}')
  [ -z "$mode" ] && mode='Rule'
  #预删除需要添加的项目
  a=$(grep -n "port:" $yaml | head -1 | cut -d ":" -f 1)
  b=$(grep -n "^prox" $yaml | head -1 | cut -d ":" -f 1)
  b=$((b-1))
  mkdir -p $tmpdir > /dev/null
  [ "$b" -gt 0 ] && sed "${a},${b}d" $yaml > $tmpdir/proxy.yaml || cp -f $yaml $tmpdir/proxy.yaml
  #跳过本地tls证书验证
  [ "$skip_cert" = "已开启" ] && sed -i 's/skip-cert-verify: false/skip-cert-verify: true/' $tmpdir/proxy.yaml || \
    sed -i 's/skip-cert-verify: true/skip-cert-verify: false/' $tmpdir/proxy.yaml
  ###添加CDN####autoclash####
  [ "$raw_cdn" = "已开启" ] && sed -i "s#: https://raw#: ${url_cdn}https://raw#" $tmpdir/proxy.yaml
  #添加配置
###################################
  cat > $tmpdir/set.yaml <<EOF
### 配置说明:https://wiki.metacubex.one/
mixed-port: $mix_port
redir-port: $redir_port
tproxy-port: $tproxy_port
authentication: ["$authentication"]
$lan
mode: $mode
$log
ipv6: false
$profile
external-controller: :$db_port
external-ui: $db_ui
secret: $secret
$tun
$exper
$dns
$sniffer_set
EOF
  if [ "$clashcore" = "clashmeta" ];then
    if [ ! -f "$clashdir/meta/user_meta.yaml" ]; then
    mkdir ${clashdir}/meta
  cat > $clashdir/meta/user_meta.yaml <<EOF
### Meta内核专属配置，请手动编辑$clashdir/meta/user_meta.yaml后重启
## https://wiki.metacubex.one/config/general/
find-process-mode: off
unified-delay: true
tcp-concurrent: true
geodata-mode: true 
geodata-loader: standard
geox-url:
  geoip: "https://testingcf.jsdelivr.net/gh/gdfsnhsw/meta-rules-dat@release/geoip.dat"
  geosite: "https://testingcf.jsdelivr.net/gh/gdfsnhsw/meta-rules-dat@release/geosite.dat"
  mmdb: "https://testingcf.jsdelivr.net/gh/gdfsnhsw/meta-rules-dat@release/country.mmdb"
### meta添加shadowsocks入站
listeners:
  - name: daed
    type: shadowsocks
    port: 52023
    password: autoclash2023
    cipher: none
###  
EOF
    fi
  fi
###################################
  #读取本机hosts并生成配置文件
  if [ "$hosts_opt" != "未启用" ] && [ -z "$(grep -E '^hosts:' $clashdir/user.yaml 2>/dev/null)" ];then
    #NTP劫持
    cat >> $tmpdir/hosts.yaml <<EOF
hosts:
   'time.android.com': 203.107.6.88
   'time.facebook.com': 203.107.6.88  
EOF
    #加载本机hosts
    sys_hosts=/etc/hosts
    [ -f /data/etc/custom_hosts ] && sys_hosts=/data/etc/custom_hosts
    while read line;do
      [ -n "$(echo "$line" | grep -oE "([0-9]{1,3}[\.]){3}" )" ] && \
      [ -z "$(echo "$line" | grep -oE '^#')" ] && \
      hosts_ip=$(echo $line | awk '{print $1}')  && \
      hosts_domain=$(echo $line | awk '{print $2}') && \
      [ -z "$(cat $tmpdir/hosts.yaml | grep -oE "$hosts_domain")" ] && \
      echo "   '$hosts_domain': $hosts_ip" >> $tmpdir/hosts.yaml
    done < $sys_hosts
  fi
  #合并文件
  [ -f $clashdir/user.yaml ] && yaml_user=$clashdir/user.yaml
  [ -f $tmpdir/hosts.yaml ] && yaml_hosts=$tmpdir/hosts.yaml
  [ -f $tmpdir/proxy.yaml ] && yaml_proxy=$tmpdir/proxy.yaml
  [ -f $clashdir/meta/user_meta.yaml ] && yaml_user_meta=$clashdir/meta/user_meta.yaml
  cut -c 1- $tmpdir/set.yaml $yaml_user_meta $yaml_hosts $yaml_user $yaml_proxy > $tmpdir/config.yaml
  # #插入自定义规则
  sed -i "/#自定义规则/d" $tmpdir/config.yaml
  space_rules=$(sed -n '/^rules/{n;p}' $tmpdir/proxy.yaml | grep -oE '^ *') #获取空格数
  #tun/fake-ip防止流量回环
  if [ "$mode" = "Rule" ] && [ "$redir_mod" = "混合模式" -o "$redir_mod" = "Tun模式" -o "$dns_mod" = "fake-ip" ];then
    sed -i "/^rules:/a\\$space_rules- SRC-IP-CIDR,198.18.0.0/16,REJECT #自定义规则(防止回环)" $tmpdir/config.yaml
  fi
  #如果没有使用小闪存模式
  if [ "$tmpdir" != "$bindir" ];then
    cmp -s $tmpdir/config.yaml $yaml >/dev/null 2>&1
    [ "$?" != 0 ] && mv -f $tmpdir/config.yaml $yaml || rm -f $tmpdir/config.yaml
  fi
  rm -f $tmpdir/set.yaml
  rm -f $tmpdir/proxy.yaml
  rm -f $tmpdir/hosts.yaml
  # rm -f $tmpdir/user_meta.yaml
}

afstart(){
  #读取配置文件
  getconfig
  $bindir/clash -t -d $clashdir >/dev/null
  if [ "$?" = 0 ];then
    PID=$(pidof daed)
    if [ -z "$PID" ];then
      #设置路由规则
      [ "$redir_mod" = "Redir模式" ] && redir_setup
      [ "$redir_mod" = "Tun模式" ] && tun_setup
      [ "$redir_mod" = "混合模式" ] && redir_tun_setup
      [ "$redir_mod" = "TProxy模式" ] && tproxy_setup
    fi
  else
    logger "clash服务启动失败！请查看报错信息！" 31
    $bindir/clash -t -d $clashdir
    echo "$($bindir/clash -t -d $clashdir)" >> $clashdir/log
    $0 stop
    exit 1
  fi
}

tproxy_setup(){
    getconfig
    ip route replace local default dev lo table "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    nft flush ruleset
    nft -f - << EOF
    include "/lib/clash/private.nft"
    include "/lib/clash/chnroute.nft"
    table clash {
        chain debug {
            type filter hook prerouting priority 0;
            ip protocol != { tcp, udp } accept
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto {tcp, udp} mark set $NETFILTER_MARK tproxy to :$tproxy_port
        }
    }
EOF
    exit 0
}

redir_setup(){
    getconfig
    ip route replace local default dev lo table "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    nft flush ruleset
    nft -f - << EOF
    include "/lib/clash/private.nft"
    include "/lib/clash/chnroute.nft"
    table clash {
        chain prerouting {
            type nat hook prerouting priority -100;
            ip daddr \$private_list return
            ip daddr \$chnroute_list return
            meta l4proto tcp mark set $NETFILTER_MARK redirect to $redir_port
        }
    }
EOF
    exit 0
}

tun_setup(){
    getconfig
    ip route replace default dev utun table "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    nft flush ruleset
    nft -f - << EOF
    include "/lib/clash/private.nft"
    include "/lib/clash/chnroute.nft"
    table clash {
        chain debug {
            type filter hook prerouting priority 0; policy accept;
            ip protocol != { tcp, udp } accept
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto {tcp, udp} mark set $NETFILTER_MARK
        }
        chain prerouting {
            type nat hook prerouting priority 0; policy accept;
            ip protocol != { tcp, udp } accept
        }        
    }
EOF
    exit 0
}

redir_tun_setup(){
    getconfig
    ip route replace default dev utun table "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    nft flush ruleset
    nft -f - << EOF
    include "/lib/clash/private.nft"
    include "/lib/clash/chnroute.nft"
    table clash {
        chain prerouting {
            type nat hook prerouting priority -100; policy accept;
            ip protocol != { tcp, udp } accept
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto tcp redirect to $redir_port
        }
        chain debug {
            type filter hook prerouting priority -150; policy accept;
            ip protocol != { tcp, udp } accept
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto udp mark set $NETFILTER_MARK
        }
        
    }
EOF

    exit 0
}

stop_firewall(){
    getconfig
    #清理路由规则
    ip route del default dev utun table "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    ip route del local default dev lo table "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    #重置nftables相关规则
    type nft >/dev/null 2>&1 && {
      nft flush table clash >/dev/null 2>&1
      nft delete table clash >/dev/null 2>&1
    }
}

case $1 in
"redir_setup") 
                  redir_setup 0
                  ;;
"tun_setup") 
                  tun_setup 0
                  ;;
"redir_tun_setup") 
                  redir_tun_setup 0
                  ;;
"tproxy_setup") 
                  tproxy_setup 0
                  ;;
"clean") 
                  clean 0
                  ;;
"getconfig") 
                  getconfig 0
                  ;;
"afstart") 
                  afstart 0
                  ;;
"start") 
                  getconfig
                  [ "$disoverride" != "已禁用" ] && modify_yaml 0
                  ;;
"getyaml") 
                  getyaml 0
                  ;;
"checkyaml") 
                  checkyaml 0
                  ;;                  
"mix_yaml") 
                  checkyaml 0
                  modify_yaml 0
                  ;;  
"updateyaml") 
                  getconfig 0
                  getyaml 0
                  modify_yaml 0
                  ;;
"stop_firewall") 
                  stop_firewall 0
                  ;;
esac
