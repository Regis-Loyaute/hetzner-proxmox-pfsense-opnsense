This script is designed for configuring the firewall rules on a Proxmox server to manage network traffic in a secure manner, especially focusing on a setup where Proxmox is used to host a PFSense virtual machine (VM) that acts as a firewall. The script is divided into multiple sections, each serving a specific purpose in the configuration. Here's a simplified breakdown:

### Before Running the Script
- **Environment Variables Setup**: Before executing the script, you must define two environment variables: `PUBIP` (your public IP address) and `SSHPORT` (the SSH port you wish to use). These variables are used within the script to customize the firewall rules according to your specific setup.

### Script Breakdown

2. **Variables Section**: Defines several variables used throughout the script for network configuration. These include network bridges (`vmbr0`, `vmbr1`, `vmbr2`), network segments for WAN and LAN sides of a PFSense VM, and IP addresses for various interfaces and services.

3. **Clean All & Drop IPv6 Section**: Clears all existing iptables rules to start with a clean slate and sets a policy to drop all IPv6 traffic, focusing solely on IPv4 traffic management.

4. **Default Policy Section**: Sets the default policy for INPUT, OUTPUT, and FORWARD chains to DROP, meaning that all traffic is blocked unless explicitly allowed by the rules defined later in the script.

5. **Chains Section**: Creates two new chains, `TCP` and `UDP`, to manage TCP and UDP traffic separately. It also defines rules to direct new UDP and TCP connections to these chains.

6. **Global Rules Section**: Allows traffic on the localhost interface and maintains existing connections. It optionally allows ICMP traffic (ping) to pass through.

7. **Rules for `PrxPubVBR` (Public Bridge) Section**: Configures rules for incoming and outgoing traffic on the public network interface. This includes allowing SSH and Proxmox Web UI access, enabling outgoing HTTP/HTTPS and DNS requests, and permitting outgoing SSH traffic on the specified port.

8. **Forward Rules Section**: Focuses on NAT (Network Address Translation) and forwarding rules. It redirects certain incoming internet traffic to the PFSense WAN interface, except for traffic on the specified SSH port. It also allows for request forwarding to and from the PFSense WAN interface and sets up masquerading to let the WAN network use the public IP address for outbound connections.

9. **Rules for `PrxVmWanVBR` (WAN Bridge) Section**: Allows packets from Proxmox to the LAN. It also configures access to the Proxmox interface via the WAN bridge.

10. **Restarting fail2ban**: The script ends by restarting the `fail2ban` service, which helps protect against brute-force attacks by dynamically banning IPs that show malicious behavior.

This script meticulously configures firewall rules to ensure secure and efficient network traffic management, crucial for maintaining the integrity and performance of the services running on the Proxmox server.

**Clustering**

For Proxmox clustering if you want to bypass pfsense and access directly to you hypervisor you can add these iptables rules for the needed clustering ports.

iptables -A INPUT -s 88.99.212.51 -i $PrxPubVBR -d $PublicIP -p tcp --dport 8006 -j ACCEPT
iptables -A INPUT -s 88.99.212.51 -i $PrxPubVBR -d $PublicIP -p udp --dport 111 -j ACCEPT
iptables -A INPUT -s 88.99.212.51 -i $PrxPubVBR -d $PublicIP -p udp -m multiport --dport 5404:5412 -j ACCEPT

iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -d 88.99.212.51 -p tcp --sport 8006 -j ACCEPT
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -d 88.99.212.51 -p udp --sport 111 -j ACCEPT
iptables -A OUTPUT -o $PrxPubVBR -s $PublicIP -d 88.99.212.51 -p udp -m multiport --sport 5404:5412 -j ACCEPT