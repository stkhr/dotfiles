# dotfiles

## vscode

```bash
# listup
code --list-extensions > ./vscode/extensions

# install
xargs -n 1 code --install-extension < ./vscode/extensions
```
