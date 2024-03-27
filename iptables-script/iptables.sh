# Run these commands before running the script.

export PUBIP=YOUR_PUB_IP
export SSHPORT=YOUR_SSH_PORT

#!/bin/sh
# ---------
# VARIABLES
# ---------
## Proxmox bridge holding Public IP
PrxPubVBR="vmbr0"
## Proxmox bridge on VmWanNET (PFSense WAN side) 
PrxVmWanVBR="vmbr1"
## Proxmox bridge on PrivNET (PFSense LAN side) 
PrxVmPrivVBR="vmbr2"
## Network/Mask of VmWanNET
VmWanNET="10.0.0.0/30"
## Network/Mmask of PrivNET
PrivNET="192.168.10.0/24"
## Network/Mmask of VpnNET
VpnNET="10.2.2.0/24"
## Public IP => Your own public IP address
PublicIP="${PUBIP}"
## Proxmox IP on the same network than PFSense WAN (VmWanNET)
ProxVmWanIP="10.0.0.1"
## Proxmox IP on the same network than VMs
ProxVmPrivIP="192.168.10.1"
## PFSense IP used by the firewall (inside VM)
PfsVmWanIP="10.0.0.2"
# ---------------------
# CLEAN ALL & DROP IPV6
# ---------------------
### Delete all existing rules.
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
### This policy does not handle IPv6 traffic except to drop it.
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP
# --------------
# DEFAULT POLICY
# --------------
### Block ALL !
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
# ------
# CHAINS
# ------
### Creating chains
iptables -N TCP
iptables -N UDP
# UDP = ACCEPT / SEND TO THIS CHAIN
iptables -A INPUT -p udp -m conntrack --ctstate NEW -j UDP
# TCP = ACCEPT / SEND TO THIS CHAIN
iptables -A INPUT -p tcp --syn -m conntrack --ctstate NEW -j TCP
# ------------
# GLOBAL RULES
# ------------
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
# Don't break the current/active connections
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Allow Ping - Comment this to return timeout to ping request
iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
# --------------------
# RULES FOR PrxPubVBR
# --------------------
### INPUT RULES
# ---------------
# Allow SSH server
iptables -A TCP -i $PrxPubVBR -d $PublicIP -p tcp --dport ${SSHPORT} -j ACCEPT
# Allow Proxmox WebUI
iptables -A TCP -i $PrxPubVBR -d $PublicIP -p tcp --dport 8006 -j ACCEPT
### OUTPUT RULES
# ---------------
# Allow ping out
iptables -A OUTPUT -p icmp -j ACCEPT
### Proxmox Host as CLIENT
# Allow HTTP/HTTPS
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --dport 443 -j ACCEPT
# Allow DNS
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p udp --dport 53 -j ACCEPT
### Proxmox Host as SERVER
# Allow SSH 
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --sport ${SSHPORT} -j ACCEPT
# Allow PROXMOX WebUI from public IP
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -p tcp --sport 8006 -j ACCEPT


### FORWARD RULES
# ----------------
### Redirect (NAT) traffic from internet 
# All tcp to PFSense WAN except ${SSHPORT}
iptables -A PREROUTING -t nat -i $PrxPubVBR -p tcp --match multiport ! --dports ${SSHPORT} -j DNAT --to $PfsVmWanIP
# All udp to PFSense WAN
iptables -A PREROUTING -t nat -i $PrxPubVBR -p udp -j DNAT --to $PfsVmWanIP
# Allow request forwarding to PFSense WAN interface
iptables -A FORWARD -i $PrxPubVBR -d $PfsVmWanIP -o $PrxVmWanVBR -p tcp -j ACCEPT
iptables -A FORWARD -i $PrxPubVBR -d $PfsVmWanIP -o $PrxVmWanVBR -p udp -j ACCEPT
# Allow request forwarding from LAN
iptables -A FORWARD -i $PrxVmWanVBR -s $VmWanNET -j ACCEPT
### MASQUERADE MANDATORY
# Allow WAN network (PFSense) to use vmbr0 public adress to go out
iptables -t nat -A POSTROUTING -s $VmWanNET -o $PrxPubVBR -j MASQUERADE
# --------------------
# RULES FOR PrxVmWanVBR
# --------------------
### Authorize packets from Proxmox to LAN
iptables -A OUTPUT -o $PrxVmWanVBR -s $ProxVmWanIP -p udp -j ACCEPT
iptables -A OUTPUT -o $PrxVmWanVBR -s $ProxVmWanIP -p tcp -j ACCEPT

### Proxmox interface access
iptables -A TCP -i $PrxVmWanVBR -d $ProxVmWanIP -p tcp --dport 8006 -j ACCEPT

service fail2ban restart
