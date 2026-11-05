# Walkthrough Challenge 3 - Deploy CPU based Large & Small Language Models (LLM/SLM)

[Back to challenge](../../challenges/challenge-03.md) - [Next Challenge's Solution](../challenge-04/solution-04.md)

## Prerequisites
* You have an arc-connected k8s cluster/finisched challenge 01.
* Verify the firewall requirements in addition to the Azure Arc-enabled Kubernetes network requirements.
* You must be logged in to az cli (az login)
* You need kubectl and helm 

## Task 1 - Check the Kubernetes cluster, check nodes and size
Execute the following script in your bash shell to access the kuberentes cluster:
```bash
kubectl get nodes
kubectl get all --all-namespaces
```

## Task 2 - Create a new namespace and prepare the helm repository

```bash
helm repo add otwld https://helm.otwld.com/
helm repo add open-webui https://helm.openwebui.com/
helm repo update
kubectl create namespace aimh
```

## Task 3 - install ollama and openwebui as an AI framework running in the Azure Arc enabled kubernetes Cluster


### Step 1: Install ollama with phi4-mini

```bash
helm install ollama otwld/ollama \
  --namespace aimh \
  --wait \
  --timeout 20m \
  --set service.type=ClusterIP \
  --set persistentVolume.enabled=true \
  --set persistentVolume.size=20Gi \
  --set ollama.models.pull[0]=phi4-mini:latest \
  --set ollama.models.run[0]=phi4-mini:latest \
  --set resources.requests.cpu="2" \
  --set resources.requests.memory="4Gi" \
  --set resources.limits.cpu="4" \
  --set resources.limits.memory="8Gi"
```

`--wait` makes Helm wait for the deployment and persistent volume to become ready,
instead of returning as soon as Kubernetes accepts the resources. The first image
pull and model download can take several minutes.

Before continuing with Step 2, verify that the rollout has completed and the
requested model is available:

```bash
kubectl rollout status deployment/ollama --namespace aimh --timeout=20m &&
kubectl exec --namespace aimh deployment/ollama -- ollama show phi4-mini:latest
```

The first command must report `deployment "ollama" successfully rolled out`.
The second must print the model information. **Only continue with Step 2 if both
commands succeed.** A `Pending` pod or a successful `helm install` without a ready
model is not sufficient.

If Helm or either check fails or times out, inspect the cause before proceeding:

```bash
kubectl get pods,pvc --namespace aimh
kubectl describe pods --namespace aimh --selector app.kubernetes.io/instance=ollama
kubectl get events --namespace aimh --sort-by=.metadata.creationTimestamp
kubectl logs deployment/ollama --namespace aimh --tail=100
```

### Step 2: Install openwebUI

```bash
helm install openwebui open-webui/open-webui \
  --namespace aimh \
  --wait \
  --timeout 20m \
  --set service.type=NodePort \
  --set service.nodePort=30080 \
  --set ollama.enabled=false \
  --set ollamaUrls[0]="http://ollama.aimh.svc.cluster.local:11434" \
  --set persistence.enabled=true \
  --set persistence.size=5Gi
```

Wait for this Helm command to finish successfully before opening OpenWebUI.
If it fails or times out, inspect the pods and events as above instead of using
the URL of an unready application.

Get the the URL of the openwebui.
```bash
export NODE_PORT=$(kubectl get -n aimh -o jsonpath="{.spec.ports[0].nodePort}" services openwebui-open-webui)
export NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[0].address}")
echo "Open http://$NODE_IP:$NODE_PORT"
```
**Note:** In this microhack lab K3s is configured to use internal IP addresses per default. Use the provided Windows workstation in the lab to open the URL.

## Task 5 - Access the openwebUI and run a prompt
* Open webbrowser to access URL provided in the previous step, create user login to the openwebUI portal.
* Try out your first prompt. If your connection works, you should see in the upper left corner the deployed model "phi4-mini".

You successfully completed challenge 3! 🚀🚀🚀

[Next challenge](../../challenges/challenge-04.md) - [Next Challenge's Solution](../challenge-04/solution-04.md)
