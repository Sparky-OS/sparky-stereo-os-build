#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# recording hooks in every directory linux-run-hooks and the old run-parts loops use
for d in preinst postinst prerm postrm header_postinst; do
    mkdir -p /etc/kernel/$d.d
    cat > /etc/kernel/$d.d/00-record <<EOT
#!/bin/sh
echo "$d | \$(basename \$0) | args: \$* | DEB_MAINT_PARAMS=\${DEB_MAINT_PARAMS:-unset} | INITRD=\${INITRD:-unset}" >> /var/log/kernel-hooks.log
exit 0
EOT
    chmod 755 /etc/kernel/$d.d/00-record
done
: > /var/log/kernel-hooks.log
