构建镜像的时候node-pre-gyp挂死不退出
============

最近使用引入grpc库以后，构建镜像经常出现失败， docker build不退出情况。导致后面排队构建等待， 发现都挂在node-pre-gyp，npm/yarn过程不退出

## 原因

根源：
1. CS机房访问外部网络的时候出现丢包/不稳定以及NAT问题，导致TCP C/S两边同步序列对不上（其它地方讨论）。
2. grpc需要去默认外国网站下载二进制编译包，这个增加失败机会。

分析：
npm/yarn 目前通过nexus进行node依赖包缓存，都是通过内网仓库缓存减少对外网依赖。但是node需要编译/需要二进制预编译库库应用还是需要访问外网。

### 解决方法

目前国内`npm.taobao.org/mirrors`缓存所有npm相关二进制包依赖， 可以通过k8s上部署一个'npm-taobao-org-cache'服务，通过这个缓存地址转发这个站点，并且缓存，再次构建的时候可以使用这个服务上缓存。


### 使用方法

下面是常用二进包下在地址配置方法

#### GRPC库

```
// 使用公司内网nexus仓库
$npm set registry http://nexus.tupu.local/repository/npm-proxy/
// 制定grpc二进制库走内网npm-taobao-org-cache
$npm --grpc_node_binary_host_mirror=http://npm-taobao-org-cache.you-private-repo.local/dist/ i -verbose
```

#### disturl

例如像截图服务需要进行ffmpg库需要编译，需要在`npm.org`站点下载`node-${node-version}-headers.tar.gz`, 在`node-pre-gyp`也经常失败

```
// 使用公司内网nexus仓库
$npm set registry http://nexus.you-private-repo.local/repository/npm-proxy/ 
// distrul走内网npm-taobao-org-cache
$npm set disturl http://npm-taobao-org-cache.repo.local/dist/
$npm i -verbose
```

#### 其它相关库可以选择添加

参考： https://npm.taobao.org/mirrors/


### 缓存库实现

通过nginx缓存实现， 配置比较长缓存超时时，通过url进行换存，配置如下:
```
user  nginx;
worker_processes  2;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
	multi_accept on;
	use epoll;
	worker_connections  1024;
}



http {
	include       /etc/nginx/mime.types;
	default_type  application/octet-stream;

	log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
		'$status $body_bytes_sent "$http_referer" '
		'"$http_user_agent" "$http_x_forwarded_for"';

	access_log  /var/log/nginx/access.log  main;

	sendfile        on;
	keepalive_timeout  65;
	proxy_cache_path /var/nginx/cache levels=1 keys_zone=STATIC:50m inactive=100d max_size=12g use_temp_path=off; 

	server {
		resolver 114.114.114.114 223.5.5.5 223.6.6.6 valid=30s;
		listen 80;
		location / {
			proxy_pass      https://cdn.npm.taobao.org;
			client_max_body_size    100m; 
			client_body_buffer_size 1m; 
			proxy_connect_timeout   900; 
			proxy_send_timeout      900; 
			proxy_read_timeout      900; 
			proxy_buffers           32 4k; 
			proxy_cache            STATIC; 
            # 加大缓存有效时间
			proxy_cache_valid      365d;
            # 同时有多个客户端下载，只有首次下载，其它客户端等待缓存
			proxy_cache_lock on;
            # 客户端缓存
			proxy_cache_key $uri; 
			proxy_ignore_headers X-Accel-Expires Expires Cache-Control;
		}
	}

}
```
