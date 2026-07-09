"""Configuration loader for iitd_tools."""

import os
import yaml

_config = None
_DEFAULT_CONFIG_PATH = "config.yaml"


def load_config(path: str = None) -> dict:
    """Load configuration from a YAML file.

    Args:
        path: Path to the YAML config file. Defaults to config.yaml in the
              current directory, or the CONFIG_PATH environment variable.

    Returns:
        The loaded configuration as a dictionary.

    Raises:
        FileNotFoundError: If the config file does not exist.
    """
    global _config

    config_path = path or os.environ.get("CONFIG_PATH", _DEFAULT_CONFIG_PATH)

    if not os.path.exists(config_path):
        raise FileNotFoundError(
            f"Config file not found: {config_path}\n"
            "Copy config.example.yaml to config.yaml and update the values."
        )

    with open(config_path, "r") as f:
        _config = yaml.safe_load(f) or {}

    return _config


def get_config() -> dict:
    """Return the currently loaded configuration.

    Returns:
        The loaded configuration dictionary, or an empty dict if not loaded.
    """
    return _config or {}
