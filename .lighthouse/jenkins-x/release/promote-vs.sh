#!/bin/bash

set -x
set -e

echo "promoting changes in jx3-gitops-template to downstream templates"

declare -a repos=(
  # vanilla
  "jx3-kubernetes" "jx3-kubernetes-bbc" "jx3-kubernetes-istio" "jx3-kubernetes-minio" "jx3-kubernetes-vault" "jx3-kind" "jx3-kind-gitea" "jx3-minikube" "jx3-docker-vault" "jx3-k3s-vault"
  # GKE
  "jx3-gke-vault" "jx3-gke-gsm" "jx3-gke-gsm-gitea"
  # EKS
  "jx3-eks-asm" "jx3-eks-vault"
  # Azure
  "jx3-azure-vault" "jx3-azure-akv"
  # OpenShift
  "jx3-openshift" "jx3-openshift-crc"
  # other clouds
  "jx3-iks" "jx3-alicloud"
)

declare -a tfrepos=(
  "jx3-terraform-gke"
  "jx3-terraform-eks"
  "jx3-terraform-azure"
)

git config --global --add user.name ${GIT_AUTHOR_NAME:-jenkins-x-bot}
git config --global --add user.email ${GIT_AUTHOR_EMAIL:-jenkins-x@googlegroups.com}

export SOURCE_DIR=$PWD
export TMPDIR=/tmp/jx3-gitops-promote
rm -rf $TMPDIR
mkdir -p $TMPDIR

function upgradeClusterRepo {
  echo "upgrading repository https://github.com/jx3-gitops-repositories/$1"
  cd $TMPDIR
  git clone https://github.com/jx3-gitops-repositories/$1.git
  cd "$1"
  echo "recreating a clean version stream"
  git rm -r --ignore-unmatch versionStream .lighthouse/jenkins-x .lighthouse/Kptfile
  git commit -m "chore: remove old versionstream"
  # jx gitops kpt update fails if there are uncommitted changes
  jx gitops kpt update
  mkdir -p .lighthouse
  kpt pkg get https://github.com/jenkins-x/jx3-pipeline-catalog.git/$2/.lighthouse/jenkins-x .lighthouse/jenkins-x
  kpt pkg get https://github.com/jenkins-x/jx3-versions.git/ versionStream
  rm -rf versionStream/jenkins*.yml versionStream/jx versionStream/.github versionStream/.pre* versionStream/.secrets* versionStream/OWNER* versionStream/.lighthouse versionStream/.github
  jx gitops helmfile resolve --update
  jx gitops helmfile report
  git add * .lighthouse && git commit -a --amend -m "chore: upgrade version stream" && git push || true
}

for r in "${repos[@]}"
do
  upgradeClusterRepo $r environment
done

upgradeClusterRepo jx3-kubernetes-production environment-remote

for r in "${tfrepos[@]}"
do
  echo "upgrading repository https://github.com/jx3-gitops-repositories/$r"
  cd $TMPDIR
  git clone https://github.com/jx3-gitops-repositories/$r.git
  cd "$r"
  jx gitops upgrade --version-stream-dir $SOURCE_DIR || true
  git commit -a -m "chore: upgrade version stream" || true
  git push || true
done

# lets upgarde our own infra automatically
LOCAL_BRANCH_NAME="jx-vs_$VERSION"
cd $TMPDIR
git clone https://github.com/jenkins-x/jx3-oss-cluster.git
cd "jx3-oss-cluster"
git checkout -b $LOCAL_BRANCH_NAME
jx gitops upgrade --version-stream-dir $SOURCE_DIR --commit-message "chore: version stream upgrade $VERSION"
git push origin $LOCAL_BRANCH_NAME
jx create pullrequest -t "chore: version stream upgrade $VERSION" -l updatebot
