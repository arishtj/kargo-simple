#!/bin/sh

set -x

argo_cd_chart_version=6.9.2
argo_rollouts_chart_version=2.35.0
cert_manager_chart_version=1.14.5
kargo_version=0.8.1
#0.4.3

create_cluster() {
  cluster_name=$1
  kind create cluster \
    --wait 120s \
    --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $cluster_name
EOF
}

install_cert_manager() {
  helm upgrade --install cert-manager cert-manager \
    --repo https://charts.jetstack.io \
    --version $cert_manager_chart_version \
    --namespace cert-manager \
    --create-namespace \
    --set installCRDs=true \
    --wait
}

install_argocd() {
  helm upgrade --install argocd argo-cd \
    --repo https://argoproj.github.io/argo-helm \
    --version $argo_cd_chart_version \
    --namespace argocd \
    --create-namespace \
    --set 'configs.secret.argocdServerAdminPassword=$2a$10$5vm8wXaSdbuff0m9l21JdevzXBzJFPCi8sy6OOnpZMAG.fOXL7jvO' \
    --set dex.enabled=false \
    --set notifications.enabled=false \
    --set server.extensions.enabled=true \
    --set 'server.extensions.contents[0].name=argo-rollouts' \
    --set 'server.extensions.contents[0].url=https://github.com/argoproj-labs/rollout-extension/releases/download/v0.3.3/extension.tar' \
    --wait
}

install_argo_rollouts() {
  helm upgrade --install argo-rollouts argo-rollouts \
    --repo https://argoproj.github.io/argo-helm \
    --version $argo_rollouts_chart_version \
    --create-namespace \
    --namespace argo-rollouts \
    --wait
}

prepare_kubeconfig_for_kargo() {
  path=$1
  cp "$HOME/.kube/config" "$path"
  kubectl --kubeconfig="$HOME/kubeconfig.yaml" config view --minify --flatten --context=kind-central-mgmt > "$path"
  central_mgmt_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' central-mgmt-control-plane)
  yq eval ".clusters[].cluster.server |= sub(\"https://127.0.0.1:[0-9]+\", \"https://$central_mgmt_ip:6443\")" -i "$path"
  kubectx kind-distributed
  kubectl create namespace kargo || true
  kubectl create secret generic central-mgmt-kubeconfig --from-file=kubeconfig.yaml="$path" -n kargo

}

install_kargo() {
  cluster_type=$1
  if [ "$cluster_type" = "central-mgmt" ]; then
    helm upgrade --install kargo \
      oci://ghcr.io/akuity/kargo-charts/kargo \
      --version $kargo_version \
      --namespace kargo \
      --create-namespace \
      --set controller.shardName=central-mgmt \
      --set api.adminAccount.passwordHash='$2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm' \
      --set api.adminAccount.tokenSigningKey=iwishtowashmyirishwristwatch \
      --wait
  elif [ "$cluster_type" = "distributed" ]; then
    prepare_kubeconfig_for_kargo
    helm upgrade --install kargo \
      oci://ghcr.io/akuity/kargo-charts/kargo \
      --version $kargo_version \
      --namespace kargo \
      --create-namespace \
      -f path/to/value.yaml/for/kargo \
      --wait
  fi
}

create_cluster "central-mgmt"
install_cert_manager
install_argocd
install_argo_rollouts
install_kargo "central-mgmt"

create_cluster "distributed"
install_cert_manager
install_argocd
install_argo_rollouts
prepare_kubeconfig_for_kargo "somepath/where/u/wanna/save/kubeconfig"
install_kargo "distributed"