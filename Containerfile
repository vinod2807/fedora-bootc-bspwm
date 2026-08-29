# Fedora 44 bootc image — bspwm desktop, legacy BIOS, ext4
# Built to mirror the running machine captured in fedora-bootstrap.
ARG FEDORA=44
FROM quay.io/fedora/fedora-bootc:${FEDORA}

# Default username; consumed by firstboot (the account itself is created
# below via useradd, since config.toml user creation only applies to disk images).
ARG USERNAME=vinod
ENV FIRSTBOOT_USER=${USERNAME}

# --- base tooling ----------------------------------------------------------
RUN dnf -y install git rsync && dnf clean all

# --- third-party repos + GPG keys -----------------------------------------
# brave/copr/onlyoffice repos are copied verbatim (they use https gpgkeys,
# auto-fetched). rpmfusion + terra ship their keys via release packages, so
# install those to provide both repo files and GPG keys.
COPY src/machine/repos/ /etc/yum.repos.d/
RUN rm -f /etc/yum.repos.d/rpmfusion-*.repo
RUN mkdir -p /etc/pki/rpm-gpg \
 && cp -v /etc/yum.repos.d/RPM-GPG-KEY-* /etc/pki/rpm-gpg/ 2>/dev/null || true \
 && dnf -y install \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm \
      distribution-gpg-keys \
 && dnf clean all && dnf -q makecache

# --- full package set (mirrors this PC) ------------------------------------
COPY src/machine/packages-full.txt /tmp/packages-full.txt
RUN xargs -a /tmp/packages-full.txt dnf -y install --skip-unavailable && dnf clean all

# --- flatpak + flathub (heavy GUI apps are installed post-login, NOT baked ---
# into the image, to keep the bootc image small). See bootc-firstboot.sh.
RUN dnf -y install flatpak && dnf clean all \
 && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

# --- legacy BIOS boot support (grub2-pc) ----------------------------------
# ostree-grub2 provides /etc/grub.d/15_ostree so `grub2-mkconfig` (run by
# bootc on upgrade) auto-tracks the bootc default/rollback deployment.
# os-prober keeps Ubuntu/Arch/Windows in the menu; enable it explicitly.
RUN dnf -y install grub2-pc grub2-pc-modules grub2-tools ostree-grub2 os-prober && dnf clean all
RUN (grep -q '^GRUB_DISABLE_OS_PROBER' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub)

# --- /etc configs (keyboard, lightdm, custom units) ------------------------
COPY src/machine/etc/ /etc/

# --- default user (vinod) -------------------------------------------------
# NOTE: config.toml's customizations.user only applies when bootc-image-builder
# builds a *disk* image. The container image used by `bootc install to-filesystem`
# must create the account itself, or lightdm's autologin-user has no account to
# log in as. So we create it here (password baked; change after first login).
ARG USER_PASS=mastermind
RUN useradd -m -G wheel -s /bin/bash vinod \
 && echo "vinod:${USER_PASS}" | chpasswd

# --- /usr/local/bin scripts ------------------------------------------------
RUN install -m 0755 /dev/null /usr/local/bin/.keep || true
COPY src/machine/usr-local-bin/ /usr/local/bin/
RUN chmod 0755 /usr/local/bin/*.sh 2>/dev/null || true

# --- /opt apps (drop tarballs into src/machine/opt/ before build) ---------
COPY src/machine/opt/ /src/opt/
RUN for t in /src/opt/*.tar.gz; do [ -e "$t" ] && tar -C / -xzf "$t" || true; done

# --- printer PPDs + queue script ------------------------------------------
COPY src/machine/printers/ /usr/share/bootc-printers/
COPY src/machine/printers.sh /usr/local/sbin/printers.sh
RUN chmod 0755 /usr/local/sbin/printers.sh

# --- enable services (verbatim from this PC) ------------------------------
COPY src/machine/services-enabled.txt /tmp/services-enabled.txt
RUN while read -r s; do systemctl enable "$s" 2>/dev/null || true; done < /tmp/services-enabled.txt \
 && systemctl enable lightdm 2>/dev/null || true \
 && systemctl set-default graphical.target

# --- firstboot + weekly upgrade -------------------------------------------
COPY src/firstboot/bootc-firstboot.service /usr/lib/systemd/system/
COPY src/firstboot/bootc-firstboot.sh /usr/local/sbin/bootc-firstboot.sh
RUN chmod 0755 /usr/local/sbin/bootc-firstboot.sh \
 && systemctl enable bootc-firstboot.service

COPY src/upgrade/bootc-upgrade.service /usr/lib/systemd/system/
COPY src/upgrade/bootc-upgrade.timer /usr/lib/systemd/system/
RUN systemctl enable bootc-upgrade.timer
