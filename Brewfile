# Brewfile — every machine. Layers: Brewfile.dev (build machines), Brewfile.server (headless).
# Install: brew bundle --file Brewfile   ·   Check: brew bundle check --file Brewfile
# Anything installed beyond these layers goes in docs/machines/<host>.md, or map-check reports drift.

tap "domt4/autoupdate"                 # `brew autoupdate start 86400 --upgrade --cleanup`

# --- Needed by the setup itself -----------------------------------------
brew "gh"
brew "bitwarden-cli"                    # `bw` — the only secret store
brew "gitleaks"                         # pre-commit secret scan
brew "rclone"                           # R2: archive, camera cold copy, resources (crypt)
brew "syncthing"                        # two-way folder sync between own machines
brew "mas"                              # Mac App Store CLI
brew "age"                              # optional: file encryption
brew "sops"                             # optional: encrypted config files

# --- Claude works better with these ----------------------------------------
brew "ripgrep"
brew "fd"
brew "ast-grep"                         # structural code search: matches syntax, not text
brew "fzf"
brew "jq"
brew "yq"
brew "bat"
brew "eza"
brew "tree"
brew "git-delta"
brew "shellcheck"
brew "tlrc"                             # tldr client
brew "just"
brew "coreutils"                        # gtimeout and friends, used by hooks

# --- Runtimes: one version manager ---------------------------------------
brew "mise"                             # Python + Node versions
brew "uv"                               # Python packages and scripts
brew "pnpm"                             # JS packages

# --- Shell -----------------------------------------------------------------
brew "starship"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "zoxide"
brew "direnv"
brew "lazygit"

# --- Ops -----------------------------------------------------------------
brew "btop"
brew "tmux"
brew "watch"
brew "nmap"
brew "mtr"
brew "wget"

# --- Media and documents ---------------------------------------------------
brew "ffmpeg"
brew "imagemagick"
brew "pandoc"
brew "poppler"
brew "exiftool"
brew "ocrmypdf"

# --- Apps --------------------------------------------------------------------
cask "claude-code"                      # installed in Phase 1; listed so rebuilds match
cask "ghostty"
cask "tailscale-app"
cask "bitwarden"
cask "google-chrome"
cask "visual-studio-code"
cask "obsidian"
cask "claude"
cask "telegram"
cask "iina"
cask "libreoffice"                      # headless document conversion as a build tool
cask "macparakeet" if Hardware::CPU.arm? # on-device dictation + transcription → vault inbox; Apple silicon, macOS 14+
cask "syncthing-app"
cask "font-jetbrains-mono-nerd-font"
cask "qlmarkdown"                       # Quick Look: markdown
cask "syntax-highlight"                 # Quick Look: source code
