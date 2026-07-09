# iitd_tools

A collection of tools for IIT Delhi systems.

## Configuration

This project requires a configuration file before running.

### Setup

1. Copy the example configuration file:
   ```bash
   cp config.example.yaml config.yaml
   ```

2. Edit `config.yaml` and fill in the values for your environment:
   ```bash
   # Update database credentials, API keys, etc.
   nano config.yaml
   ```

3. (Optional) Set the `CONFIG_PATH` environment variable to point to a custom
   config file location:
   ```bash
   export CONFIG_PATH=/path/to/your/config.yaml
   ```

### Loading Configuration in Python

```python
from config import load_config, get_config

# Load once at startup
load_config()          # reads config.yaml by default
# or specify a path:
load_config("path/to/config.yaml")

# Access the config anywhere in the codebase
cfg = get_config()
db_host = cfg["database"]["host"]
```

> **Note:** `config.yaml` is listed in `.gitignore` to prevent accidental
> commits of sensitive credentials. Always use `config.example.yaml` as the
> template and keep your local `config.yaml` private.