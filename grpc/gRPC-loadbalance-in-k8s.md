## gRPC 客户端和API网关之间网络高可用负载均衡

API网关给简化了gRPC客户端和服务端之间实现服务发现的逻辑，提供一个中心化的服务，gRPC客户端和API Gateway之间网络高可用，负载均衡有更高的要求。

目标

- 客户端和API Gateway网络高可用
- 多个API Gateway实例可以负载均衡

### 通过k8s的ClusterIP访问API网关(ambassador)

这个访问方式具体流程如下：

- gRPC client 通过k8s dns 解析域名`ambassador.basic.svc.cluster.local`获取ClusterIP地址
- gRPC client 通过ClusterIP(lvs)地址，通过lvs转发连接一个API Gateway pod上
- 由于gRPC长连接，ClusterIP(lvs)起不了负载均衡的作用


能否对服务地址建立多个连接`ambassador.basic.svc.cluster.local:80`，多次执行下面代码，保存连接
```js
createGrpcConnection (server) {
    const connection = new this.MongodbOperatorGrpc.MongodbOperator(server,
      grpc.credentials.createInsecure()）
    Promise.promisifyAll(connection)
    return connection
  }
```

答案是不可以，测试发现由于gRPC库有信导的抽象，同一服务，同一地址只能创建唯一一个信道。

结论:

- 只能和APIGateway Pod建立一个连接
- 连接出错以后只能通过cluster重新连接
- 不能实现多个API Gateway负载均衡

这个方法无法实现高可用和负载均衡需求。

### 通过k8s的headless 服务访问

这个方法配置headless服务，这个服务没有Cluster, 通过dns返回的都是POD IP地址， 当然服务实例变化的时候， 这个DNS解析更新有K8s维护。

k8s服务配置如下:
```
apiVersion: v1
kind: Service
metadata:
  labels:
    service: ambassador
  name: ambassador-headless
  namespace: basic
spec:
  # 配置无cluster ip状态
  clusterIP: None
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    service: ambassador
  type: ClusterIP
```

grpc也需要相应配置
```
const grpcOption = {
  'grpc.min_reconnect_backoff_ms': 1000,
  'grpc.max_reconnect_backoff_ms': 10000,
  'grpc.enable_retries': 1,
  'grpc.grpclb_call_timeout_ms': 5000,
  // 启用grpc dns负载均衡配置
  'grpc.lb_policy_name': 'round_robin',
  'grpc.keepalive_timeout_ms': (120 * 1000),
  'grpc.keepalive_time_ms': (60 * 1000),
  // grpc库option只接收数值和string类型
  'grpc.service_config': '"retryPolicy": {' +
    // 启动底层重试机制，当一个信道有问题可以切换另外一个信道，不用向上层报错
    '"maxAttempts": 2, ' +
    '"initialBackoff": "0.1s", ' +
    '"maxBackoff": "1s", ' +
    '"backoffMultiplier": 2, ' +
    '"retryableStatusCodes": ["UNAVAILABLE"] ' +
   '}'
```

创建grpc连接

```
createGrpcConnection (server) {
    const connection = new this.MongodbOperatorGrpc.MongodbOperator(server,
      grpc.credentials.createInsecure(), grpcOption）
    Promise.promisifyAll(connection)
    return connection
  }

...
```

这样只要和headless`ambassador-headless.basic.svc.cluster.local:80`创建一次连接，底层grpc库自动根据dns返回地址创建多个信道，按照`round_robin`方式进行负载均衡。



结论:

- 可以和所有的API Gateway pod建立连接
- 通过库提供重试机制提供高可用
- 通过grpc库实现和API Gateway负载均衡

所以可以选择headless方式和API Gateway进行连接。


### 疑问

#### 为什么不直接使用grpc库提供负载均衡功能

gRPC库服务实例发现功能比较弱，如果只有在连接出现问题以后，才会重新去dns解析，如果服务端实例比较忙，增加实例以后，grpc库不会主动添加新实例信道连接。 Ambassador envoy API 网关可以在服务添加实例以后，快速感知道，把请求发送新的实例上。