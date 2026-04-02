#!/usr/bin/env bash
# arch-setup.sh — Post-install setup: yay, fish shell, audio stack
# Run as your normal user (script will sudo when needed)
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; RST='\033[0m'

info()    { echo -e "${BLU}[INFO]${RST}  $*"; }
success() { echo -e "${GRN}[OK]${RST}    $*"; }
warn()    { echo -e "${YLW}[WARN]${RST}  $*"; }
section() { echo -e "\n${CYN}══════════════════════════════════════════${RST}"; \
            echo -e "${CYN}  $*${RST}"; \
            echo -e "${CYN}══════════════════════════════════════════${RST}"; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
    echo -e "${RED}[ERR]${RST}  Don't run this as root. Use your normal user account."
    exit 1
fi

# ── 1. yay (AUR helper) ───────────────────────────────────────────────────────
section "1/3  Installing yay"

if command -v yay &>/dev/null; then
    success "yay is already installed — skipping"
else
    info "Installing base-devel and git..."
    sudo pacman -S --needed --noconfirm base-devel git

    info "Cloning yay from AUR..."
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay"
    pushd "$TMPDIR/yay" > /dev/null
    makepkg -si --noconfirm
    popd > /dev/null
    rm -rf "$TMPDIR"
    success "yay installed"
fi

# ── 2. Fish shell ─────────────────────────────────────────────────────────────
section "2/3  Installing fish and setting as default shell"

if ! pacman -Qi fish &>/dev/null; then
    info "Installing fish..."
    sudo pacman -S --needed --noconfirm fish
fi

# Add fish to /etc/shells if not already there
if ! grep -qx "$(command -v fish)" /etc/shells; then
    info "Registering fish in /etc/shells..."
    command -v fish | sudo tee -a /etc/shells > /dev/null
fi

# Set fish as default for the current user
CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
FISH_PATH=$(command -v fish)

if [[ "$CURRENT_SHELL" == "$FISH_PATH" ]]; then
    success "fish is already your default shell"
else
    info "Setting fish as default shell for $USER..."
    chsh -s "$FISH_PATH"
    success "Default shell → fish (takes effect on next login)"
fi

# Set fish as default for new users going forward
info "Setting fish as default shell for new users in /etc/default/useradd..."
sudo sed -i "s|^SHELL=.*|SHELL=$FISH_PATH|" /etc/default/useradd 2>/dev/null \
    || echo "SHELL=$FISH_PATH" | sudo tee -a /etc/default/useradd > /dev/null
success "New users will default to fish"

# ── 3. Audio stack ────────────────────────────────────────────────────────────
section "3/3  Installing audio packages"

# ── Core audio (pipewire + wireplumber) ──────────────────────────────────────
AUDIO_CORE=(
    pipewire          # Core daemon
    pipewire-audio    # Base audio support
    pipewire-alsa     # ALSA replacement shim
    pipewire-pulse    # PulseAudio replacement shim
    pipewire-jack     # JACK replacement shim
    wireplumber       # Session/policy manager
    libpipewire       # Client library
    libwireplumber    # WirePlumber client lib
    libpulse          # PulseAudio compat lib (apps link against this)
)

# ── ALSA userspace ────────────────────────────────────────────────────────────
AUDIO_ALSA=(
    alsa-lib          # ALSA library
    alsa-utils        # aplay, arecord, alsamixer
    alsa-plugins      # Rate conversion, format plugins
    alsa-firmware     # Firmware for some ALSA drivers
    alsa-card-profiles  # PipeWire card profile data
    alsa-topology-conf  # ALSA topology config files
    alsa-ucm-conf     # UCM (Use Case Manager) configs — needed for your Chromebook's DA7219
)

# ── Firmware ──────────────────────────────────────────────────────────────────
# NOTE: EndeavourOS ships split linux-firmware-* packages; vanilla Arch uses
# one combined linux-firmware. sof-firmware is separate and needed for your
# Chromebook's Intel AVS / SOF audio DSP.
AUDIO_FIRMWARE=(
    linux-firmware
    sof-firmware
)

# ── Misc audio libs ───────────────────────────────────────────────────────────
AUDIO_LIBS=(
    libmysofa           # HRTF/spatial audio (used by PipeWire)
    webrtc-audio-processing-1  # Echo cancellation / noise reduction
    portaudio           # Cross-platform audio I/O lib
    soundtouch          # Pitch/tempo shifting lib
    gst-plugin-pipewire # GStreamer → PipeWire bridge
)

# ── UI / cosmetic (sound themes) ─────────────────────────────────────────────
AUDIO_THEMES=(
    sound-theme-freedesktop   # Standard XDG event sounds
    media-player-info         # udev rules for USB media players
)

# ── KDE/Qt-specific (only needed if running KDE Plasma) ──────────────────────
AUDIO_KDE=(
    kcodecs             # KDE codec abstraction
    kpipewire           # KDE PipeWire integration (screen share audio etc.)
    pulseaudio-qt       # Qt PulseAudio bindings (used by KDE volume applet)
    qt6-multimedia      # Qt6 multimedia framework
    qt6-multimedia-ffmpeg  # FFmpeg backend for Qt6 multimedia
    ocean-sound-theme   # KDE Ocean sound theme
)

# ── Install core + ALSA + firmware + libs + themes ───────────────────────────
ALL_PACKAGES=(
    "${AUDIO_CORE[@]}"
    "${AUDIO_ALSA[@]}"
    "${AUDIO_FIRMWARE[@]}"
    "${AUDIO_LIBS[@]}"
    "${AUDIO_THEMES[@]}"
)

info "Installing core audio stack (${#ALL_PACKAGES[@]} packages)..."
sudo pacman -S --needed --noconfirm "${ALL_PACKAGES[@]}"
success "Core audio stack installed"

# ── KDE packages (optional prompt) ───────────────────────────────────────────
echo ""
read -rp "$(echo -e "${YLW}[PROMPT]${RST} Install KDE/Qt audio packages? (only needed for Plasma) [y/N]: ")" INSTALL_KDE
if [[ "${INSTALL_KDE,,}" == "y" ]]; then
    info "Installing KDE audio packages..."
    sudo pacman -S --needed --noconfirm "${AUDIO_KDE[@]}"
    success "KDE audio packages installed"
else
    info "Skipping KDE audio packages"
fi

# ── Enable WirePlumber as the session manager ─────────────────────────────────
info "Enabling PipeWire services for $USER..."
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
    || warn "Could not enable PipeWire services now — run this after first login if needed"

# ── Done ──────────────────────────────────────────────────────────────────────
section "Setup complete"
echo -e "  ${GRN}✔${RST}  yay is ready"
echo -e "  ${GRN}✔${RST}  fish set as default shell for ${USER} (re-login to apply)"
echo -e "  ${GRN}✔${RST}  Audio stack installed"
echo ""
warn "Rebooting to apply changes..."
systemctl reboot
