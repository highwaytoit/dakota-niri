kind: manual

sources:
- kind: local
  path: files/countme

build-depends:
- core/sandbox-tools.bst
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  # Upstream Fedora reporting. Additive and unchanged: the first-party service
  # does not replace it.
  #
  # Named dakota-countme, not bluefin-countme: the shared first-party reporter
  # that common installs into system_files/shared owns that name now, and two
  # units cannot claim it.
  - install -Dm644 dakota-countme.{service,timer} -t "%{install-root}/usr/lib/systemd/system/"
  - install -Dm755 dakota-countme "%{install-root}/usr/libexec/dakota-countme"
  - mkdir -p "%{install-root}/usr/lib/systemd/system/timers.target.wants/"
  - ln -sf ../dakota-countme.timer "%{install-root}/usr/lib/systemd/system/timers.target.wants/dakota-countme.timer"

  # First-party reporting to countme.projectbluefin.io. The unit and its helper
  # come from projectbluefin/common via bluefin/common.bst, which copies
  # system_files/shared/usr wholesale — the same files every other image gets.
  # Only the enablement symlink is added here, because this image applies
  # timers.target.wants directly rather than running systemctl preset.
  - ln -sf ../bluefin-countme.timer "%{install-root}/usr/lib/systemd/system/timers.target.wants/bluefin-countme.timer"

depends:
- bluefin/common.bst
