## 故障发生

gpu机器太繁忙导致系统卡死， pod被reschedule到其他的node节点后一直处于ContainerCreating的状态，kubectl describe pod看到报错Multi-Attach error for volume "pvc-76b54b6c-df46-11e7-a2f0-005056b12f99" Volume is already exclusively attached to one node and can't be attached to another。

原因是rbd image仍然有watcher存在，导致其他node不能正常mount(map) image

### 处理步骤

#### 查看pv对应哪个rbd image

```
kubectl get pv pvc-1bf69589-ec9d-11e8-ae69-44a84246e955  -o go-template='{{.spec.rbd.image}}'
```

#### 查看rbd image的watcher
```
$ sudo rbd status kubernetes-dynamic-pvc-1bf69589-ec9d-11e8-ae69-44a84246e955 -p kube
Watchers:
        watcher=172.26.10.105:0/1787993098 client.205213 cookie=55
```
可以看到节点172.20.10.105仍map着这个image

登陆节点查看rbd images mapped关系
```
$ sudo rbd showmapped | grep kubernetes-dynamic-pvc-1bf69589-ec9d-11e8-ae69-44a84246e955
8  kube kubernetes-dynamic-pvc-1bf69589-ec9d-11e8-ae69-44a84246e955 -    /dev/rbd8
```
可看到image被挂载在/dev/rbd8

unmap image

sudo rbd unmap /dev/rbd8
再次查看watcher已经没有了，等待一会可以看到pod开始挂载image，正常来说是没问题到了，但是通过describe看到报错

  Warning  FailedMount            16s (x2 over 24s)  kubelet, node08          MountVolume.MountDevice failed for volume "pvc-76b54b6c-df46-11e7-a2f0-005056b12f99" : rbd: failed to mount device /dev/rbd8 at /var/lib/kubelet/plugins/kubernetes.io/rbd/rbd/kube-image-kubernetes-dynamic-pvc-1bf69589-ec9d-11e8-ae69-44a84246e955 (fstype: ), error 'fsck' found errors on device /dev/rbd8 but could not correct them: fsck from util-linux 2.27.1
/dev/rbd8 contains a file system with errors, check forced.
/dev/rbd8: Unattached inode 303


/dev/rbd8: UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY.
  (i.e., without -a or -p options)
提示卷发生文件系统错误，那么我们需要登陆到node08上运行fsck，保险起见可先尝试对rbd做snapshot镜像，参考

执行修复
```
sudo fsck -fv /dev/rbd8 
fsck from util-linux 2.27.1
e2fsck 1.42.13 (17-May-2015)
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Unattached inode 303
Connect to /lost+found<y>? yes
Inode 303 ref count is 2, should be 1.  Fix<y>? yes
Pass 5: Checking group summary information
Block bitmap differences:  -(71680--73727) -(94208--95231)
Fix<y>? yes

/dev/rbd8: ***** FILE SYSTEM WAS MODIFIED *****

         326 inodes used (0.50%, out of 65536)
          35 non-contiguous files (10.7%)
           0 non-contiguous directories (0.0%)
             # of inodes with ind/dind/tind blocks: 0/0/0
             Extent depth histogram: 311/7
       63642 blocks used (24.28%, out of 262144)
           0 bad blocks
           1 large file

         308 regular files
           9 directories
           0 character device files
           0 block device files
           0 fifos
           1 link
           0 symbolic links (0 fast symbolic links)
           0 sockets
------------
         317 files
```
修复完成，等待一会之后可观察到pod已能正常挂载上image并启动。
