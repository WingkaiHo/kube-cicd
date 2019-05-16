#!/bin/bash
nginx_conf=`base64 ./nginx.conf | tr -d '\n'`


cat << EOF > ./k8s_yaml/npm-taobao-org-cache.yaml
apiVersion: v1
kind: Secret
metadata:
  name: npm-taobao-org-cache 
data:
  nginx.conf: "${nginx_conf}"
EOF
