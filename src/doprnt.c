/* Output like sprintf to a buffer of specified size.
   Also takes args differently: pass one pointer to an array of strings
   in addition to the format string which is separate.
   Copyright (C) 1985, 2001-2011  Free Software Foundation, Inc.

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


#include <config.h>
#include <stdio.h>
#include <ctype.h>
#include <setjmp.h>

#ifdef STDC_HEADERS
#include <float.h>
#endif

#include <unistd.h>

#include "lisp.h"

/* Since we use the macro CHAR_HEAD_P, we have to include this, but
   don't have to include others because CHAR_HEAD_P does not contains
   another macro.  */
#include "character.h"

#ifndef DBL_MAX_10_EXP
#define DBL_MAX_10_EXP 308 /* IEEE double */
#endif

/* Generate output from a format-spec FORMAT,
   terminated at position FORMAT_END.
   Output goes in BUFFER, which has room for BUFSIZE chars.
   If the output does not fit, truncate it to fit.
   Returns the number of bytes stored into BUFFER.
   ARGS points to the vector of arguments, and NARGS says how many.
   A double counts as two arguments.
   String arguments are passed as C strings.
   Integers are passed as C integers.  */

EMACS_INT
doprnt (char *buffer, register int bufsize, const char *format,
	const char *format_end, va_list ap)
{
  const char *fmt = format;	/* Pointer into format string */
  register char *bufptr = buffer; /* Pointer into output buffer.. */

  /* Use this for sprintf unless we need something really big.  */
  char tembuf[DBL_MAX_10_EXP + 100];

  /* Size of sprintf_buffer.  */
  unsigned size_allocated = sizeof (tembuf);

  /* Buffer to use for sprintf.  Either tembuf or same as BIG_BUFFER.  */
  char *sprintf_buffer = tembuf;

  /* Buffer we have got with malloc.  */
  char *big_buffer = 0;

  register int tem;
  char *string;
  char fixed_buffer[20];	/* Default buffer for small formatting. */
  char *fmtcpy;
  int minlen;
  char charbuf[MAX_MULTIBYTE_LENGTH + 1];	/* Used for %c.  */

  if (format_end == 0)
    format_end = format + strlen (format);

  if ((format_end - format + 1) < sizeof (fixed_buffer))
    fmtcpy = fixed_buffer;
  else
    fmtcpy = (char *) alloca (format_end - format + 1);

  bufsize--;

  /* Loop until end of format string or buffer full. */
  while (fmt != format_end && bufsize > 0)
    {
      if (*fmt == '%')	/* Check for a '%' character */
	{
	  unsigned size_bound = 0;
	  EMACS_INT width;  /* Columns occupied by STRING.  */

	  fmt++;
	  /* Copy this one %-spec into fmtcpy.  */
	  string = fmtcpy;
	  *string++ = '%';
	  while (1)
	    {
	      *string++ = *fmt;
	      if ('0' <= *fmt && *fmt <= '9')
		{
		  /* Get an idea of how much space we might need.
		     This might be a field width or a precision; e.g.
		     %1.1000f and %1000.1f both might need 1000+ bytes.
		     Parse the width or precision, checking for overflow.  */
		  unsigned n = *fmt - '0';
		  while ('0' <= fmt[1] && fmt[1] <= '9')
		    {
		      if (n * 10 + fmt[1] - '0' < n)
			error ("Format width or precision too large");
		      n = n * 10 + fmt[1] - '0';
		      *string++ = *++fmt;
		    }

		  if (size_bound < n)
		    size_bound = n;
		}
	      else if (*fmt == '-' || *fmt == ' ' || *fmt == '.' || *fmt == '+')
		;
	      else
		break;
	      fmt++;
	    }
	  *string = 0;

	  /* Make the size bound large enough to handle floating point formats
	     with large numbers.  */
	  if (size_bound + DBL_MAX_10_EXP + 50 < size_bound)
	    error ("Format width or precision too large");
	  size_bound += DBL_MAX_10_EXP + 50;

	  /* Make sure we have that much.  */
	  if (size_bound > size_allocated)
	    {
	      if (big_buffer)
		big_buffer = (char *) xrealloc (big_buffer, size_bound);
	      else
		big_buffer = (char *) xmalloc (size_bound);
	      sprintf_buffer = big_buffer;
	      size_allocated = size_bound;
	    }
	  minlen = 0;
	  switch (*fmt++)
	    {
	    default:
	      error ("Invalid format operation %%%c", fmt[-1]);

/*	    case 'b': */
	    case 'd':
	    case 'o':
	    case 'x':
	      if (sizeof (int) == sizeof (EMACS_INT))
		;
	      else if (sizeof (long) == sizeof (EMACS_INT))
		/* Insert an `l' the right place.  */
		string[1] = string[0],
		string[0] = string[-1],
		string[-1] = 'l',
		string++;
	      else
		abort ();
	      sprintf (sprintf_buffer, fmtcpy, va_arg(ap, char *));
	      /* Now copy into final output, truncating as nec.  */
	      string = sprintf_buffer;
	      goto doit;

	    case 'f':
	    case 'e':
	    case 'g':
	      {
		double d = va_arg(ap, double);
		sprintf (sprintf_buffer, fmtcpy, d);
		/* Now copy into final output, truncating as nec.  */
		string = sprintf_buffer;
		goto doit;
	      }

	    case 'S':
	      string[-1] = 's';
	    case 's':
	      if (fmtcpy[1] != 's')
		minlen = atoi (&fmtcpy[1]);
	      string = va_arg (ap, char *);
	      tem = strlen (string);
	      width = strwidth (string, tem);
	      goto doit1;

	      /* Copy string into final output, truncating if no room.  */
	    doit:
	      /* Coming here means STRING contains ASCII only.  */
	      width = tem = strlen (string);
	    doit1:
	      /* We have already calculated:
		 TEM -- length of STRING,
		 WIDTH -- columns occupied by STRING when displayed, and
		 MINLEN -- minimum columns of the output.  */
	      if (minlen > 0)
		{
		  while (minlen > width && bufsize > 0)
		    {
		      *bufptr++ = ' ';
		      bufsize--;
		      minlen--;
		    }
		  minlen = 0;
		}
	      if (tem > bufsize)
		{
		  /* Truncate the string at character boundary.  */
		  tem = bufsize;
		  while (!CHAR_HEAD_P (string[tem - 1])) tem--;
		  memcpy (bufptr, string, tem);
		  /* We must calculate WIDTH again.  */
		  width = strwidth (bufptr, tem);
		}
	      else
		memcpy (bufptr, string, tem);
	      bufptr += tem;
	      bufsize -= tem;
	      if (minlen < 0)
		{
		  while (minlen < - width && bufsize > 0)
		    {
		      *bufptr++ = ' ';
		      bufsize--;
		      minlen++;
		    }
		  minlen = 0;
		}
	      continue;

	    case 'c':
	      {
		/* Sometimes for %c we pass a char, which would widen
		   to int.  Sometimes we pass XFASTINT() or XINT()
		   values, which would be EMACS_INT.  Let's hope that
		   both are passed the same way, otherwise we'll need
		   to rewrite callers.  */
		EMACS_INT chr = va_arg(ap, EMACS_INT);
		tem = CHAR_STRING ((int) chr, (unsigned char *) charbuf);
		string = charbuf;
		string[tem] = 0;
		width = strwidth (string, tem);
		if (fmtcpy[1] != 'c')
		  minlen = atoi (&fmtcpy[1]);
		goto doit1;
	      }

	    case '%':
	      fmt--;    /* Drop thru and this % will be treated as normal */
	    }
	}

      {
	/* Just some character; Copy it if the whole multi-byte form
	   fit in the buffer.  */
	char *save_bufptr = bufptr;

	do { *bufptr++ = *fmt++; }
	while (--bufsize > 0 && !CHAR_HEAD_P (*fmt));
	if (!CHAR_HEAD_P (*fmt))
	  {
	    bufptr = save_bufptr;
	    break;
	  }
      }
    };

  /* If we had to malloc something, free it.  */
  xfree (big_buffer);

  *bufptr = 0;		/* Make sure our string end with a '\0' */
  return bufptr - buffer;
}
