"""Linux execution boundary for clean extraction. Denies every socket syscall."""
import ctypes
import errno
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(38, 1, 0, 0, 0) != 0:
    raise RuntimeError("no_new_privs unavailable")
seccomp = ctypes.CDLL("libseccomp.so.2")
seccomp.seccomp_init.argtypes = [ctypes.c_uint32]
seccomp.seccomp_init.restype = ctypes.c_void_p
seccomp.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
seccomp.seccomp_rule_add.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_uint]
seccomp.seccomp_load.argtypes = [ctypes.c_void_p]
seccomp.seccomp_release.argtypes = [ctypes.c_void_p]
context = seccomp.seccomp_init(0x7FFF0000)
if not context:
    raise RuntimeError("seccomp unavailable")
try:
    for name in ("socket", "socketpair", "connect", "bind", "listen", "accept", "accept4", "sendto", "sendmsg", "recvfrom", "recvmsg", "io_uring_setup", "io_uring_enter", "io_uring_register", "ptrace", "process_vm_readv", "process_vm_writev"):
        number = seccomp.seccomp_syscall_resolve_name(name.encode())
        if number >= 0 and seccomp.seccomp_rule_add(context, 0x00050000 | errno.EPERM, number, 0) != 0:
            raise RuntimeError("seccomp rule unavailable")
    if seccomp.seccomp_load(context) != 0:
        raise RuntimeError("seccomp load unavailable")
finally:
    seccomp.seccomp_release(context)
os.execv(sys.argv[1], sys.argv[1:])
