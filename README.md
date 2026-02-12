# Quadrant
![Bash](https://img.shields.io/badge/language-bash-green)
![QEMU](https://img.shields.io/badge/hypervisor-QEMU-red)
![License](https://img.shields.io/badge/license-MIT-blue)
![Sudo](https://img.shields.io/badge/sudo-not%20required-success)
Lightweight VM orchestration tool using pure QEMU  (no sudo required)

## About
- **No root privileges required** — runs entirely under user permissions using QEMU's user-mode and socket networking
- **Multi-stage provisioning** — separates base setup (Docker installation) from advanced tasks (Swarm initialization, token exchange between nodes)
- **Socket-based internal networks** — connect VMs via socket pairs without bridge setup or `sudo`
- **Per-VM configuration** — customize CPU, RAM, networks, and provisioning scripts for each machine via `Quadrantfile`

## Requirements
- Bash ver. 4.3+
- ssh / scp
- qemu-system-x86_64 (or another architecture, or binary)
- base image

## Description
- Error messages and console output are currently available only in Russian
- Only QCOW2 format is supported for base images (`BASE_DISK`). Other formats (RAW, VDI) require conversion via `qemu-img` before use

## Installation
```bash
git clone https://github.com/clomase/Quadrant.git
cd ~/Quadrant
bash quadrant.sh install
source ~/.bashrc
```

## Uninstall
```bash
quadrant uninstall
unalias quadrant
```

## Preparation base image
- Define the username to be used inside the guest OS and set it in the script on your host at ~/.q-drant/quadrant.sh (default: vagrant):\
  IN_GUEST_USER="USERNAME"
- Create key
  ssh-keygen -f ~/path-to-castom-key/id_USERNAME_key
  chmod 600 ~/path-to-castom-key/id_USERNAME_key
```bash
# Example preparation guest script
# Set username
IN_GUEST_USER="${IN_GUEST_USER:-vagrant}" # replace row with your USERNAME

# Create user
sudo useradd -m -G sudo -s /bin/bash "$IN_GUEST_USER"
echo "${IN_GUEST_USER}:${IN_GUEST_USER}" | sudo chpasswd

# Configure passwordless sudo
echo "$IN_GUEST_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$IN_GUEST_USER"

# Install and configure SSH
sudo apt update && sudo apt install -y openssh-server
sudo mkdir -p "/home/$IN_GUEST_USER/.ssh"
sudo chmod 700 "/home/$IN_GUEST_USER/.ssh"

# (After copying public key from host)
# sudo cp /path/to/id_rsa.pub "/home/$IN_GUEST_USER/.ssh/authorized_keys"
sudo chown -R "$IN_GUEST_USER:$IN_GUEST_USER" "/home/$IN_GUEST_USER/.ssh"
sudo chmod 600 "/home/$IN_GUEST_USER/.ssh/authorized_keys"

# Ensure SSH daemon accepts key auth
sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```
 **Note** The base image must be prepared **once**

## Usage

### Initialization
```bash
quadrant init

```
Creates **Quadrantfile** in the current directory
Edit it to specify:
 - BASE_DISK : path to your base QCOW2 image
 - SSH_PASS_KEY : path to private SSH key for guest access
 - MACHINES_NAMES : list of VM names (default: node1)
 - Per-VM overrides (VMNAME_CPU, VMNAME_RAM, etc.)
 
### 
