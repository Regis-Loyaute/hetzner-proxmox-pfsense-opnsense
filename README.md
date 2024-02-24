This guide is part of a multi articles guide on how to install and configure Proxmox on a dedicated server, secure the hypervisor behind a virtual firewall, deploy some monitoring services, setup a virtual machine backup solution, expose some services using a reverse proxy and much more.

Introduction

In this first guide, we're going to approach the method of how to install Proxmox on a dedicated server without having access to a IPMI interface, my server is hosted by Hetzner and they sadly do not offer to have access to it but instead they offer to install Proxmox with an installing tool which possess an already configured image without having the option to use ZFS. In consequences we are going to see an another solution.

Install Proxmox

We will approach the installation process first by seeing how to install Proxmox using the official ISO by using a QEMU machine, then securing hypervisor by implementing some SSH security measures.

Here's the hardware specifications that will be used in this guide.

Some prerequisites are needed before diving into the installation process, download the Proxmox ISO from the official repository:

wget -O proxmox.iso http://download.proxmox.com/iso/proxmox-ve_7.1-2.iso -O proxmox.iso  

Before starting the KVM machine we will need to take note of the network configuration which is going to be needed later to setup Proxmox, here are the commands needed:

For your public IP address:

ip a  

And to find your gateway:

ip route | grep default  

Find your network adapter which is most likely called "eth0". Then use this command and replace ADAPTATER_NAME by yours:

udevadm info -q all -p /sys/class/net/ADAPTATER_NAME | grep ID_NET_NAME  

The command should return something like the example below.

E: ID_NET_NAME_PATH=enp2s0  

Write that down, we'll also need it later.

Let’s create and run the KVM machine with the Proxmox ISO that we downloaded earlier and mount the disks where Proxmox will be installed replace sda and sdb by the names of your disks with the help of the lsblk command.

qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -boot d -cdrom proxmox.iso -drive file=/dev/sda,format=raw,media=disk -drive file=/dev/sdb,format=raw,media=disk -vnc 127.0.0.1:1  

While running VM, we are going to connect into it by creating a ssh tunnel. Open a new tab and run this command:

ssh -L 8888:127.0.0.1:5901 root@YOUR_IP_ADRESS  

You can now use any VNC client by and use 127.0.0.1 as the host address and for the port 8888.

I will be using a raid1 configuration in this tutorial to mirror my Proxmox boot installation.

Now that we are in the Network Configuration step, use your notes that we took earlier to fill in the addresses.

Press on reboot and close the session once it’s done. The reason to do that is that Proxmox is currently being virtualized therefore we are going to need to make some modifications on the network side. Run this command to create a virtual machine once again but this time it will boot directly onto the disks.

qemu-system-x86_64 -enable-kvm -smp 4 -m 4096 -drive file=/dev/sda,format=raw,media=disk -drive file=/dev/sdb,format=raw,media=disk -vnc 127.0.0.1:1  

Once you are on the shell, enter your credentials then edit the network interfaces file:

nano /etc/network/interfaces  

The file should look like this.

auto lo

 iface lo inet loopback

 iface ens3 inet manual

 auto vmbr0

 iface vmbr0 inet static

   address x.x.x.x

   netmask 255.255.255.224

   gateway x.x.x.y

   bridge_ports ens3

   bridge_stp off

   bridge_fd 0

Replace the "ens3" instances by the network adapter name that we wrote down earlier, in my case it was "enp2s0".

auto lo

 iface lo inet loopback

 iface enp2s0 inet manual

 auto vmbr0

 iface vmbr0 inet static

   address x.x.x.x

   netmask 255.255.255.224

   gateway x.x.x.y

   bridge_ports enp2s0

   bridge_stp off

   bridge_fd 0

Once the network interfaces configured, you can quit QEMU and restart your dedicated server. If no mistakes were made in the network configuration process you should have access to your Proxmox web interface by typing https://YOUR_PUBLIC_ADRESS:8006 in your browser.

Setup Proxmox

nano /etc/apt/sources.list.d/pve-enterprise.list  

