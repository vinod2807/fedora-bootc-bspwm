#!/usr/bin/env bash
# Runs once, on first boot of the installed system (ConditionFirstBoot=yes).
set -euo pipefail

USER="${FIRSTBOOT_USER:-vinod}"
HOME="/var/home/$USER"

# --- printer queues ---------------------------------------------------------
systemctl start cups 2>/dev/null || true
sleep 2
/usr/local/sbin/printers.sh || echo "WARN: printer setup needs attention"

# --- dotfiles (optional; private repo, needs network + creds) --------------
if [ ! -d "$HOME/.config" ] || [ -z "$(ls -A "$HOME/.config" 2>/dev/null)" ]; then
  if sudo -u "$USER" git clone --depth 1 \
      https://github.com/vinod2807/dotfiles-backup "$HOME/dotfiles-backup" 2>/dev/null; then
    cp -a "$HOME/dotfiles-backup/configs/.config/." "$HOME/.config/" 2>/dev/null || true
    cp -a "$HOME/dotfiles-backup/scripts/.local/."  "$HOME/.local/"  2>/dev/null || true
    cp -a "$HOME/dotfiles-backup/bin/."             "$HOME/bin"      2>/dev/null || true
    chown -R "$USER:$USER" "$HOME/.config" "$HOME/.local" "$HOME/bin"
  else
    echo "NOTE: dotfiles-backup not cloned (private repo). Apply manually."
  fi
fi

# --- enable user services (mirrors user-services-enabled.txt) -------------
USERSV="dbus-broker.service syncthing.service wireplumber.service \
xdg-user-dirs.service pipewire-pulse.socket pipewire.socket \
grub-boot-success.timer systemd-tmpfiles-clean.timer"
mkdir -p "$HOME/.config/systemd/user/default.target.wants"
for s in $USERSV; do
  src=""
  for d in /usr/lib/systemd/user /usr/share/systemd/user /etc/systemd/user; do
    [ -e "$d/$s" ] && src="$d/$s" && break
  done
  if [ -n "$src" ]; then
    ln -sf "$src" "$HOME/.config/systemd/user/default.target.wants/$s"
  fi
done
chown -R "$USER:$USER" "$HOME/.config/systemd"

# --- flatpak GUI apps (installed post-login, not in the image) ------------
# Runs in the background so first login is not blocked on large downloads.
if command -v flatpak >/dev/null 2>&1; then
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
  setsid bash -c \
    "sudo -u $USER flatpak install -y flathub org.mozilla.firefox >/var/log/firstboot-flatpak.log 2>&1 \
     && sudo -u $USER flatpak install -y flathub org.libreoffice.LibreOffice >>/var/log/firstboot-flatpak.log 2>&1" &
  echo "flatpak app install started in background (see /var/log/firstboot-flatpak.log)"
fi

echo "firstboot complete"
