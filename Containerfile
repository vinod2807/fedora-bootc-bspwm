# Fedora 44 bootc image — bspwm desktop, legacy BIOS, ext4
# Built to mirror the running machine captured in fedora-bootstrap.
ARG FEDORA=44
FROM quay.io/fedora/fedora-bootc:${FEDORA}

# Default user created by bootc-image-builder (config.toml). Used by firstboot.
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

# --- legacy BIOS boot support (grub2-pc) ----------------------------------
RUN dnf -y install grub2-pc grub2-pc-modules && dnf clean all

# --- /etc configs (keyboard, lightdm, custom units) ------------------------
COPY src/machine/etc/ /etc/

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
