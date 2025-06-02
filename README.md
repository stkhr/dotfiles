# dotfiles

## vscode

```bash
# listup
code --list-extensions > ./vscode/extensions

# install
xargs -n 1 code --install-extension < ./vscode/extensions
```

### cursor に extension を同期する

```bash
xargs -n 1 cursor --install-extension < ./vscode/extensions
```
