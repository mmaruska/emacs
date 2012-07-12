/* System description header file for Darwin (Mac OS X).

Copyright (C) 2001-2012  Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.  */


/* Define symbols to identify the version of Unix this is.
   Define all the symbols that apply correctly.  */
#define BSD4_2
/* BSD4_3 and BSD4_4 are already defined in sys/param.h */
#define BSD_SYSTEM

/* More specific than the above two.  We cannot use __APPLE__ as this
   may not be defined on non-OSX Darwin, and we cannot define DARWIN
   here because Panther and lower CoreFoundation.h uses DARWIN to
   distinguish OS X from pure Darwin.  */
#define DARWIN_OS

#define PTY_NAME_SPRINTF	/* none */
#define PTY_TTY_NAME_SPRINTF	/* none */
/* Note that openpty may fork via grantpt on Mac OS X 10.4/Darwin 8.
   But we don't have to block SIGCHLD because it is blocked in the
   implementation of grantpt.  */
#define PTY_OPEN						\
  do								\
    {								\
      int slave;						\
      if (openpty (&fd, &slave, pty_name, NULL, NULL) == -1)	\
	fd = -1;						\
      else							\
	emacs_close (slave);					\
    }								\
  while (0)

/* PTYs only work correctly on Darwin 7 or higher.  So make the default
   for process-connection-type dependent on the kernel version.  */
#define MIN_PTY_KERNEL_VERSION '7'

/* Avoid the use of the name init_process (process.c) because it is
   also the name of a Mach system call.  */
#define init_process emacs_init_process

/* Definitions for how to compile & link.  */
#ifdef HAVE_NS
#define SYSTEM_PURESIZE_EXTRA 200000
#endif

#ifdef emacs
#define malloc unexec_malloc
#define realloc unexec_realloc
#define free unexec_free
/* Don't use posix_memalign because it is not compatible with unexmacosx.c.  */
#undef HAVE_POSIX_MEMALIGN
#endif

/* The following solves the problem that Emacs hangs when evaluating
   (make-comint "test0" "/nodir/nofile" nil "") when /nodir/nofile
   does not exist.  Also, setsid is not allowed in the vfork child's
   context as of Darwin 9/Mac OS X 10.5.  */
#undef HAVE_WORKING_VFORK
#define vfork fork
