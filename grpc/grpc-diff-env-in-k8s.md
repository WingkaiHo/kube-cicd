## API 网关怎么区分APP测试和生产环境

API网关是通过prefix区分grpc不同服务请求，然后把请求转发到对应的服务实例上。GRPC客户端请求`perfix`其实来源于`.proto`文件里面package名称和service名称定义， 'packagename.servicename'

同一服务部署了测试和生产环境，如果同一套API网关怎么区分。通过修改`.proto`文件packename来实现，可以在packeagename加入不同测试环境前缀实现。


### 代码可以根据环境自动生成对应proto文件

如果有多个`.proto`文件可能由于不一致产成问题。目前工程一般都只有`development`和`production`两个环境，可以rpc框架启动判断`NODE_ENV`,如果值不为`production`,生成一个test版本`.proto`, 代码如下:

```js
const PROTO_PATH = Path.join(__dirname, '../interface.proto')
const PROTO_PATH_TEST = Path.join(__dirname, '../testinterface.proto')

...

loadPackageDefine () {
  const isProduction = process.env.NODE_ENV === 'production'
  if (isProduction) {
    const PackageDefinition = protoLoader.loadSync(
      PROTO_PATH, {
        keepCase: true,
        longs: String,
        enums: String,
        defaults: true,
        oneofs: true
      })
    this.MongodbOperatorGrpc = grpc.loadPackageDefinition(PackageDefinition).db
  } else {
    // copy package form source
    execSync(`cp ${PROTO_PATH} ${PROTO_PATH_TEST}`)
    // fix package name (use different prefix)
    execSync(`sed -i "s/package db/package test.db/" ${PROTO_PATH_TEST}`)
    const testPackageDefinition = protoLoader.loadSync(
      PROTO_PATH_TEST, {
        keepCase: true,
        longs: String,
        enums: String,
        defaults: true,
        oneofs: true
      })
    this.MongodbOperatorGrpc = grpc.loadPackageDefinition(testPackageDefinition).testdb
  }
```

以`db-service-rpc`通过上面代码处理后:

- deployment环境客户/服务器处理前缀为: /test.db.MongodbOperatorGrpc/
- production环境客户/服务器处理前缀为: /db.MongodbOperatorGrpc/

在k8s部署db-service配置service的yaml里面两个环境也要有相应变化:

development环境
```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-service-grpc-test
  labels:
    app.kubernetes.io/name: db-service
    app.kubernetes.io/module: db-service-grpc
  annotations:
    getambassador.io/config: |
      ---
      apiVersion: ambassador/v0
      kind: Mapping
      name: db-service-grpc-test
      grpc: true
      prefix: /testdb.MongodbOperator/
      rewrite: /testdb.MongodbOperator/
      service: db-service-grpc-test.node.svc.cluster.local:27200

spec:
  clusterIP: None
  type: ClusterIP
  ports:
    - port: 27200
      targetPort: 27200
      protocol: TCP
      name: grpc
  selector:
    app.kubernetes.io/name: db-service
    app.kubernetes.io/module: db-service-grpc
    app: test-node-db-service
    rollout: "false"
```

production:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-service-grpc-production
  labels:
    app.kubernetes.io/name: db-service
    app.kubernetes.io/module: db-service-grpc
  annotations:
    getambassador.io/config: |
      ---
      apiVersion: ambassador/v0
      kind: Mapping
      name: db-service-grpc-production
      grpc: true
      prefix: /db.MongodbOperator/
      rewrite: /db.MongodbOperator/
      service: db-service-grpc-production.node.svc.cluster.local:27200
spec
  clusterIP: None
  type: ClusterIP
  ports:
    - port: 27200
      targetPort: 27200
      protocol: TCP
      name: grpc
  selector:
    app.kubernetes.io/name: db-service
    app.kubernetes.io/module: db-service-grpc
    app: production-node-d-p5l23n
    rollout: "false"
```
