### 创建rbd存储块

创建mysq-rbd存储块就是需要创建PVC, 通过statefulset template

创建 mysql-pvc.yml
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  annotations:
     volume.beta.kubernetes.io/storage-class: "ceph-rbd"
  labels:
    docs-app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

执行命令
```
$kubectl apply -f mysql-pvc.yml -n heyongjia
```

等一段时间后, rbd-provider创建对应pv, 可以通过下面命令获取

```
$kubectl get pv 
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                                          STORAGECLASS   REASON    AGE
pvc-17a8378f-921a-11e8-b9f8-0894ef5a554a   10Gi       RWO            Delete           Bound      heyongjia/mysql-pvc                            ceph-rbd 

$kubectl get pv pvc-17a8378f-921a-11e8-b9f8-0894ef5a554a -o yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    kubernetes.io/createdby: rbd-dynamic-provisioner
    pv.kubernetes.io/bound-by-controller: "yes"
    pv.kubernetes.io/provisioned-by: kubernetes.io/rbd
  creationTimestamp: 2018-07-28T03:55:40Z
  name: pvc-17a8378f-921a-11e8-b9f8-0894ef5a554a
  resourceVersion: "5303489"
  selfLink: /api/v1/persistentvolumes/pvc-17a8378f-921a-11e8-b9f8-0894ef5a554a
  uid: 17d1173e-921a-11e8-85cf-7cd30a558550
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 10Gi
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: mysql-pvc
    namespace: heyongjia
    resourceVersion: "5303486"
    uid: 17a8378f-921a-11e8-b9f8-0894ef5a554a
  persistentVolumeReclaimPolicy: Delete
  rbd:
    fsType: xfs
    image: kubernetes-dynamic-pvc-17ab264e-921a-11e8-8d88-7cd30a558550
    keyring: /etc/ceph/keyring
    monitors:
    - 172.25.52.205
    pool: rbd
    secretRef:
      name: ceph-secret
      namespace: kube-system
    user: admin
  storageClassName: ceph-rbd
  volumeMode: Filesystem
status:
  phase: Bound
```

创建对应mysql deployment

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    dcos-service: wordpress-mysql
    dcos-app: wordpress
spec:
  replicas: 1 # tells deployment to run 2 pods matching the template
  revisionHistoryLimit: 10
  minReadySeconds: 300
  strategy:
    type: Recreate
  template: # create pods using pod definition in this template
    metadata:
      labels:
        dcos-service: wordpress-mysql
        dcos-app: wordpress
    spec:
      nodeSelector:
          kubernetes.io/hostname: k8s-node-216
      containers:
      - name: wordpress-mysql
        image: private-registry.k8s.tuputech.com/system/mysql:5.7
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: wordpress
        ports:
        - containerPort: 3306
        volumeMounts:
        - mountPath: /var/lib/mysql
          name: mysql-persistent-storage
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pvc  #和pvc对应上
```