Then comment out the following line to avoir using the enterprise repository.

# deb https://enterprise.proxmox.com/debian/pve buster pve-enterprise  

And add this line to use the non-subscription repository.

Do the same for the ceph list as well.

nano /etc/apt/sources.list  

deb http://download.proxmox.com/debian buster pve-no-subscription  

Finally, we can now check if there is any update and if so install them.

apt-get update

apt-get dist-upgrade -y

https://pve.proxmox.com/wiki/Package_Repositories

Basic security

Now that Proxmox is operational and exposed to the entire Internet, we will need to do establish some basic security to have some peace of mind. I'll create a new user with sudo authority to avoid using the root user then configure the ssh server with some tweaking such as disable root login, changing the default ssh port and using a ssh key to connect to my admin account.

I also like to install fail2ban to avoid any bruteforce attempt on the ssh server and on the Proxmox web interface.

First, create a new user with sudo permissions:

adduser chad-user
usermod -aG sudo chad-user

Connect to your newly created user by typing: 

su - chad-user  

Make a new directory which will contain the ssh key file and change the folder permission:

mkdir ~/.ssh
chmod 700 ~/.ssh

Now let's create the ssh key file and change the file permission:

nano ~/.ssh/authorized_keys ## write your key inside
chmod 600 ~/.ssh/authorized_keys

Make some changes into the ssh server parameters file by replacing the default values with the example below:

nano /etc/ssh/sshd_config  ## Change your default ssh port

Port 69420

## Disable root login

PermitRootLogin no

## Disable password login which is not needed anymore with the key

PasswordAuthentication no

Restart the ssh server to apply the modification that we just made:

/etc/init.d/ssh restart  

To add another layer of security, fail2ban does a great job at blocking bruteforce attack by banning the IP address after as many attempts you configure it to. Let's install the service first.

apt install fail2ban  

Then you can configure it in the follow file:

nano /etc/fail2ban/jail.local  

Once inside this file, there are several parameters that you can configure like you want such as the ban time length, the number of logins attempts and if you want to be notified by email. Here's what a typical config looks like.

[DEFAULT]

bantime = 84600

findtime = 600

maxretry = 3

destemail = chad-user@example.com

sendername = Fail2ban

action = %(action_mwl)s

[sshd]

enabled = true

port = 69420

Bantime is the ban length, i chose 84600 seconds but you can change it to suit your taste.

Findtime defines in seconds the time since which an anomaly is searched for in the logs, it is recommended to not choose a high value otherwise the quantity of logs to be analyzed could become exceptionally large and therefore have an impact on performance.

Maxretry is the amount of login attempt that is allowed before getting banned.

In the sshd section, we decide that fail2ban is enabled and change the ssh port to yours.

If you want to be extra careful, you can also apply fail2ban to the Proxmox interface. It won't be needed in the future as the Proxmox interface will only be accessible through a VPN but if you plan to expose it publicly then i suggest you to do that.

[proxmox]

enabled = true

port = https,http,8006

filter = proxmox

logpath = /var/log/daemon.log

maxretry = 3

bantime = 3600

Now restart the fail2ban service to apply the configuration we just made: 

systemctl restart fail2ban   

Proxmox bridge configuration

First, backup your current network configuration files.

cp /etc/network/interfaces /etc/network/interfaces.cp  

Create a first linux bridge by clicking on "Create/Linux Bridge" in the network configuration area on Proxmox, the first virtual bridge will access to the WAN network, and a second one for the LAN network.

I am using a /30 CIDR which means only 2 IPs, to restrict how much IP there is available in case someone manages to access the WAN network there won't be any IP left to take.

For the LAN side, i chose a /24 CIDR in order to have plenty of room for how much virtual machines you want to deploy.

To apply the network modification that we just made without rebooting we need to install ifupdown2:

apt install ifupdown2   

Once installed you can now click on "Apply Configuration'' for the changes to take effect.

Installing and configuring pfSense

Currently the hypervisor is on the front line and pfSense is retreated behind it, however the end goal is to have pfSense on the front line and having Proxmox to act as just as a router from a network standpoint.

