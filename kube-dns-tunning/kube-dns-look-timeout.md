## contrack竞争机制导致dns超时

### 存在问题

我们部署`POD`经常通过内存域名访问其他服务，同时机器部署这些实例比较多，导致内部域名解析失败，无法连接其他服务。

影响比较大：
GRPC API 网关这些实例经常刷新对于GRPC服务实例，高并发发起dns解析，经常解析失败，导致GRPC异常。

### 具体现象

在问题机器POD里面测试出现下面现象：

- ping 一个域名的时候出现很久没有返回，解析失败
- ping 一个域名IP解析出来了，卡住。原因dns反响时候失败，重试
- nslookup测试/tcpdump 发现远程dns服务已经返回结果, 但是IP不是dns server ip(10.233.0.3), 而是对于dns实例`POD`IP。导致系统任，解析失败
- 执行`watch conntrack -S`命令发现`insert_failed`计数不断上升

### 背景

在生产环境`kubenetes`使用coredns做为集群kube-dns， 所以POD都是通过`Service`地址也就是cluster地址访问kube-dns服务，我们使用kube-proxy ipvs模式，所以访问dns service 地址(10.233.0.3)都需要通过ipvs模块进行DNAT转换,把service地址替换为dns实例`Pod`地址，回来的时候需要把dns实例`POD`地址转化为`service`地址。

#### Linux内核中的DNAT

DNAT的主要职责是修改发送出去数据包的目的地，远程回复数据包的来源，同时确保对所有后续数据包应用相同的修改。

后者严重依赖于连接跟踪机制，也称为conntrack内核模块。顾名思义，conntrack跟踪系统中正在进行的网络连接。

以简化的方式，每个连接conntrack用两个元组表示： 一个用于原始请求（IP_CT_DIR_ORIGINAL），一个用于回复（IP_CT_DIR_REPLY）。在UDP的情况下，每个元组由源IP地址，源端口以及目标IP地址和目标端口组成。回复元组包含存储在src字段中的目标的真实地址。

例如，如果具有IP地址10.234.0.17的Pod向ClusterIP(10.233.0.3)发送请求，ipvs并将kube-dns地址其转换为10.234.2.202，则将创建以下元组：

src： src=10.234.0.17 dst=10.233.0.3 sport=53378 dport=53
reply: src=10.234.2.202 dst=10.234.0.17 sport=53 dport=53378

通过具有这些item，内核可以相应地修改任何相关分组的目的地和源地址，而无需再次遍历DNAT规则。此外，它将知道如何修改回复以及应该向谁发送回复。

当conntrack被创建的item. 如果没有确认的conntrack条目具有相同的src元组或reply元组，内核将尝试确认该条目。

conntrack创建和DNAT的简化流程如下所示：

```
+---------------------------+      Create a conntrack for a given packet if
|                           |      it does not exist; IP_CT_DIR_REPLY is
|    1. nf_conntrack_in     |      an invert of IP_CT_DIR_ORIGINAL tuple, so
|                           |      src of the reply tuple is not changed yet.
+------------+--------------+
             |
             v
+---------------------------+
|                           |
|     2. ipt_do_table       |      Find a matching DNAT rule.
|                           |
+------------+--------------+
             |
             v
+---------------------------+
|                           |      Update the reply tuples src part according
|    3. get_unique_tuple    |      to the DNAT rule in a way that it is not used
|                           |      by any already confirmed conntrack.
+------------+--------------+
             |
             v
+---------------------------+
|                           |      Mangle the packet destination port and address
|     4. nf_nat_packet      |      according to the reply tuple.
|                           |
+------------+--------------+
             |
             v
+----------------------------+
|                            |     Confirm the conntrack if there is no confirmed
|  5. __nf_conntrack_confirm |     conntrack with either the same original or
|                            |     a reply tuple; increment insert_failed counter
+----------------------------+     and drop the packet if it exists.
```

#### 问题所在

当两个UDP数据包同时从不同的线程通过同一个套接字发送时，会出现问题。

UDP是一种无连接协议，因此不会因为connect（2）系统调用（与TCP相反）而发送数据包，因此conntrack在调用之后没有创建任何条目。

仅在发送数据包时才创建该条目。这导致以下可能的竞争：

无论是包找到证实conntrack的`1. nf_conntrack_in step`。对于两个数据包conntrack，都会创建具有相同元组的两个条目。
与上述情况相同，但conntrack在另一个呼叫之前确认其中一个数据包的条目3. get_unique_tuple。另一个数据包通常在源端口发生变化时获得不同的reply元组。
与第一种情况相同，但在步骤中选择了具有不同端点的两个不同规则2. ipt_do_table。
竞争的结果是相同的其中一个数据包在步骤中被丢弃5. __nf_conntrack_confirm。

这正是DNS案例中发生的情况。GNU C Library和musl libc并行执行A和AAAA DNS查找。由于竞争，其中一个UDP数据包可能被内核丢弃，因此客户端将在超时（通常是5秒）后尝试重新发送它。

值得一提的是，这个问题不仅仅针对Kubernetes， 任何并行发送UDP数据包的Linux多线程进程都容易出现这种竞争情况。

此外，即使您没有任何DNAT规则，竞争可能存在


#### 解决方法

步骤如下：

- 每个节点部署一个本地dns cache实例，`POD`使用本节点ip地址dns, 不使用`service`地址. 使用发真实ip减少DNAT影响.
- 修改/etc/resolv配置。开启single-request-reopen解决IPV4 DNS 和 IPV6 DNS请求使用了相同的网络五元组。一旦出现同一 socket 发送的两次请求处理，解析端发送第一次请求后会关闭 socket，并在发送第二次请求前打开新的 socket. 参考: https://bbs.aliyun.com/simple/t540447.html 此参数对于一些Alpine Linux无效，因为他们使用musl libc

```
nameserver 本节点dns [支持kube域名]
nameserver 备用dns [支持Kube域名]

options timeout:2 attempts:3 single-request-reopen
```
- k8s yaml 里面是设置POD.spec.dnsPolicy为`Default`, 意思是POD里面的/etc/resolv.conf 使用节点上的文件/etc/resolv.conf. 参考：https://tencentcloudcontainerteam.github.io/2018/10/26/DNS-5-seconds-delay/


其他方法:

The outcome is the following kernel patches:
- "netfilter: nf_conntrack: resolve clash for matching conntracks" fixes the 1st race (accepted).
- "netfilter: nf_nat: return the same reply tuple for matching CTs" fixes the 2nd race (waiting for a review).


#### kube-node-dns部署

```
$kubectl apply -f kube-node-dns/yaml/ -n kube-system
```
