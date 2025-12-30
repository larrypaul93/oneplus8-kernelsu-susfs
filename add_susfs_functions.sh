#!/bin/bash
# Script to add SUSFS functions to KernelSU selinux.c
# This is needed when the SUSFS patch doesn't apply cleanly

SELINUX_C="$1"

if [ ! -f "$SELINUX_C" ]; then
    echo "ERROR: selinux.c not found at $SELINUX_C"
    exit 1
fi

# Check if SUSFS functions already exist
if grep -q "susfs_is_current_ksu_domain" "$SELINUX_C"; then
    echo "SUSFS functions already present in selinux.c"

    # Just add EXPORT_SYMBOL if missing
    if ! grep -q "EXPORT_SYMBOL(susfs_is_current_ksu_domain)" "$SELINUX_C"; then
        echo "Adding EXPORT_SYMBOL declarations..."
        cat >> "$SELINUX_C" << 'EOF'

/* SUSFS symbol exports for fs/susfs.c */
#ifdef CONFIG_KSU_SUSFS
EXPORT_SYMBOL(susfs_is_current_ksu_domain);
EXPORT_SYMBOL(susfs_is_current_zygote_domain);
EXPORT_SYMBOL(susfs_is_current_init_domain);
EXPORT_SYMBOL(susfs_is_sid_equal);
EXPORT_SYMBOL(susfs_set_ksu_sid);
EXPORT_SYMBOL(susfs_set_zygote_sid);
EXPORT_SYMBOL(susfs_set_init_sid);
EXPORT_SYMBOL(susfs_get_current_sid);
EXPORT_SYMBOL(susfs_get_sid_from_name);
#endif
EOF
    fi
    exit 0
fi

echo "SUSFS functions not found - adding manually..."

# Add SUSFS variable declarations after KERNEL_SU_DOMAIN
sed -i '/#define KERNEL_SU_DOMAIN/a \
\
#ifdef CONFIG_KSU_SUSFS\
#define KERNEL_INIT_DOMAIN "u:r:init:s0"\
#define KERNEL_ZYGOTE_DOMAIN "u:r:zygote:s0"\
u32 susfs_ksu_sid = 0;\
u32 susfs_init_sid = 0;\
u32 susfs_zygote_sid = 0;\
#endif' "$SELINUX_C"

# Add SUSFS functions at the end of the file
cat >> "$SELINUX_C" << 'EOF'

#ifdef CONFIG_KSU_SUSFS
static inline void susfs_set_sid(const char *secctx_name, u32 *out_sid)
{
	int err;
	if (!secctx_name || !out_sid) {
		pr_err("secctx_name || out_sid is NULL\n");
		return;
	}
	err = security_secctx_to_secid(secctx_name, strlen(secctx_name), out_sid);
	if (err) {
		pr_err("failed setting sid for '%s', err: %d\n", secctx_name, err);
		return;
	}
	pr_info("sid '%u' is set for secctx_name '%s'\n", *out_sid, secctx_name);
}

bool susfs_is_sid_equal(void *sec, u32 sid2) {
	struct task_security_struct *tsec = (struct task_security_struct *)sec;
	if (!tsec) return false;
	return tsec->sid == sid2;
}

u32 susfs_get_sid_from_name(const char *secctx_name)
{
	u32 out_sid = 0;
	int err;
	if (!secctx_name) {
		pr_err("secctx_name is NULL\n");
		return 0;
	}
	err = security_secctx_to_secid(secctx_name, strlen(secctx_name), &out_sid);
	if (err) {
		pr_err("failed getting sid from secctx_name: %s, err: %d\n", secctx_name, err);
		return 0;
	}
	return out_sid;
}

u32 susfs_get_current_sid(void) { return current_sid(); }

void susfs_set_zygote_sid(void) { susfs_set_sid(KERNEL_ZYGOTE_DOMAIN, &susfs_zygote_sid); }
bool susfs_is_current_zygote_domain(void) { return unlikely(current_sid() == susfs_zygote_sid); }

void susfs_set_ksu_sid(void) { susfs_set_sid(KERNEL_SU_DOMAIN, &susfs_ksu_sid); }
bool susfs_is_current_ksu_domain(void) { return unlikely(current_sid() == susfs_ksu_sid); }

void susfs_set_init_sid(void) { susfs_set_sid(KERNEL_INIT_DOMAIN, &susfs_init_sid); }
bool susfs_is_current_init_domain(void) { return unlikely(current_sid() == susfs_init_sid); }

/* SUSFS symbol exports for fs/susfs.c */
EXPORT_SYMBOL(susfs_is_current_ksu_domain);
EXPORT_SYMBOL(susfs_is_current_zygote_domain);
EXPORT_SYMBOL(susfs_is_current_init_domain);
EXPORT_SYMBOL(susfs_is_sid_equal);
EXPORT_SYMBOL(susfs_set_ksu_sid);
EXPORT_SYMBOL(susfs_set_zygote_sid);
EXPORT_SYMBOL(susfs_set_init_sid);
EXPORT_SYMBOL(susfs_get_current_sid);
EXPORT_SYMBOL(susfs_get_sid_from_name);
#endif
EOF

echo "Added SUSFS functions to selinux.c"
echo "=== selinux.c tail ==="
tail -25 "$SELINUX_C"
