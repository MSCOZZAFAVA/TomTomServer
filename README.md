# TomTomServer

> **Disclaimer:** This software and documentation are provided "as is" without warranty of any kind. Interacting with embedded hardware firmware, flashing bootloaders, or overriding device update manifests carries inherent risks. This process worked for the author, but **no claims or guarantees are made that it will work for your specific device**. If you brick, lock up, or otherwise render your device inoperable, you are solely responsible. Proceed at your own risk.

A containerized, open-source **local backend server** designed to resurrect decommissioned TomTom GPS sports watches (PID `EB030000`). By intercepting local HTTPS requests via a host entry and serving the firmware assets directly, this solution allows the official `MySports Connect` desktop software to communicate locally, bypass obsolete servers, and push updates straight to your device.

---

## Table of Contents
1. [Prerequisites & Environment Setup](#prerequisites--environment-setup)
2. [Project Structure & Configuration](#project-structure--configuration)
3. [Generating SSL Certificates](#generating-ssl-certificates)
4. [Building and Running TomTomServer](#building-and-running-tomtomserver)
5. [Client Setup & Software Installation](#client-setup--software-installation)
6. [Routing Local Traffic](#routing-local-traffic)
7. [Teardown & Cleanup](#teardown--cleanup)

---

## Prerequisites & Environment Setup

This project uses **Podman** on Windows backed by WSL2 to run the container and bind securely to HTTPS port `443`.

### Step 1: Enable WSL2 & Install Podman
1. Open PowerShell as Administrator and enable WSL2:
   ```powershell
   wsl --install --no-distribution
   ```
   *(Restart your computer if prompted to finalize virtual machine platform features).*

2. Install Podman via Windows Package Manager (`winget`):
   ```powershell
   winget install RedHat.Podman
   ```
3. Close and reopen your PowerShell window to refresh your system `PATH` variables, then verify the installation:
   ```powershell
   podman --version
   ```

### Step 2: Initialize and Configure the Podman Machine
Because containers require root permissions to bind to privileged ports (`< 1024`, such as port 443), initialize the Podman machine in **rootful** mode:
```powershell
podman machine init
podman machine set --rootful
podman machine start
```

Confirm the connection status:
```powershell
podman system connection list
```

---

## Project Structure & Configuration

### Step 1: Create the Local Project Directory
Create your workspace directory following a clean structure:
```powershell
mkdir C:\Users\your-user\Projects\TomTomServer
cd C:\Users\your-user\Projects\TomTomServer
mkdir certs, html\downloads\firmware\EB030000, html\service\config
```

Your workspace layout should look like this:
```text
C:\Users\your-user\Projects\TomTomServer\
├── certs\
│   ├── cert.pem
│   └── key.pem
├── html\
│   ├── downloads\
│   │   └── firmware\
│   │       └── EB030000\
│   │           ├── FirmwareVersionConfigV2.xml
│   │           ├── 00000012.bin
│   │           ├── 000000F0.bin
│   │           └── . . .
│   └── service
│       └── config
│           └── config.json
├── Containerfile
└── nginx.conf
```

### Step 2: Write the Nginx Configuration (`nginx.conf`)
Create `nginx.conf` in your root project folder. This handles the SSL server block and uses Nginx's `try_files` directive to map extensionless URL requests directly to physical `.bin` files on disk:
```nginx
server {
    listen 443 ssl default_server;
    server_name mysports.tomtom.com sports.tomtom-static.com mysports-preprod.tomtom.com mysports-test.tomtom.com;
    ssl_certificate /etc/ssl/certs/cert.pem;
    ssl_certificate_key /etc/ssl/private/key.pem;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers "ALL:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:@SECLEVEL=0";
    ssl_prefer_server_ciphers on;
    absolute_redirect off;
    access_log /dev/stdout;
    error_log /dev/stderr info;
    root /var/www/html;

    location / {
        try_files $uri $uri.bin $uri/ =404;
        default_type application/octet-stream;
        autoindex on;
    }
}
```

### Step 3: Write the Containerfile
Create a file named `Containerfile` in the root folder to package Nginx, your configuration, certificates, and firmware assets:
```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Install Nginx
RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*

# Copy SSL certificates
COPY certs/cert.pem /etc/ssl/certs/cert.pem
COPY certs/key.pem /etc/ssl/private/key.pem

# Copy Nginx server configuration block
COPY nginx.conf /etc/nginx/sites-available/default

# Copy firmware files and XML manifests into the web root
COPY html /var/www/html

EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]
```

### Step 4: Format the XML Manifest
Inside `html\downloads\firmware\EB030000\FirmwareVersionConfigV2.xml`, ensure your file entry URLs are stripped of the `.bin` extension so the client's validation passes successfully:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<firmwareConfig>
    <Major>1</Major>
    <Minor>8</Minor>
    <Build>52</Build>
    <isCritical>yes</isCritical>
    <BLE URL="0x00000012" version="18"/>
    <URL>0x000000F0"/>
    <URL>0x00010200"/>
    <URL>0x00810000"/>
    . . .
</firmwareConfig>
```

---

## Generating SSL Certificates

To ensure the desktop app trusts your local backend over HTTPS, generate a local certificate with Subject Alternative Names (SAN) matching TomTom's endpoints.

1. Install `openssl` inside your Podman WSL machine:
   ```powershell
   wsl -d podman-machine-default sudo microdnf install -y openssl
   ```

2. Generate the key and self-signed certificate:
   ```powershell
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem -subj "/CN=mysports.tomtom.com" -addext "subjectAltName=DNS:mysports.tomtom.com,DNS:sports.tomtom-static.com,DNS:mysports-preprod.tomtom.com,DNS:mysports-test.tomtom.com"
   ```

3. Trust the certificate in Windows so client applications accept the TLS handshake:
   ```powershell
   Import-Certificate -FilePath "C:\Users\your-user\Projects\TomTomServer\certs\cert.pem" -CertStoreLocation Cert:\LocalMachine\Root
   ```

---

## Building and Running TomTomServer

### Step 1: Build the Container Image
Navigate to your project folder and build the container image:
```powershell
cd C:\Users\your-user\Projects\TomTomServer
podman build -t tomtom-server .
```

### Step 2: Run the Container
Spin up the container, binding host port `443` to container port `443`:
```powershell
podman run -d --name tomtom-server -p 443:443 tomtom-server
```

---

## Client Setup & Software Installation

1. Obtain and run the standard desktop installer package (**`TomTomSportsConnectInstaller.exe`**).
2. Follow the setup wizard prompts to install the TomTom MySports Connect client application on your Windows system.
3. Ensure the application is completely closed before adjusting routing configurations.

---

## Routing Local Traffic

To redirect requests away from obsolete official infrastructure and into your local container:

1. **Edit the Windows Hosts File:** Open Notepad as Administrator and add the following entry to `C:\Windows\System32\drivers\etc\hosts`:
   ```text
   127.0.0.1 mysports.tomtom.com
   ```

2. **Launch MySports Connect:** Plug in your TomTom watch via USB. The desktop client will now securely query your local containerized backend and successfully communicate with your device!

---

## Teardown & Cleanup

When you are finished syncing or updating your watch, you can cleanly stop and remove the container, as well as shut down the background WSL virtualization environment:

```powershell
# Stop and remove the running container instance
podman stop tomtom-server
podman rm tomtom-server

# Shut down the WSL subsystem and background virtual machines
wsl --shutdown
