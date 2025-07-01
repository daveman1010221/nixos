# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2025-07-01

### 🚀 Features

- *(configuration)* Add packages and enhance shell environment
- Add Rust toolchain and Nix shell environment setup
- Add git config and credentials bindings
- *(shell)* Add bwrap sandboxing
- *(shell)* Improve shell environment with enhanced security features
- *(shell)* Add development tools and improve environment setup
- Feat(shell): Enhance shell environment with new tools and improved SSL handling
- Add bat, eza, fd, figlet for enhanced CLI capabilities
- Introduce bwrap sandboxing for secure development
- Improve SSL certificate handling in the shell environment
- Feat(shell): Add bwrap sandboxing for secure development
- Adds bwrap integration for isolated shell environments
- Enhances security for fish shell development
- Add flake.lock
- Feat(shell): Add bwrap sandboxing
- Adds bwrap for isolated shell
- Enables secure fish development
- *(dependencies)* Add tree-sitter dependency
- *(configuration)* Add several new packages
- *(configuration)* Enable NVIDIA proprietary drivers and update system configuration
- Feat(neovim): Improve Neovim configuration and plugin setup
- Update Neovim configuration with enhanced settings
- Add new plugins for better development experience
- Configure treesitter for syntax highlighting
- Optimize key mappings and theme customization
- *(system)* Add new system features and configurations
- *(configuration)* Update kernel settings and add packages
- Feat(security): Add ClamAV configuration and enable services
- Enable ClamAV scanner, updater, and daemon
- Set up fangfrisch with Sanesecurity feed
- Configure file paths for antivirus scanning
- Feat(build): Update dependencies and restructure configuration
- Updates nixos-cosmic URL to specific branch
- Restructures overlay inputs for proper dependency resolution
- Adds explicit URLs for rust-overlay and myNeovimOverlay
- Improves configuration structure with let bindings
- Feat(shell): Add bwrap sandboxing
- Adds bwrap for isolated shell
- Enables secure fish development
- *(hardware)* Add hardware configuration and new packages
- *(boot)* Ensure script commands run in /etc/nixos directory context
- *(package)* Add psmisc
- Feat(system): Update packages and configuration
- Update System76 services for better hardware compatibility
- Improve network and Bluetooth configurations
- Enhance shell functionality with new commands and aliases
- Add improved man page navigation using bat
- Feat(system): Set up NixOS system configuration
- Generate initial config files
- Clone necessary repositories
- Update flake configuration with hardware details
- Install NixOS from the flake
- Add F2FS file system configuration
- Feat: Add new feature to the application
- Introduces a new core functionality
- Enhances user experience with key features
- *(config)* Update configuration files with hardware-specific details
- *(shell)* Add hardened Linux kernel build configuration
- *(hardware)* Update hardware configuration and filesystem definitions
- *(crypto)* Improve LUKS encryption setup using ESSIV mode
- *(configuration)* Organize kernel modules in initrd
- Feat(config): Move placeholder variables into secrets.nix
- Creates secrets.nix for secure configuration storage
- Updates flake.nix with new secrets management
- *(filesystem)* Add f2fs support
- Feat(crypto): Add AES-GCM support to crypto libraries
- Adds AES-GCM cryptographic algorithm support
- Enhances security with authenticated encryption capabilities
- *(build)* Add module symlink creation
- *(kernel)* Add additional module support
- *(kernel)* Enable Secure Boot support
- *(kernel)* Update module signing configuration
- Feat(docker/networking): Enhance Docker and networking configurations
- Adjusted Docker daemon settings
- Added Minikube iptables rules
- Optimized LVM readahead parameters
- *(infrastructure)* Add MOK certificates and update signing process
- *(wireless)* Enable rtl8814au wireless driver
- *(hardware)* Enable GPU firmware support and hardware features
- Feat(sys): Enable Containerd/Docker services and optimize system configuration  
- Enables Containerd and Docker for virtualization/containerization  
- Optimizes swapfile size for better memory management  
- Adjusts LVM read-ahead settings for improved performance  
- Implements additional system-wide optimizations
- *(config)* Remove hardcoded disk identifiers from placeholders
- *(hooks)* Add pre-push Git hook for automated security checks
- *(shell)* Add fish shell configuration files
- *(shell)* Add vendor_functions.d support
- Update NixOS configuration with firewall rules and user settings
- Feat(build-system): Add dotacatFast, remove cowsay based fish greeting
- Adds dotacatFast module in flake.nix
- Removes cowsay-based fish greeting
- Uses dotacat instead of lolcat
- Feat(flake): Update system configuration
- Add disk device paths and UUIDs
- Enable cachix and dnsmasq services
- Enhance security with additional keys and groups
- Improve kernel parameters
style(shell): Refine cowsay output handling
- Use printf for consistent argument processing
- *(config)* Clear default disk identifiers
- Feat(configuration): Add flake.nix configuration file
- Adds new flake.nix file as main NixOS Flake configuration
- Sets up input dependencies and output configurations
- Enables proper dependency resolution and module organization
- Feat(nixos): Setup NixOS automated installation pipeline
- Automates NixOS installation process
- Implements hardware configuration generation
- Updates flake.nix with system details
- Installs OS using specified hostname
- *(shell)* Add secrets configuration variables
- *(partitioning)* Add encrypted SECRETS and DATA partitions
- *(shell)* Improve encrypted /boot and EFI mounting process
- *(nixos)* Add new configuration options with boot-options module
- Add new file
- *(shell)* Setup basic development environment
- *(git)* Add GitHub credential setup
- *(bootstrap)* Add tree package
- *(build)* Use clang and lld as default compilers
- *(dev)* Add Clang/LLD build configuration
- *(shell)* Add Git configuration setup function
- *(shell)* Setup Git configuration
- *(shell)* Improve user interaction with interactive prompts
- *(shell)* Update Git configuration setup
- Add unzip, uv utilities, and new shell function
- Feat(packaging): Add new packages and configurations
- Adds comprehensive set of new software packages
- Includes Neovim configuration and plugins
- Updates shell themes and development tools
- *(git-hooks)* Add commit message validation
- Add git utilities
- *(config)* Add git-cliff configuration
- *(hooks)* Initialize changelog with git-cliff configuration

