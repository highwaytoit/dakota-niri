kind: script

# Override of gnome-build-meta.bst:oci/initramfs.bst (GNOME 50.4).
#
# Identical to upstream except for the first command: freedesktop-sdk 25.08.16
# pins shadow 4.20.0, which no longer builds the expiry utility, while its
# shadow initial-script still chmods it. prepare-image.sh then aborts with
# "chmod: cannot access '/usr/bin/expiry': No such file or directory" and this
# element fails whenever it is built rather than pulled from a cache.
#
# The fix is applied to the collected script inside this sandbox instead of to
# components/shadow.bst, because patching the freedesktop-sdk junction changes
# the cache key of every element derived from it and forces a full SDK rebuild.
# Drop this override once freedesktop-sdk drops expiry from that loop.

build-depends:
- gnome-build-meta.bst:gnomeos/generate-initramfs.bst
- gnome-build-meta.bst:oci/initramfs/deps.bst
- gnome-build-meta.bst:oci/initramfs/initial-scripts.bst
- freedesktop-sdk.bst:components/fakecap.bst
- freedesktop-sdk.bst:vm/prepare-image.bst

variables:
  sysroot-seed: 9473a621-1617-4679-87e5-031afef28359

environment:
  LD_PRELOAD: /usr/libexec/fakecap/fakecap.so
  FAKECAP_DB: /fakecap
  ZSTDFLAGS: -T%{max-jobs}
  DLOPEN_NOTE_IGNORE: archive:fido2:qrencode:ip4tc
  INITRD_MODE: oci

environment-nocache:
- ZSTDFLAGS

config:
  commands:
  - mkdir -p /fakecap
  - |
    # Assert the stale entry is present, then remove only it. `chage` stays:
    # shadow 4.20.0 still installs it and it still needs mode 4755.
    _hook=/etc/fdsdk/initial_scripts/003-components_shadow_bst
    if ! grep -q 'for i in expiry chage; do' "${_hook}"; then
      echo "ERROR: ${_hook} no longer chmods expiry - drop this override" >&2
      exit 1
    fi
    sed -i 's/^\(\s*\)for i in expiry chage; do$/\1for i in chage; do/' "${_hook}"
    grep -q 'for i in chage; do' "${_hook}"
  - |
    prepare-image.sh \
       --seed "%{sysroot-seed}" \
       --noroot --noboot >/dev/null

  - |
    version="$(ls -1 /lib/modules | head -n1)"
    generate-initramfs /initramfs-root "${version}" "%{libdir}" "%{libdir}/systemd"

  - |
    (
      cd /initramfs-root
      find . -print0 | sort -z | cpio --reproducible --null -H newc -o --quiet | zstd ${ZSTDFLAGS} >/initramfs.img
    )

  - |
    case '%{arch}' in
      x86_64)
        mkdir -p /microcode/kernel/x86/microcode
        cat /usr/lib/firmware/amd-ucode/microcode_amd*.bin >/microcode/kernel/x86/microcode/AuthenticAMD.bin
        cp /usr/lib/firmware/intel-ucode/GenuineIntel.bin /microcode/kernel/x86/microcode/GenuineIntel.bin
        (
          cd /microcode
          find . -print0 | sort -z | cpio --reproducible --null -H newc -o --quiet >/microcode.img
        )
      ;;
    esac

  - |
    version="$(ls -1 /lib/modules | head -n1)"
    mkdir -p "%{install-root}/usr/lib/modules/${version}"
    initrds=()
    case '%{arch}' in
      x86_64)
        initrds+=(/microcode.img)
        ;;
    esac
    initrds+=(/initramfs.img)
    cat "${initrds[@]}" >"%{install-root}/usr/lib/modules/${version}/initramfs.img"
