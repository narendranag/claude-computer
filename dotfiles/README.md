# dotfiles

Linked by `/setup`. Existing files are moved to `<name>.backup-<date>` first.

| File here          | Linked to                                                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| `zshrc`            | `~/.zshrc`                                                                                                            |
| `starship.toml`    | `~/.config/starship.toml`                                                                                             |
| `ghostty.config`   | `~/.config/ghostty/config.ghostty` (current name; plain `config` still loads)                                         |
| `gitconfig`        | `~/.gitconfig` — **copied** in `/setup` phase 0, not linked: `{{git_name}}` and `{{git_email}}` are filled with yours |
| `gitignore_global` | `~/.gitignore_global` (the `excludesfile` in `gitconfig`)                                                             |
| `editorconfig`     | `~/.editorconfig`                                                                                                     |

Machine-specific shell settings go in `~/.zshrc.local`, which `zshrc` sources and which is never committed.
