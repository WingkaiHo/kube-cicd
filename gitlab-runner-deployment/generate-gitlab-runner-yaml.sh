#! /bin/bash

function usage() {
	echo "usage: generate-gitlab-runner-yaml.sh <gitlab-runner-namespaec> <gitlab-project-toker> <gitlab-url>"
	echo "example: generate-gitlab-runner-yaml.sh runner Uaaaa-Ho9xxxxx your.gitlab.url"
}

# main funciton
GITLAB_BUILD_NAMESPACE=$1
GITLAB_CI_TOKEN=$2
GITLAB_URL=$3

if [[ -z ${GITLAB_BUILD_NAMESPACE} ]]; then
	echo "请输入对应的namepace"
	usage
	exit 1
fi

if [[ -z ${GITLAB_CI_TOKEN} ]]; then
	echo "请输入token, Uaaaa-Ho9xxxxx"
	usage
	exit 1
fi


if [[ -z ${GITLAB_URL} ]]; then
	echo "请输入url, your.gitlab.url"
	usage
	exit 1
fi

# bas464 encode token
echo "base64 encode token..."
GITLAB_CI_TOKEN_BASE64=$(echo $GITLAB_CI_TOKEN | base64 -w0)

echo $GITLAB_CI_TOKEN_BASE64

echo "copy template to $GITLAB_BUILD_NAMESPACE"
cp -rf yaml-tmpl $GITLAB_BUILD_NAMESPACE

echo "replace VALs."
sed -i "s/__YOUR_GITLAB_BUILD_NAMESPACE__/${GITLAB_BUILD_NAMESPACE}/g" $GITLAB_BUILD_NAMESPACE/*.yaml
sed -i "s/__YOUR_BASE64_ENCODED_TOKEN__/${GITLAB_CI_TOKEN_BASE64}/g" $GITLAB_BUILD_NAMESPACE/*.yaml
sed -i "s/__YOUR_GITLAB_CI_SERVER_URL__/${GITLAB_URL}/g" $GITLAB_BUILD_NAMESPACE/*.yaml
