Update scripts for Minecraft on Crafty Controller, adds Geyser/Floodgate and updates the Purpur or Paper Minecraft jars

# Crafty Controller – Minecraft & Geyser/Floodgate Auto-Update Scripts

These instructions explain how to:
- Ensure `curl` is installed in your Crafty environment.
- Install and use the Minecraft Purpur update script.
- Install and use the Geyser/Floodgate update script.
- Pass options to target servers by UUID.
- Place scripts in the correct Crafty location.

---

## 1. Prerequisites

Make sure the host machine running Crafty Controller supports `apt-get` and "curl."  

**Install `apt-get` and `curl`**
```bash
apt-get update && apt-get install -y curl
```

---

## 2. Scripts Overview

You should have two scripts:

- `update-mc-core.sh`  
  Updates the Minecraft core `.jar` file to the latest Purpur build.

- `update-geyser-floodgate.sh`  
  Updates Geyser and Floodgate plugin `.jar` files to their latest builds.

---

## 3. Supported Flags

Both scripts support the same target selection flags:

| Flag                | Description                                                                 | Example                                                                 |
|---------------------|-----------------------------------------------------------------------------|-------------------------------------------------------------------------|
| `--server-name`     | Use the Crafty **server UUID** directly.                                    | `--server-name <server-UUID>`                     |
| `--help`            | Displays usage information.                                                 | `--help`                                                                |

## Pinning to a Specific Purpur Version

By default, the `update-mc-core.sh` script will update your server to the **latest build** of your current Minecraft version (e.g., 1.21.8).  
If Mojang releases a new version (e.g., 1.21.9 or 1.22), the script could update before you're ready unless you **pin** it to a specific version.

### Why Pin?
- **Pinned version**: You’ll always get the latest Purpur build for that exact version (e.g., all builds of 1.21.8).  
- **Unpinned**: You might jump to the next Minecraft release, which could break plugins.

### How to Pin
Set the environment variable `TARGET_VERSION` when running the script.

Example for Minecraft **1.21.8**:
```bash
apt-get update && apt-get install -y curl && TARGET_VERSION="1.21.8" /bin/bash /crafty/scripts/update-mc-core.sh --server-name <server-UUID>
```

---

## 4. Placing Scripts in Crafty

In CasaOS You can use the Web GUI and file manager to do this.

1. On your Crafty VM/container host, create a scripts folder:
```bash
mkdir -p /crafty/scripts
```

2. Place both `update-mc-core.sh` and `update-geyser-floodgate.sh` into this directory.

3. Make them executable:
```bash
chmod +x /crafty/scripts/update-mc-core.sh
chmod +x /crafty/scripts/update-geyser-floodgate.sh
```
*Note: In Docker/CasaOS make sure there is a Volume added to the Docker container. In CasaOS this means clicking the "Add" under the "Volumes" section in the app settings with a "Host" value of `/DATA/AppData/crafty/scripts` and a "Container" path of `/crafty/scripts`. In CasaOS this is found under the "Settings" area for the app.*

---

## 5. Running Scripts

### Update Minecraft (Purpur) core:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --server-name <server-UUID>
```

### Update Geyser & Floodgate plugins:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-geyser-floodgate.sh --server-name <server-UUID>
```

---

## 6. Combined Example Command

You can also install `curl` install `apt-get` and run both script updates all at once:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --server-name <server-UUID> && /bin/bash /crafty/scripts/update-geyser-floodgate.sh --server-name <server-UUID>
```

---

## 7. Notes
- Replace `<server-UUID>` with your own Crafty server's UUID.
- The Minecraft server will need to be restarted after running the update scripts.
- You can automate running these scripts using Cron on the host machine (NOT the Scheduler in Crafty Controller's Web Interface, that's for Minecraft terminal commands. These scripts must be run on the linux terminal)
