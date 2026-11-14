---
name: Quickshell
description: Use when editing QML, shell surfaces, apps, services, live reload, quickshell logs or the shell design system.
---

- Run the shell from the repo: `quickshell -p shell/shell.qml`; never edit installed copies.
- Check `/run/user/1000/quickshell/by-id/<newest>/log.qslog` with `grep -a` on errors.
- Use the shell tokens in `shell/services/Config.qml`; keep the existing type and palette.
- Reusable UI belongs in `shell/ui/` and must be registered in `shell/ui/qmldir`.
