# Changelog

All notable changes to this project will be documented in this file.

## [unreleased]

### ⚙️ Miscellaneous Tasks

- *(ci)* Fix git-cliff tagging

## [2025.06.0] - 2025-07-01

### 🚀 Features

- *(build)* Use clang and lld as default compilers
- *(dev)* Add Clang/LLD build configuration
- *(shell)* Add Git configuration setup function
- *(shell)* Setup Git configuration
- *(shell)* Improve user interaction with interactive prompts
- *(shell)* Update Git configuration setup
- Add unzip, uv utilities, and new shell function
- *(git-hooks)* Add commit message validation
- Add git utilities
- *(config)* Add git-cliff configuration
- *(hooks)* Initialize changelog with git-cliff configuration

### 🐛 Bug Fixes

- *(shell)* Secure password input for Git credentials

### ⚙️ Miscellaneous Tasks

- Update lock files and dependency configurations

## [2025.05.0] - 2025-05-30

### 🚀 Features

- Update NixOS configuration with firewall rules and user settings
- *(config)* Clear default disk identifiers
- *(shell)* Add secrets configuration variables
- *(partitioning)* Add encrypted SECRETS and DATA partitions
- *(shell)* Improve encrypted /boot and EFI mounting process
- *(nixos)* Add new configuration options with boot-options module
- Add new file
- *(shell)* Setup basic development environment
- *(git)* Add GitHub credential setup
- *(bootstrap)* Add tree package

### 🐛 Bug Fixes

- *(shell)* Adjust fortune command ordering
- *(config)* Remove placeholder values from flake.nix
- *(security)* Remove secret detection and scrubbing functionality
- Remove deprecated extra.nix references

### ⚙️ Miscellaneous Tasks

- *(build)* Modify nixos_commit checks
- Remove pre-push hook file
- *(hooks)* Remove install_hooks.sh
- Make bootstrap script executable

## [2025.03.0] - 2025-03-31

### 🚀 Features

- Add F2FS file system configuration
- *(config)* Update configuration files with hardware-specific details
- *(shell)* Add hardened Linux kernel build configuration
- *(hardware)* Update hardware configuration and filesystem definitions
- *(crypto)* Improve LUKS encryption setup using ESSIV mode
- *(configuration)* Organize kernel modules in initrd
- *(filesystem)* Add f2fs support
- *(build)* Add module symlink creation
- *(kernel)* Add additional module support
- *(kernel)* Enable Secure Boot support
- *(kernel)* Update module signing configuration
- *(infrastructure)* Add MOK certificates and update signing process
- *(wireless)* Enable rtl8814au wireless driver
- *(hardware)* Enable GPU firmware support and hardware features
- *(config)* Remove hardcoded disk identifiers from placeholders
- *(hooks)* Add pre-push Git hook for automated security checks
- *(shell)* Add fish shell configuration files
- *(shell)* Add vendor_functions.d support

### 🐛 Bug Fixes

- *(configuration)* Replace hardcoded paths with placeholder variables
- *(config)* Remove on-the-go NVIDIA configurations
- Remove outdated Python extension and add remote-ssh-edit
- *(nvidia)* Update NVIDIA package version and rebuild command
- *(nix)* Remove --impure flag from nix eval commands
- Remove olddefconfig from kernel build commands
- *(config)* Enable DM Snapshot support and update kernel configuration
- Remove deprecated dependencies and configurations
- *(configuration)* Update rtl8814au package configuration
- *(shell)* Improve commit function security and error handling

### 🚜 Refactor

- *(nix)* Correct NixOS configuration variable expansion

### ⚙️ Miscellaneous Tasks

- Update nixpkgs dependencies
- *(config)* Update security configurations and dependencies
- *(configuration)* Update kernel module configuration and certificate paths
- Update dependencies and enable rtl8814au module

## [2025.02.0] - 2025-02-28

### 🐛 Bug Fixes

- *(config)* Replace disk UUIDs with placeholder variables
- *(setup)* Update OpenSSL installation with experimental features
- *(setup)* Improve LVM mount validation and waiting logic
- *(setup)* Improve LVM creation and mounting process

## [2024.12.0] - 2024-12-20

### 🚀 Features

- *(hardware)* Add hardware configuration and new packages
- *(boot)* Ensure script commands run in /etc/nixos directory context
- *(package)* Add psmisc

### 🐛 Bug Fixes

- *(dependencies)* Update package dependencies

## [2024.11.0] - 2024-11-25

### 🚀 Features

- *(system)* Add new system features and configurations
- *(configuration)* Update kernel settings and add packages

### 🐛 Bug Fixes

- *(nvidia)* Reconfigure prime settings for optimal performance

## [2024.10.0] - 2024-10-10

### 🚀 Features

- *(configuration)* Enable NVIDIA proprietary drivers and update system configuration

## [2024.07.0] - 2024-07-21

### 🚀 Features

- *(configuration)* Add several new packages

## [2024.05.0] - 2024-05-29

### 📚 Documentation

- Update README description

## [2024.04.0] - 2024-04-06

### 🚀 Features

- Add flake.lock
- *(dependencies)* Add tree-sitter dependency

### 🐛 Bug Fixes

- Replace bwrap with exec bwrap

### ⚙️ Miscellaneous Tasks

- Remove deprecated shell.nix and update NIX configuration

## [2024.03.0] - 2024-03-30

### 🚀 Features

- *(configuration)* Add packages and enhance shell environment
- Add Rust toolchain and Nix shell environment setup
- Add git config and credentials bindings
- *(shell)* Add bwrap sandboxing
- *(shell)* Improve shell environment with enhanced security features
- *(shell)* Add development tools and improve environment setup

### 📚 Documentation

- Add documentation files

<!-- generated by git-cliff -->
