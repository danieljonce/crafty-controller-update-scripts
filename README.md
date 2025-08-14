Update scripts for Minecraft on Crafty Controller, adds Geyser/Floodgate and updates the Purpur or Paper Minecraft jars

# Crafty Controller – Minecraft & Geyser/Floodgate Auto-Update Scripts

These instructions explain how to:
- Ensure `curl` is installed in your Crafty environment.
- Install and use the Minecraft Purpur update script.
- Install and use the Geyser/Floodgate update script.
- Pass options to target servers by UUID or friendly name.
- Place scripts in the correct Crafty location.
- Schedule automated updates.
- Restart the server after updates.

---

## 1. Prerequisites

Make sure your Crafty Controller environment supports `apt-get`.  
You’ll need `curl` installed before either script can run.

**Install `curl` manually:**
```bash
apt-get update && apt-get install -y curl
```

**Or** include the installation step in a scheduled command (recommended if using Docker / CasaOS) within Crafty's "Schedule" section of the server.

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
| `--friendly-name`   | Use the Crafty **friendly name** for the server (script will look up UUID). | `--friendly-name <server-name>`                                         |
| `--server-name`     | Use the Crafty **server UUID** directly.                                    | `--server-name <server-UUID>`                     |
| `--help`            | Displays usage information.                                                 | `--help`                                                                |

*Note: To use the `--friendly-name` flag with the *update-mc-core.sh* script you'll need to add a Crafty API key to the script file and use an API call to get the correct UUID associated with the freiendly name, so using the UUID may be easier for that script*

---

## 4. Placing Scripts in Crafty

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

## 5. Running Scripts Manually

### Update Minecraft (Purpur) core:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --friendly-name <server-name>
```

### Update Geyser & Floodgate plugins:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-geyser-floodgate.sh --friendly-name <server-name>
```

---

## 6. Scheduling in Crafty Controller

1. Open Crafty Controller UI.
2. Go to your server’s **Schedule** tab.
3. Add a new scheduled job:
   - **Command:**  
     For Purpur updates:
     ```bash
     apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --friendly-name <server-name>
     ```
     For Geyser/Floodgate updates:
     ```bash
     apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-geyser-floodgate.sh --friendly-name <server-name>
     ```
   - **Interval:** Set to your preferred schedule (e.g., daily or weekly).
4. Save the schedule.

---

## 7. Restarting the Server After Updates

### Option 1: Restart Manually
After the scheduled job runs, restart the server from Crafty’s UI.

### Option 2: Restart Automatically
If `craftyctl` is available in your environment, append:
```bash
&& craftyctl server restart <server-name>
```
to the end of your scheduled command.  

Example:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --friendly-name <server-name> && craftyctl server restart <server-name>
```

---

## 8. Combined Example Command

You can also run both updates in one scheduled job and restart automatically:
```bash
apt-get update && apt-get install -y curl && /bin/bash /crafty/scripts/update-mc-core.sh --friendly-name <server-name> && /bin/bash /crafty/scripts/update-geyser-floodgate.sh --friendly-name <server-name> && craftyctl server restart <server-name>
```

---

## 9. Notes
- Replace `<server-name>` with your own Crafty server friendly name.
- If your Crafty install doesn’t have `craftyctl`, you’ll need to restart manually, via the UI, or via a Scheduled restart command (recommended).
- You can run these scripts on demand from the Crafty container terminal as well.
