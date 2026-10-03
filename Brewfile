# Brewfile — every machine. Layers: Brewfile.dev (build machines), Brewfile.server (headless).
# Install: brew bundle --file Brewfile   ·   Check: brew bundle check --file Brewfile
# Anything installed beyond these layers goes in docs/machines/<host>.md, or map-check reports drift.
# Sections say who a tool is for: the setup, Claude, or you at the terminal.

tap "domt4/autoupdate"                  # `brew autoupdate start 86400 --upgrade --cleanup`

# --- Needed by the setup itself ---------------------------------------------
brew "gh"
brew "bitwarden-cli"                    # `bw` — the only secret store
brew "gitleaks"                         # pre-commit secret scan
brew "rclone"                           # R2: archive, camera cold copy, resources (crypt)
brew "mas"                              # Mac App Store CLI
brew "jq"                               # every hook parses its input with it
brew "coreutils"                        # gtimeout, used by the session-start and stop hooks

# --- Claude uses these from its shell ---------------------------------------
brew "ripgrep"                          # text search; dotfiles/ripgreprc caps line length
brew "fd"                               # files by name; reads .gitignore and .ignore
brew "ast-grep"                         # structural code search: matches syntax, not text
brew "yq"                               # jq for YAML
brew "shellcheck"                       # lint for every bash script, including Claude's
brew "just"                             # one name per project task: `just --list`
brew "tree"                             # a directory's layout in one call

# --- Runtimes: one version manager ------------------------------------------
brew "mise"                             # Python + Node versions
brew "uv"                               # Python packages and scripts
brew "pnpm"                             # JS packages

# --- For you at the terminal — Claude doesn't use these ---------------------
brew "starship"                         # prompt
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf"                              # fuzzy finder
brew "zoxide"                           # `z <dir>`; never aliased over cd
brew "direnv"                           # loads a project's .envrc when you cd in
brew "lazygit"                          # `lg`
brew "bat"                              # cat with highlighting; never aliased over cat
brew "eza"                              # `ll`; never aliased over ls
brew "git-delta"                        # git's pager in dotfiles/gitconfig; plain when piped
brew "tlrc"                             # tldr client

# --- Ops --------------------------------------------------------------------
brew "btop"
brew "tmux"
brew "watch"
brew "nmap"
brew "mtr"
brew "wget"

# --- Media and documents ----------------------------------------------------
brew "ffmpeg"
brew "imagemagick"
brew "pandoc"
brew "poppler"
brew "exiftool"
brew "ocrmypdf"

# --- Optional: encryption — nothing in the setup uses these yet -------------
brew "age"                              # file encryption
brew "sops"                             # encrypted config files

# --- Apps -------------------------------------------------------------------
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
cask "font-jetbrains-mono-nerd-font"
cask "qlmarkdown"                       # Quick Look: markdown
cask "syntax-highlight"                 # Quick Look: source code