Here's how to download the pfSense iso directly into Proxmox image folder if you have a pretty slow upload speed like me:

cd /var/lib/vz/template/iso  

wget https://frafiles.pfsense.org/mirror/downloads/pfSense-CE-2.5.1-RELEASE-amd64.iso.gz  

openssl dgst -sha256 pfSense-CE-2.5.1-RELEASE-amd64.iso.gz  

gunzip pfSense-CE-2.5.1-RELEASE-amd64.iso.gz  

Create the pfSense virtual machine as shown below:

Choose vmbr1 as the first network interface for the WAN interface and finish the creation process.

Once your VM is created, go into the pfSense VM hardware tab and add a second network device with the vmbr2 interface which correspond to the LAN.

You can now start the pfSense VM and go through the regular install process.

After pfSense has rebooted, choose to not configure any VLAN.

For the WAN interface choose vtnet0 interface, which correspond to vmbr1.

For the LAN interface choose vtnet1, which correspond to vmbr2.

We need to attribute ip address to the interfaces, type 2 to select the option to do that.

Let's start with the WAN interface, type 1 to choose it and here's how i've configured it:

DHCP : no

IPv4 : 10.0.0.2

Subnet bit count : 30

Upstream gateway address : 10.0.0.1

DHCP6 : no

IPv6 : leave empty and press enter

Do you want to revert HTTP as the webConfigurator protocol? no

And we configure the LAN interface by typing 2.

IPv4 : 192.168.5.254

Subnet bit count : 24

Upstream gateway address : leave empty and press enter

IPv6 : leave empty and press enter

Activate the DHCP server : no

Do you want to revert HTTP as the webConfigurator protocol? no

You can now have access to the pfSense web interface either from a VM located within the LAN or by creating a ssh tunnel and redirect the https port.

ssh chad-user@PROXMOX_PUB_IP -p 42069 -L 127.0.0.1:8443:192.168.5.254:443  

Now you can have access to your pfSense web interface with the following address https://localhost:8443.

You can follow the configuration wizard and let almost everything by except for the 4th step, it is important to uncheck the "Block RFC1918 Private Networks".

The reason is this option will block packets that arrive from a private network from entering through the WAN interface. A private network is a network whose IP starts with 10, 172.16, or 192.168. 

And since our WAN is precisely on a private network therefore this choice will block everything.

Creating a VM which will serve the purpose of testing the LAN side is also needed, in my case i choose to use Ubuntu virtual machine.

cd /var/lib/vz/template/iso 

wget https://releases.ubuntu.com/20.10/ubuntu-20.10-desktop-amd64.iso   

As for the network interface, be careful to pick the right one which is vmbr2 which corresponds to the LAN.

Either way, if you connect into the WAN, there will be no IP available.

Go through the regular Ubuntu installation process and once you are logged in, go into the network settings, and change as shown below.

I chose the IP 192.168.5.100 but you can choose anything you want as long it is within the IP range chosen for the LAN and the IP isn't already used by something else. The netmask is a /24 and the gateway is the pfSense IP address.

You may have noticed that the virtual machine doesn’t have access to internet, we are going to address that issue further on.

Let's create a route on the hypervisor which will allow to redirect every packet going to the LAN has to go through the WAN pfSense interface. This rule makes it as if pfSense is in the frontline, before entering the LAN.

We create a /root/pfsense-route.sh file with the following command.

cat > /root/pfsense-route.sh << EOF

#!/bin/sh

##enable IP forwarding

echo 1 > /proc/sys/net/ipv4/ip_forward

##Redirect intended packets to LAN for the WAN pfSense interface

ip route change 192.168.5.0/24 via 10.0.0.2 dev vmbr1

EOF

For this file to launch automatically as soon as we boot, we run the command chmod +x /root/pfsense-route.sh and we will add at the end of the /etc/network/interfaces file the line post-up/root/pfsense-route.sh at the end of the vmbr2 config block, just before the #LAN comment: 

