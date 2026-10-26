#include "TVShim.h"

mach_port_t tvbox_mach_task_self(void) { return mach_task_self(); }
