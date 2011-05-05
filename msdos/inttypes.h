/* Replacement inntypes.h file for building GNU Emacs on MS-DOS with DJGPP.

Copyright (C) 2011  Free Software Foundation, Inc.

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

#ifndef _REPL_INTTYPES_H
#define _REPL_INTTYPES_H

#if __DJGPP__ > 2 || __DJGPP_MINOR__ >= 4
#include_next <inttypes.h>
#else  /* __DJGPP__ < 2.04 */
#include <stdlib.h>
#define uintmax_t unsigned long long
#define strtoumax strtoull
#endif	/* __DJGPP__ < 2.04 */

#endif