[…]

 auto vmbr2

 iface vmbr2 inet static

 address 192.168.5.1/24

 bridge-ports none

 bridge-stp off

 bridge-fd 0

 post-up /root/pfsense-route.sh

 LAN

Now if you run the /root/pfsense-route.sh script and try to ping the hypervisor from the Ubuntu VM or the other way around that shouldn't work. It means the packets are trying to go through pfSense, but it is blocking them.

If you go on the pfSense interface and look at the Firewall/System Logs, you can see the pings that have been blocked.

IPTABLES

Now that the base of our script is working, we will continue to add iptables rules. As it is quite long, I will explain it to you step by step. For those who want the full version of the file right away, it's available here.

Note: The big problem with iptables and firewall rules in general is that even when you're an expert, if you've ever messed up (or for one reason or another, the commands I give are not 100% compatible in your context there is a small subtlety) you risk cutting yourself off from your server.

A safe way to limit this kind of risk is to do the following every time you make a change:

Backup these 3 files:  

/etc/network/interfaces /root/pfsense-route.sh /root/iptables.sh  

Disable/delete the lines with the post-up /root/pfsense-route.sh and/or /root/pfsense-route.sh in /etc/network/interfaces, which will allow you to regain control after a reboot.

Run the script by hand for the first time, then reboot only IF EVERYTHING is working properly!

In the situation where you do not have any access to your server anymore, reboot the server with the help of your hosting provider web panel and restore the files that you backed up earlier.

Note: Do not run these instructions one at a time either. The first thing we do is drop everything, then re-authorize little by little. Hence you have a good chance of blocking yourself by doing that.

Define variables

We will first export the variables that will be present in the scripts such as your public IP address and your ssh port.

export PUBIP=YOUR_PUB_IP

export SSHPORT=42069

Then create the IPTABLES script by running the following command:

cat > /root/iptables.sh << EOF

#!/bin/sh

# ---------

# VARIABLES

# ---------

## Proxmox bridge holding Public IP

PrxPubVBR="eno1"

## Proxmox bridge on VmWanNET (PFSense WAN side) 

PrxVmWanVBR="vmbr1"

## Proxmox bridge on PrivNET (PFSense LAN side) 

PrxVmPrivVBR="vmbr2"

## Network/Mask of VmWanNET

VmWanNET="10.0.0.0/30"

## Network/Mmask of PrivNET

PrivNET="192.168.5.0/24"

## Network/Mmask of VpnNET

VpnNET="10.2.2.0/24"

## Public IP => Your own public IP address

PublicIP="${PUBIP}"

## Proxmox IP on the same network than PFSense WAN (VmWanNET)

ProxVmWanIP="10.0.0.1"

## Proxmox IP on the same network than VMs

ProxVmPrivIP="192.168.5.1"

## PFSense IP used by the firewall (inside VM)

PfsVmWanIP="10.0.0.2"

EOF

