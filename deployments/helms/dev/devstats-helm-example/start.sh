kubectl create namespace devstats
./switch_namespace.sh devstats
kubectl apply -f sc.yaml
kubectl apply -f pv.yaml
kubectl apply -f pv1.yaml
kubectl apply -f pv2.yaml
kubectl apply -f pv3.yaml
kubectl apply -f pv4.yaml
kubectl apply -f pv5.yaml
helm install ./devstats-helm-example --generate-name