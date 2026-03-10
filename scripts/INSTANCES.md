# VM Instance Management

Tools for creating, cloning, and managing named VM instances.

All commands are run from the **project root** (`vphone-cli/`).

---

## instance.mk — Primary interface

`instance.mk` is the recommended entry point. It wraps all instance operations.

```
make -f instance.mk <target> INSTANCE=<name> [options]
```

### Targets

| Target          | Description                                           |
| --------------- | ----------------------------------------------------- |
| `setup`         | Full setup: tools → vm → firmware → restore → CFW → first boot |
| `boot`          | Boot instance in GUI mode                             |
| `boot_dfu`      | Boot instance in DFU mode                             |
| `from_template` | Create instance from template (APFS clone, instant)   |
| `clone`         | Clone instance to a new directory                     |
| `list`          | List existing instances (directories with `Disk.img`) |
| `iproxy`        | Start SSH tunnel for instance                         |
| `iproxy_list`   | Show all running iproxy tunnels                       |
| `ssh`           | SSH into instance (requires running iproxy)           |

### Setup options

| Variable              | Default | Description                                  |
| --------------------- | ------- | -------------------------------------------- |
| `JB=1`                | `0`     | Jailbreak firmware + CFW                     |
| `DEV=1`               | `0`     | Dev firmware + CFW                           |
| `SKIP_PROJECT_SETUP=1`| `0`     | Skip `setup_tools` / build stage             |
| `NONE_INTERACTIVE=1`  | `0`     | Auto-continue first-boot prompts             |
| `SUDO_PASSWORD=...`   |         | Preload sudo credential                      |

### Boot options

| Variable    | Default | Description    |
| ----------- | ------- | -------------- |
| `CPU=N`     | `8`     | vCPU count     |
| `MEMORY=N`  | `8192`  | RAM in MB      |

---

## Common workflows

### 1. Set up a fresh instance

```sh
# Regular firmware
make -f instance.mk setup INSTANCE=iphone_01

# Jailbreak firmware
make -f instance.mk setup INSTANCE=iphone_01 JB=1

# Skip tools/build (already set up)
make -f instance.mk setup INSTANCE=iphone_02 SKIP_PROJECT_SETUP=1 JB=1
```

### 2. Boot an instance

```sh
make -f instance.mk boot INSTANCE=iphone_01

# Custom resources
make -f instance.mk boot INSTANCE=iphone_01 CPU=4 MEMORY=4096
```

### 3. Template workflow (fastest multi-instance)

Set up one template, then spin up instances instantly via APFS copy-on-write.
Each instance gets an independent disk (no extra space until it writes data).

```sh
# Step 1 — set up template once
make -f instance.mk setup INSTANCE=iphone_template JB=1

# Step 2 — create instances (~1 second each)
make -f instance.mk from_template TEMPLATE=iphone_template INSTANCE=iphone_01
make -f instance.mk from_template TEMPLATE=iphone_template INSTANCE=iphone_02

# Step 3 — boot one at a time
make -f instance.mk boot INSTANCE=iphone_01
```

> **Note:** All instances share the same ECID (`machineIdentifier.bin`). Do **not** run more than one simultaneously.

### 4. Clone an existing instance

Copies all boot-critical files. Skips the large IPSW restore folder.

```sh
make -f instance.mk clone INSTANCE=iphone_01 TARGET=iphone_backup
```

> The clone has the same ECID as the source. Do **not** run both at the same time.

### 5. SSH into a running instance

```sh
# Start tunnel (default local port 22222)
make -f instance.mk iproxy INSTANCE=iphone_01

# In another terminal
make -f instance.mk ssh INSTANCE=iphone_01
# or: ssh -p 22222 root@localhost

# See all running tunnels
make -f instance.mk iproxy_list
```

### 6. List instances

```sh
make -f instance.mk list
```

---

## Direct script usage

The scripts can also be called directly if you need more control.

### setup_instance.sh

Wrapper for `setup_machine.sh` that sets `VM_DIR` to the named instance.

```sh
zsh scripts/setup_instance.sh <instance-name> [--jb] [--dev] [--skip-project-setup]

# Examples
zsh scripts/setup_instance.sh iphone_01 --jb
zsh scripts/setup_instance.sh iphone_02

# Non-interactive (CI)
NONE_INTERACTIVE=1 SUDO_PASSWORD=mypass zsh scripts/setup_instance.sh iphone_01 --jb
```

### from_template.sh

Creates a new instance from a template using APFS copy-on-write (instant, zero extra space).

```sh
zsh scripts/from_template.sh <template-dir> <new-instance-dir>

# Examples
zsh scripts/from_template.sh iphone_template iphone_01
zsh scripts/from_template.sh iphone_template iphone_02
```

Falls back to `rsync --sparse` if not on APFS.

### clone_instance.sh

Copies an existing instance to a new directory. Skips the IPSW restore folder.

```sh
zsh scripts/clone_instance.sh <source> <destination>

# Examples
zsh scripts/clone_instance.sh iphone_01 iphone_03
zsh scripts/clone_instance.sh vm iphone_backup
```

Uses APFS copy-on-write for `Disk.img` when available; falls back to `rsync`.

### list_iproxy.sh

Shows all running `iproxy` tunnels and maps them to instance names via `udid-prediction.txt`.

```sh
zsh scripts/list_iproxy.sh
```

Output:

```
  PID       LOCAL   REMOTE  UDID                                      INSTANCE
  --------  ------  ------  ----------------------------------------  --------
  12345     22222   22      00008110-...                               iphone_01
```

---

## Key constraints

- **One instance at a time** — instances cloned or created from the same template share a `machineIdentifier.bin` (ECID). Running two simultaneously causes identity conflicts.
- **Independent disks** — after `from_template` or `clone_instance`, each instance's disk is fully isolated. Writes to one do not affect the other.
- **IPSW folder not copied** — `clone_instance.sh` and `from_template.sh` skip the large `iPhone*_Restore` folder. Copy it manually if you need to re-restore a clone.
