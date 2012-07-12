/* System description file for hpux version 10.20.

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
#define HPUX

/* Special hacks needed to make Emacs run on this system.  */

/* Assar Westerlund <assar@sics.se> says this is necessary for
   HP-UX 10.20, and that it works for HP-UX 0 as well.  */
#define NO_EDITRES

/* We have to go this route, rather than hpux9's approach of renaming the
   functions via macros.  The system's stdlib.h has fully prototyped
   declarations, which yields a conflicting definition of srand48; it
   tries to redeclare what was once srandom to be srand48.  So we go
   with HAVE_LRAND48 being defined.
   Note we also undef HAVE_RANDOM via configure.  */
#undef srandom
#undef random

/* Rainer Malzbender <rainer@displaytech.com> says defining
   HAVE_XRMSETDATABASE allows Emacs to compile on HP-UX 10.20 using GCC.  */
#ifndef HAVE_XRMSETDATABASE
#define HAVE_XRMSETDATABASE
#endif

/* Conservative garbage collection has not been tested, so for now
   play it safe and stick with the old-fashioned way of marking.  */
#define GC_MARK_STACK GC_USE_GCPROS_AS_BEFORE
