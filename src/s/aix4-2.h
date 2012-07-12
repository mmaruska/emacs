/*
Copyright (C) 1999, 2001-2012  Free Software Foundation, Inc.

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
#define USG				/* System III, System V, etc */
#define USG5

/* This symbol should be defined on AIX Version 3  ??????? */
#ifndef _AIX
#define _AIX
#endif

/* In AIX, you allocate a pty by opening /dev/ptc to get the master side.
   To get the name of the slave side, you just ttyname() the master side.  */
#define PTY_NAME_SPRINTF strcpy (pty_name, "/dev/ptc");
#define PTY_TTY_NAME_SPRINTF strcpy (pty_name, ttyname (fd));


/* Special items needed to make Emacs run on this system.  */

/* Perry Smith <pedz@ddivt1.austin.ibm.com> says these are correct.  */
#undef sigmask

#ifndef HAVE_LIBXMU
/* Unfortunately without libXmu we cannot support EditRes.  */
#define NO_EDITRES
#endif

/* Conservative garbage collection has not been tested, so for now
   play it safe and stick with the old-fashioned way of marking.  */
#define GC_MARK_STACK GC_USE_GCPROS_AS_BEFORE
