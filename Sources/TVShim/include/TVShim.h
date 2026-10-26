#ifndef TVSHIM_H
#define TVSHIM_H

#include <mach/mach.h>

/// `mach_task_self` is a C macro over a mutable global; Swift 6 rejects reading that global.
/// Wrapping it in a function keeps the read in C and hands Swift a plain value.
mach_port_t tvbox_mach_task_self(void);

#endif /* TVSHIM_H */
