# SP-Labs Troubleshooting Guide

## Common Issues

### 1. UPF fails to start — TUN device error

**Symptom:** UPF container exits with `Could not create TUN device`

**Fix:**
```bash
# Ensure TUN module is loaded on the host
sudo modprobe tun
echo "tun" | sudo tee /etc/modules-load.d/tun.conf

# The UPF container requires NET_ADMIN + /dev/net/tun — already set in compose
```

### 2. UERANSIM gNB cannot connect to AMF

**Symptom:** `NGAP connection failed` in gNB logs

**Check:**
```bash
# Verify AMF is listening on SCTP
docker exec amf ss -tlnp | grep 38412

# Check N2 network connectivity
docker exec gnb ping -c 2 10.33.34.12

# Verify AMF config has correct NGAP bind address
docker logs amf 2>&1 | grep -i ngap
```

### 3. UE registration rejected — Authentication failure

**Symptom:** `Registration rejected: cause=5GMM_CAUSE_ILLEGAL_UE`

**Fix:**
```bash
# Verify subscriber is registered in Open5GS
curl -s http://localhost:9999/api/subscriber | python3 -m json.tool

# Re-register subscriber
bash infrastructure/scripts/register-subscriber.sh
```

### 4. No internet from UE — PDU session but no data

**Symptom:** UE gets IP (10.45.x.x) but cannot ping 8.8.8.8

**Fix:**
```bash
# Check IP forwarding on host
sysctl net.ipv4.ip_forward   # Must be 1

# Check NAT rules
sudo iptables -t nat -L POSTROUTING -n | grep 10.45

# Re-apply NAT if missing
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
```

### 5. MongoDB connection refused

**Symptom:** Open5GS NFs log `MongoClient connection error`

**Fix:**
```bash
# Check MongoDB is running
docker ps | grep mongodb
docker logs mongodb

# Restart MongoDB
docker compose -f 5g-lab/docker-compose.yml restart mongodb
```

### 6. Sionna — CUDA not available

**Symptom:** `Could not load dynamic library 'libcuda.so'`

**Fix:**
```bash
# Install NVIDIA Container Toolkit
sudo apt install -y nvidia-container-toolkit
sudo systemctl restart docker

# Verify GPU is visible
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### 7. Docker Compose version mismatch

**Symptom:** `unknown shorthand flag: 'f' in -f`

**Fix:** Ensure Docker Compose v2 is installed (bundled with Docker 24+):
```bash
docker compose version    # Should show v2.x
# If not:
sudo apt install docker-compose-plugin
```

## Useful Debug Commands

```bash
# 5G Core logs (all NFs)
docker compose -f 5g-lab/docker-compose.yml logs -f

# Specific NF logs
docker logs amf -f --tail=50
docker logs smf -f --tail=50
docker logs upf -f --tail=50

# UERANSIM logs
docker logs gnb -f --tail=50
docker logs ue -f --tail=50

# Capture NGAP/GTP traffic
docker exec amf tcpdump -i any -w /tmp/ngap.pcap port 38412
docker exec upf tcpdump -i any -w /tmp/gtp.pcap port 2152

# Check container networking
docker network ls | grep sp-labs
docker network inspect sp-labs-sbi
```