### 🐛 Bug Fixes

- Replace bwrap with exec bwrap
- *(nvidia)* Reconfigure prime settings for optimal performance
- *(dependencies)* Update package dependencies
- *(config)* Replace disk UUIDs with placeholder variables
- *(setup)* Update OpenSSL installation with experimental features
- *(setup)* Improve LVM mount validation and waiting logic
- *(setup)* Improve LVM creation and mounting process
- Fix(flake,setup): Replace device paths with UUID-based placeholders
- Replaces hardcoded device paths with UUID-based placeholders in flake.nix
- Updates encryption setup to use aes-xts-plain64 cipher
- *(configuration)* Replace hardcoded paths with placeholder variables
- *(config)* Remove on-the-go NVIDIA configurations
- Remove outdated Python extension and add remote-ssh-edit
- *(nvidia)* Update NVIDIA package version and rebuild command
- *(nix)* Remove --impure flag from nix eval commands
- Fix(kernel): Upgrade Linux kernel to 6.13
- Update hardened_linux_kernel to use 6.13
- Adjust kernel parameters for improved performance
- Add necessary security patches
- Remove olddefconfig from kernel build commands
- *(config)* Enable DM Snapshot support and update kernel configuration
- Fix(system): Enable WERROR in kernel, DRM, and KVM configuration
- Enabled CONFIG_WERROR in kernel for stricter compile-time checks
- Removed drm_werror_disabled to enforce warnings as errors in DRM
- Removed kvm_werror_disabled to enable strict compilation in KVM
- Updated nvidia module signing process with improved logging
- Remove deprecated dependencies and configurations
- *(configuration)* Update rtl8814au package configuration
- *(shell)* Improve commit function security and error handling
- *(shell)* Adjust fortune command ordering
- *(config)* Remove placeholder values from flake.nix
- Fix(system): Improve system initialization and reliability
- Remove docker container cleanup from startup
- Add systemctl controls for fwupd and expressvpn services
- Enhance error handling in device path retrieval
- Delete deprecated flake.nix configuration
- Improve overall system reliability and security
- *(security)* Remove secret detection and scrubbing functionality
- Remove deprecated extra.nix references
- *(shell)* Secure password input for Git credentials

### 💼 Other

- FIPS compliant kernel config for hardened nix kernel
- Making config handling more automated

### 🚜 Refactor

- *(nix)* Correct NixOS configuration variable expansion

### 📚 Documentation

- Add documentation files
- Update README description
- Regenerate changelog after removing v-prefixed tags

### ⚙️ Miscellaneous Tasks

- Chore(storage): Initialize encrypted storage with LUKS2 and RAID
- Sets up encrypted NVMe volumes using LUKS2
- Creates RAID0 array for improved performance
- Configures logical volumes for swap, tmp, var, root, and home
- Formats volumes without journal for optimal alignment
- Includes user creation and system configuration setup
- Remove deprecated shell.nix and update NIX configuration
- Update nixpkgs dependencies
- *(config)* Update security configurations and dependencies
- *(configuration)* Update kernel module configuration and certificate paths
- Update dependencies and enable rtl8814au module
- *(build)* Modify nixos_commit checks
- Remove pre-push hook file
- *(hooks)* Remove install_hooks.sh
- Chore(project-structure): Move config/kernel files to dedicated directory
- Migrate .config, MOK.pem, etc., to kernel/ for better organization
- Remove unused rust-toolchain.toml
- Improve file structure management
- Make bootstrap script executable
- Update lock files and dependency configurations
- *(ci)* Fix git-cliff tagging

<!-- generated by git-cliff -->
