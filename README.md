# nixos

### Features

- **Automated Installation**  
  Includes a bare-metal install script that gets you from “blank disk” to a
  fully working, encrypted NixOS install—no handholding required.
- **Full `flake.nix` Build**  
  Designed for robust, reproducible builds using Nix flakes. Every config
  change, every secret, every package—versioned and traceable.
- **Security-First Defaults**  
  Disk encryption (LUKS/ESSIV), secure-boot, and opinionated firewall rules are
  not “add-ons.” They’re built in.
- **Rust-Ready Dev Environment**  
  Comes with a fully set up, sandboxed Rust toolchain using Clang+LLD and
  advanced shell functions. It’s not just for Rust, but it’s definitely for
  Rust.
- **Extensive Scripting**  
  Tons of supporting shell and fish functions for system setup, secrets
  management, bootstrapping, Git/GitHub integration, and more.
- **Changelog & Commit Hygiene**  
  Enforces structured commit messages and maintains a real changelog using
  [git-cliff](https://github.com/orhun/git-cliff).

### Quick Start

1. **Clone the repo**
   ```sh
   git clone https://github.com/daveman1010221/nixos.git
   cd nixos
   ```

2. **Read the install.sh and configuration.nix for details.**
- Customize hardware variables as needed.
- Optionally, review or extend the flake for custom modules or overlays.

3. **Run the installer (be careful, it wipes disks!)**
   ```sh
   ./install.sh
   ```
4. **Profit.**

### Changelog
See CHANGELOG.md for an actual, human-readable history.

### Forking & Contributions
- Fork it if you want to use/modify.
- PRs welcome, but don’t break the build or the security assumptions unless you have a damn good reason.
