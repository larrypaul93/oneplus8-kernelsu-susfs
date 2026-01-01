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

# Add hook call after getname_flags
cat > /tmp/exec_call.txt << 'HOOKEOF'
#ifdef CONFIG_KSU
	if (unlikely(ksu_execveat_hook))
		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
	else
		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);
#endif
HOOKEOF
sed -i '/getname_flags(filename, lookup_flags, NULL)/r /tmp/exec_call.txt' fs/exec.c

# Hook 2: fs/open.c - faccessat hook
echo "Patching fs/open.c..."

cat > /tmp/open_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);
#endif
HOOKEOF
sed -i '/#include <linux\/rcupdate.h>/r /tmp/open_hook.txt' fs/open.c

cat > /tmp/open_call.txt << 'HOOKEOF'
#ifdef CONFIG_KSU
	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
#endif
HOOKEOF
awk '/^static long do_faccessat/{found=1} found && /^{/{print; system("cat /tmp/open_call.txt"); found=0; next} 1' fs/open.c > fs/open.c.tmp && mv fs/open.c.tmp fs/open.c

# Hook 3: fs/read_write.c - vfs_read hook
echo "Patching fs/read_write.c..."

cat > /tmp/read_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern bool ksu_vfs_read_hook __read_mostly;
extern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr, size_t *count_ptr, loff_t **pos);
#endif
HOOKEOF
sed -i '/#include <linux\/compat.h>/r /tmp/read_hook.txt' fs/read_write.c

cat > /tmp/read_call.txt << 'HOOKEOF'
#ifdef CONFIG_KSU
	if (unlikely(ksu_vfs_read_hook))
		ksu_handle_vfs_read(&file, &buf, &count, &pos);
#endif
HOOKEOF
awk '/^ssize_t vfs_read/{found=1} found && /^{/{print; system("cat /tmp/read_call.txt"); found=0; next} 1' fs/read_write.c > fs/read_write.c.tmp && mv fs/read_write.c.tmp fs/read_write.c

# Hook 4: fs/stat.c - stat hook
echo "Patching fs/stat.c..."

cat > /tmp/stat_hook.txt << 'HOOKEOF'

#ifdef CONFIG_KSU
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
#endif
HOOKEOF
sed -i '/#include <linux\/compat.h>/r /tmp/stat_hook.txt' fs/stat.c

cat > /tmp/stat_call.txt << 'HOOKEOF'
#ifdef CONFIG_KSU
	ksu_handle_stat(&dfd, &filename, &flags);
#endif
HOOKEOF
awk '/^int vfs_statx/{found=1} found && /^{/{print; system("cat /tmp/stat_call.txt"); found=0; next} 1' fs/stat.c > fs/stat.c.tmp && mv fs/stat.c.tmp fs/stat.c

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
  # Fallback: add after first #include block
  sed -i '0,/^#include/!b; /^#include.*$/a\
#ifdef CONFIG_KSU\
extern bool ksu_input_hook __read_mostly;\
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\
#endif
' drivers/input/input.c
fi

# For input_handle_event, we need to insert AFTER variable declarations
# The function signature and then find where statements begin
cat > /tmp/input_call.txt << 'HOOKEOF'
#ifdef CONFIG_KSU
	if (unlikely(ksu_input_hook))
		ksu_handle_input_handle_event(&type, &code, &value);
#endif
HOOKEOF

# Use a more sophisticated approach: find the function and insert after the first statement line
# Look for input_get_disposition which is the first actual code after variable decls
sed -i '/input_get_disposition(dev, type, code, \&value)/i\
#ifdef CONFIG_KSU\
	if (unlikely(ksu_input_hook))\
		ksu_handle_input_handle_event(\&type, \&code, \&value);\
#endif
' drivers/input/input.c

echo "Manual hooks added successfully!"