We here define the variables which will be used multiple times in the script. Make sure that the PublicIP=''' does indeed hold your public IP address.

Drop everything and start anew

Next, we create chains that will capture all new TCP and UDP connections, respectively then we add some basic rules:

Allow localhost connections.

We do not stop existing connections. Like your SSH connection for example.

And we allow ping which is useful for troubleshooting.

cat >> /root/iptables.sh << EOF

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

EOF

Ingoing

Those rules will dictate the vmbr0 interface which linked us to the Internet. We add 2 following rules that are for incoming packets:

We authorize new connections on the SSH port which go through vmbr0 and whose destination is our public IP.

We allow new connections on port 8006 which go through vmbr0 and whose destination is our public IP.

cat >> /root/iptables.sh << EOF

# --------------------

# RULES FOR PrxPubVBR

# --------------------

### INPUT RULES

# ---------------

# Allow SSH server

iptables -A TCP -i \$PrxPubVBR -d \$PublicIP -p tcp --dport ${SSHPORT} -j ACCEPT

# Allow Proxmox WebUI

iptables -A TCP -i \$PrxPubVBR -d \$PublicIP -p tcp --dport 8006 -j ACCEPT

EOF

Check that line just below "# Allow SSH server" which should have the port you are using for SSH.

We will not need those rules later but instead, we will connect to the VPN and from there we will have access to SSH or Proxmox.

Outgoing

Then we add the outgoing packets:

cat >> /root/iptables.sh << EOF  ### OUTPUT RULES

# ---------------

# Allow ping out

iptables -A OUTPUT -p icmp -j ACCEPT

### Proxmox Host as CLIENT

# Allow HTTP/HTTPS

iptables -A OUTPUT -o \$PrxPubVBR -s \$PublicIP -p tcp --dport 80 -j ACCEPT

iptables -A OUTPUT -o \$PrxPubVBR -s \$PublicIP -p tcp --dport 443 -j ACCEPT

# Allow DNS

iptables -A OUTPUT -o \$PrxPubVBR -s \$PublicIP -p udp --dport 53 -j ACCEPT

### Proxmox Host as SERVER

# Allow SSH 

iptables -A OUTPUT -o \$PrxPubVBR -s \$PublicIP -p tcp --sport ${SSHPORT} -j ACCEPT

# Allow PROXMOX WebUI 

iptables -A OUTPUT -o \$PrxPubVBR -s \$PublicIP -p tcp --sport 8006 -j ACCEPT

EOF

cat >> /root/iptables.sh << EOF

MASQUERADE MANDATORY

Allow WAN network (PFSense) to use vmbr0 public adress to go out

iptables -t nat -A POSTROUTING -s \$VmWanNET -o \$PrxPubVBR -j MASQUERADE

EOF

First, we allow the pings to go out. This rule is redundant with another previous one where pings in all directions were allowed.

The idea is that the previous rule is very permissive in order to be able to debug. But it will not stay for too long.

On the other hand, allowing an outgoing ping, it can still be used on occasion, and it poses zero security problems.

Then I allow the HTTP and HTTPS packets to go out. This is what will give us access to the internet. Besides, you can try. Ping 1.1.1.1 before entering these new rules, it should be blocked, then try again after entering these new rules, and it should work!

Forward

Finally, we route all the traffic to the pfSense:

cat >> /root/iptables.sh << EOF  ### FORWARD RULES

# ----------------

### Redirect (NAT) traffic from internet 

# All tcp to PFSense WAN except ${SSHPORT}, 8006

iptables -A PREROUTING -t nat -i \$PrxPubVBR -p tcp --match multiport ! --dports ${SSHPORT},8006 -j DNAT --to \$PfsVmWanIP

# All udp to PFSense WAN

iptables -A PREROUTING -t nat -i \$PrxPubVBR -p udp -j DNAT --to \$PfsVmWanIP

# Allow request forwarding to PFSense WAN interface

iptables -A FORWARD -i \$PrxPubVBR -d \$PfsVmWanIP -o \$PrxVmWanVBR -p tcp -j ACCEPT

iptables -A FORWARD -i \$PrxPubVBR -d \$PfsVmWanIP -o \$PrxVmWanVBR -p udp -j ACCEPT

# Allow request forwarding from LAN

iptables -A FORWARD -i \$PrxVmWanVBR -s \$VmWanNET -j ACCEPT

EOF

The beginning is a pre-routing rule. This means that the action takes place on the packet before anything else. For example, if someone tries to connect to port 3812 of your Nextcloud, we do not necessarily want to drop it. This kind of decision will be the future job of pfSense. Without the pre-routing rule, the packet would be dropped by default.

So instead, we send it to pfSense.

Note that this rule applies except for ssh and 8006 ports, which have a bit of special treatment. Again, later, when the VPN is setup, these rules will not be needed anymore.

The next paragraph goes along with what we have just done. Basically, it says: If a packet is transferring from the Internet to pfSense, then we allow it. And that is good, since we just said that all the packets that come from the Internet are automatically transferred to pfSense.

Finally, we also do the opposite. All the packets which are in transfer from the pfSense (and therefore which likely goes to the Internet) are also accepted. Communication goes both ways.

To summarize: A package comes from the Internet. We pre-route him to pfSense. We accept this transfer. The pfSense receives it. The pfSense will decide, for example send it to a VM, receive a response, then send this packet back to the Internet. We accept this transfer again.

We now have everything we need for VMs to have access to the Internet.

MASQUERADE

This part allows a machine on a local network to access the Internet without having a public IP.

cat >> /root/iptables.sh << EOF  ### MASQUERADE MANDATORY

iptables -t nat -A POSTROUTING -s \$VmWanNET -o \$PrxPubVBR -j MASQUERADE

EOF

From there the script is ready. Try to run it and if you do not throw yourself out, well done.

chmod +x /root/iptables.sh

Now your LAN is connected to the Internet.

Hosting services

For the example here, we will use our Ubuntu Desktop VM. This is really as an example.

Let's go to the VM, and in the terminal we install nginx: sudo apt install nginx.

Once the installation is done, verify that the server is working properly by going to http://localhost from the VM. You should see the nginx welcome screen.

Now, we want to get to this page from the Internet. In order to do that, we will go to the configuration of the pfSense, and click on Firewall / NAT, then add:

Interface : WAN

Protocol : TCP

Destination : Any

Destination Port Range : 7000

Redirect target IP : 192.168.5.100

Redirect target port : 80

Description : Nginx test server

Validate and apply the changes.

Now try to access the follow URL:

http://YOUR_PUBLIC_IP.com:7000

VPN

The idea is that we are going to create a new virtual network: 10.2.2.0/24. The pfSense will be in this virtual network. And we will be able to connect to this virtual network, so that our pc will have a private IP of type 10.2.2.2 (10.2.2.1 will be reserved for the pfSense).

And from within the vpn, you can access the LAN through the pfSense.

Creation of the authority certificate

In pfSense, click on System / Cert. Manager then add:

Descriptive Name : The authority certificate

Method : Create an internal Certificate Authority

Key length : 4096

Digest Algorithm : sha256

Lifetime : 3650

Common Name : homelab.localdomain (change it as you wish)

Country Code : DE

Creation of the server certificate

Click on the "Certificates" tab and add:

Method : Create an internal Certificate

Descriptive Name : VPN server

Certificate authority : Choose your newly created certification authority 

Key length : 4096

Digest Algorithm : sha256

Lifetime : 3650

Common Name : vpn.homelab.localdomain

Certificate Type : Server Certificates

Creation of the client certificate

We create a new certificate, but change the type at the end:

Method : Create an internal Certificate

Descriptive Name : VPN client

Certificate authority : Choose your newly created certification authority

Key length : 4096

Digest Algorithm : sha256

Lifetime : 3650

Common Name : vpn-client.homelab.localdomain

Certificate Type : User Certificates

We are done for the certificate’s creation process.

VPN server setup

Let’s move onto VPN/OpenVPN and then add the following parameters:

Server mode : Remote Access (SSL/TLS + User Auth)

Protocol : UDP

Interface : WAN

Local Port : 42069 (change it as you want)

Description : My VPN

TLS Configuration : Checked

Peer Certificate Authority : Choose your certification authority

Server Certificate : Choose the server certificate 

DH Parameter Length : 4096

Encryption Algorithm : You can keep the default settings or change to a higher one.

IPv4 Tunnel Network : 10.2.2.0/24

Redirect IPv4 Gateway : Checked. This box will allow you to access the internet through the VPN. Otherwise, you can specify the local network you want to access with the VPN (192.168.5.0/24 in our case).

Concurrent connections : Put the number corresponding to the number of devices you will connect simultaneously.

Dynamic IP : Tick the box.

And we are done for this part.

Now, we’ll also need to create a user for the authentication process.

Go to System/User manager then add:

Disabled : Leave it unchecked

Username : chad-user

Password : superhardpassword

Save. Then go back to edit the user and add the client certificate that we created earlier to him.

In User Certificates, click Add, then:

Method : Choose an existing certificate

Existing Certificate : VPN client

Client configuration

You can easily export a configuration file to automatically configure your VPN client, whether on Windows, Mac, Linux, Android with the help of a package that you can install on pfSense.

Go to System / Package Manager, then Available Packages, and type openvpn-client-export on the search bar.

The click on the install icon.

Return to VPN / OpenVPN, and we find the new Client Export tab.

Remote Access Server : My VPN

Host Name Resolution : Other - and write the public IP of your server

Use Random Local Port : Tick the box

We will add a route for the VPN. Go back to the /root/pfsense-route.sh file and add this line:

ip route add 10.2.2.0/24 via 10.0.0.2 dev vmbr1

pfSense must accept these packages as well. In the interface, we add two rules. The first says to accept packets in UDP which are destined for the pfSense on the port of the V-PN:

Action : Pass

Interface : WAN

Address Family : IPv4

Protocol : UDP

Source : Any

Destination : WAN net

Destination port range : 18223 (your VPN port)

Description : Access to the VPN from the Internet

You also need to add this rule to have access to the internet while being connect to the vpn:

Action : Pass

Interface : OpenVPN

Address Family : IPv4

Protocol : Any

Source : Network – 10.2.2.0/24

Destination : Any

Description : Access to the Internet from the VPN

Accessing the internet while being connected to the VPN is now possible.

Now that the VPN server is up and running. We can now deactivate the public access to the Proxmox interface.

First, redirect port 8006 to pfSense (removing the exception in iptables). This will cancel access to the interface from the Internet.

Second, Allow access to port 8006 of the Proxmox server from the pfSense. This will allow access from the VPN.

In the iptables file, we will edit the following line:

iptables -A PREROUTING -t nat -i $PrxPubVBR -p tcp --match multiport ! --dports 21153,8006 -j DNAT --to $PfsVmWanIP  

Simply remove 8006. And execute the file. Now you no longer have access to the Proxmox web interface at all.

At the end of the iptables script, we add the following instruction: service fail2ban restart.

The iptables script does not start automatically at boot. So, if Proxmox restarts, we lose all our rules.

To solve this, we will run apt install iptables-persistent and now the rules will persist after a reboot.

How to debug

I don't necessarily expect EVERYTHING to work in this tutorial.

It works for me.

But maybe you have a different machine or a different provider, you might even be left-handed, who knows! I think it's more important to teach you how to do it yourself than to give you a list of instructions to copy/paste, and then when it doesn't work you get stuck.

So, I present in this section the tools I have learned and found especially useful for debugging.

Trace your packages

When you try to ping a server, or just connect to it, and it doesn't work, it's frustrating.

The pointer blinks, nothing happens, and you know nothing will happen. Just if you wait a minute or two, you'll see a nice "Timeout".

It could be because the packet got lost, because it was eaten by a firewall, or even because the service you are trying to access is offline. To understand the path of a packet, you can use tcpdump.

The -i option allows you to specify the interface on which you are listening. For example: tcpdump -i vmbr0.

The -p option allows you to specify the protocol you are listening to. For example: tcpdump -p udp.

And the option port allows you to specify the port. For example: tcpdump port 22.

You will see, or not, if a packet goes out or comes in. If it doesn't go out, it is most likely blocked by iptables or the firewall of the machine you are on.

You can use this instruction on the hypervisor, on a VM, and also on the PFSense.

Log iptables

Is the iptable script dropping the packets you send?

Add a statement to your script before the statement that potentially drops your packet. For example, add:

iptables -A OUTPUT -o vmbr1 -s 10.0.0.1 -p tcp -j LOG

The idea is to replace the end (ACCEPT) with LOG. And then the logs will be displayed in /var/log/syslog.

Use the PFSense logs

In the PFsense interface, you can go to Status / System Logs, then Firewall, to see all blocked connections. Does yours appear? Maybe you should create a rule. Yours doesn't appear? Then either it has passed, or it has not even arrived on the PFSense.

By clicking on the little +, you can easily add a rule specifically for the connection that was blocked.

If you suspect that it got through, then look at where it went by sniffing the packets on the machine. Either with tcpdump or by going to Diagnostics/Packet Capture.

A problem with the VPN? The logs are in Status / System Logs, then OpenVPN.


https://homelabing.fr/installing-hetzner-proxmox-pfsense/
