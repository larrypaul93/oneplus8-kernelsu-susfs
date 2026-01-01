#!/bin/bash
# Add manual KernelSU hooks for non-GKI kernels
# This is required because kprobe doesn't work reliably on kernel 4.19

set -e

echo "Adding manual hooks for non-GKI kernel..."

# Hook 1: fs/exec.c - execveat hook for detecting su calls
echo "Patching fs/exec.c..."

# Add extern declarations after includes
cat > /tmp/exec_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern bool ksu_execveat_hook __read_mostly;
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
#endif
HOOKEOF
sed -i '/#include <linux\/fs_struct.h>/r /tmp/exec_hook.txt' fs/exec.c

# Add hook call after getname_flags - this is safe because it's after variable decls
sed -i '/getname_flags(filename, lookup_flags, NULL)/a\
#ifdef CONFIG_KSU\
	if (unlikely(ksu_execveat_hook))\
		ksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\
	else\
		ksu_handle_execveat_sucompat(\&fd, \&filename, \&argv, \&envp, \&flags);\
#endif
' fs/exec.c

# Hook 2: fs/open.c - faccessat hook
echo "Patching fs/open.c..."

cat > /tmp/open_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);
#endif
HOOKEOF
sed -i '/#include <linux\/rcupdate.h>/r /tmp/open_hook.txt' fs/open.c

# For do_faccessat - find the function and insert after the variable declarations
# Look for a statement line that starts the actual code
sed -i '/^static long do_faccessat/,/^}/{
  /res = user_path_at/i\
#ifdef CONFIG_KSU\
	ksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif
}' fs/open.c

# Hook 3: fs/read_write.c - vfs_read hook
echo "Patching fs/read_write.c..."

cat > /tmp/read_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern bool ksu_vfs_read_hook __read_mostly;
extern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr, size_t *count_ptr, loff_t **pos);
#endif
HOOKEOF
sed -i '/#include <linux\/compat.h>/r /tmp/read_hook.txt' fs/read_write.c

# For vfs_read - need to match ONLY within vfs_read function
# Use awk to be more precise about function boundaries
awk '
/^ssize_t vfs_read\(struct file \*file, char __user \*buf, size_t count, loff_t \*pos\)$/ {
    in_vfs_read = 1
    print
    next
}
in_vfs_read && /ssize_t ret;/ {
    print
    print "#ifdef CONFIG_KSU"
    print "\tif (unlikely(ksu_vfs_read_hook))"
    print "\t\tksu_handle_vfs_read(&file, &buf, &count, &pos);"
    print "#endif"
    in_vfs_read = 0
    next
}
{ print }
' fs/read_write.c > fs/read_write.c.tmp && mv fs/read_write.c.tmp fs/read_write.c

# Hook 4: fs/stat.c - stat hook
echo "Patching fs/stat.c..."

cat > /tmp/stat_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
#endif
HOOKEOF
sed -i '/#include <linux\/compat.h>/r /tmp/stat_hook.txt' fs/stat.c

# For vfs_statx - find the retry: label or the first actual statement
sed -i '/^int vfs_statx/,/^}/{
  /getname_flags/i\
#ifdef CONFIG_KSU\
	ksu_handle_stat(\&dfd, \&filename, \&flags);\
#endif
}' fs/stat.c

# Hook 5: drivers/input/input.c - input event hook for volume key detection
echo "Patching drivers/input/input.c..."

# Find a more reliable include to insert after
cat > /tmp/input_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern bool ksu_input_hook __read_mostly;
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);
#endif
HOOKEOF
# Try multiple possible includes
if grep -q '#include <linux/input.h>' drivers/input/input.c; then
  sed -i '/#include <linux\/input.h>/r /tmp/input_hook.txt' drivers/input/input.c
elif grep -q '#include "input-compat.h"' drivers/input/input.c; then
  sed -i '/#include "input-compat.h"/r /tmp/input_hook.txt' drivers/input/input.c
else
  # Fallback: add at end of includes
  sed -i '/^#define pr_fmt/a\
#ifdef CONFIG_KSU\
extern bool ksu_input_hook __read_mostly;\
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\
#endif
' drivers/input/input.c
fi

# For input_handle_event, insert after the variable declaration line
sed -i '/int disposition = input_get_disposition(dev, type, code, \&value);/a\
#ifdef CONFIG_KSU\
	if (unlikely(ksu_input_hook))\
		ksu_handle_input_handle_event(\&type, \&code, \&value);\
#endif
' drivers/input/input.c

echo "Manual hooks added successfully!"
