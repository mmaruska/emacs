/* Output like sprintf to a buffer of specified size.
   Also takes args differently: pass one pointer to the end
   of the format string in addition to the format string itself.
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

/* If you think about replacing this with some similar standard C function of
   the printf family (such as vsnprintf), please note that this function
   supports the following Emacs-specific features:

   . For %c conversions, it produces a string with the multibyte representation
     of the (`int') argument, suitable for display in an Emacs buffer.

   . For %s and %c, when field width is specified (e.g., %25s), it accounts for
     the diplay width of each character, according to char-width-table.  That
     is, it does not assume that each character takes one column on display.

   . If the size of the buffer is not enough to produce the formatted string in
     its entirety, it makes sure that truncation does not chop the last
     character in the middle of its multibyte sequence, producing an invalid
     sequence.

   . It accepts a pointer to the end of the format string, so the format string
     could include embedded null characters.

   . It signals an error if the length of the formatted string is about to
     overflow MOST_POSITIVE_FIXNUM, to avoid producing strings longer than what
     Emacs can handle.

   OTOH, this function supports only a small subset of the standard C formatted
   output facilities.  E.g., %u and %ll are not supported, and precision is
   ignored %s and %c conversions.  (See below for the detailed documentation of
   what is supported.)  However, this is okay, as this function is supposed to
   be called from `error' and similar functions, and thus does not need to
   support features beyond those in `Fformat', which is used by `error' on the
   Lisp level.  */

/* This function supports the following %-sequences in the `format'
   argument:

   %s means print a string argument.
   %S is silently treated as %s, for loose compatibility with `Fformat'.
   %d means print a `signed int' argument in decimal.
   %o means print an `unsigned int' argument in octal.
   %x means print an `unsigned int' argument in hex.
   %e means print a `double' argument in exponential notation.
   %f means print a `double' argument in decimal-point notation.
   %g means print a `double' argument in exponential notation
      or in decimal-point notation, whichever uses fewer characters.
   %c means print a `signed int' argument as a single character.
   %% means produce a literal % character.

   A %-sequence may contain optional flag, width, and precision specifiers, and
   a length modifier, as follows:

     %<flags><width><precision><length>character

   where flags is [+ -0], width is [0-9]+, precision is .[0-9]+, and length
   modifier is empty or l or ll.

   The + flag character inserts a + before any positive number, while a space
   inserts a space before any positive number; these flags only affect %d, %o,
   %x, %e, %f, and %g sequences.  The - and 0 flags affect the width specifier,
   as described below.  For signed numerical arguments only, the ` ' (space)
   flag causes the result to be prefixed with a space character if it does not
   start with a sign (+ or -).

   The l (lower-case letter ell) length modifier is a `long' data type
   modifier: it is supported for %d, %o, and %x conversions of integral
   arguments, must immediately precede the conversion specifier, and means that
   the respective argument is to be treated as `long int' or `unsigned long
   int'.  Similarly, ll (two letter ells) means to use `long long int' or
   `unsigned long long int'; this can be used only on hosts that have
   these two types.  The empty length modifier means to use `int' or
   `unsigned int'.  EMACS_INT arguments should use the pI macro, which
   expands to whatever length modifier is needed for the target host.

   The width specifier supplies a lower limit for the length of the printed
   representation.  The padding, if any, normally goes on the left, but it goes
   on the right if the - flag is present.  The padding character is normally a
   space, but (for numerical arguments only) it is 0 if the 0 flag is present.
   The - flag takes precedence over the 0 flag.

   For %e, %f, and %g sequences, the number after the "." in the precision
   specifier says how many decimal places to show; if zero, the decimal point
   itself is omitted.  For %s and %S, the precision specifier is ignored.  */

#include <config.h>
#include <stdio.h>
#include <ctype.h>
#include <setjmp.h>

#ifdef STDC_HEADERS
#include <float.h>
#endif

#include <unistd.h>

#include <limits.h>
#ifndef SIZE_MAX
# define SIZE_MAX ((size_t) -1)
#endif

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
   Returns the number of bytes stored into BUFFER, excluding
   the terminating null byte.  Output is always null-terminated.
   String arguments are passed as C strings.
   Integers are passed as C integers.  */

size_t
doprnt (char *buffer, register size_t bufsize, const char *format,
	const char *format_end, va_list ap)
{
  const char *fmt = format;	/* Pointer into format string */
  register char *bufptr = buffer; /* Pointer into output buffer.. */

  /* Use this for sprintf unless we need something really big.  */
  char tembuf[DBL_MAX_10_EXP + 100];

  /* Size of sprintf_buffer.  */
  size_t size_allocated = sizeof (tembuf);

  /* Buffer to use for sprintf.  Either tembuf or same as BIG_BUFFER.  */
  char *sprintf_buffer = tembuf;

  /* Buffer we have got with malloc.  */
  char *big_buffer = NULL;

  register size_t tem;
  char *string;
  char fixed_buffer[20];	/* Default buffer for small formatting. */
  char *fmtcpy;
  int minlen;
  char charbuf[MAX_MULTIBYTE_LENGTH + 1];	/* Used for %c.  */
  USE_SAFE_ALLOCA;

  if (format_end == 0)
    format_end = format + strlen (format);

  if ((format_end - format + 1) < sizeof (fixed_buffer))
    fmtcpy = fixed_buffer;
  else
    SAFE_ALLOCA (fmtcpy, char *, format_end - format + 1);

  bufsize--;

  /* Loop until end of format string or buffer full. */
  while (fmt < format_end && bufsize > 0)
    {
      if (*fmt == '%')	/* Check for a '%' character */
	{
	  size_t size_bound = 0;
	  EMACS_INT width;  /* Columns occupied by STRING on display.  */
	  int long_flag = 0;

	  fmt++;
	  /* Copy this one %-spec into fmtcpy.  */
	  string = fmtcpy;
	  *string++ = '%';
	  while (fmt < format_end)
	    {
	      *string++ = *fmt;
	      if ('0' <= *fmt && *fmt <= '9')
		{
		  /* Get an idea of how much space we might need.
		     This might be a field width or a precision; e.g.
		     %1.1000f and %1000.1f both might need 1000+ bytes.
		     Parse the width or precision, checking for overflow.  */
		  size_t n = *fmt - '0';
		  while (fmt < format_end
			 && '0' <= fmt[1] && fmt[1] <= '9')
		    {
		      if (n >= SIZE_MAX / 10
			  || n * 10 > SIZE_MAX - (fmt[1] - '0'))
			error ("Format width or precision too large");
		      n = n * 10 + fmt[1] - '0';
		      *string++ = *++fmt;
		    }

		  if (size_bound < n)
		    size_bound = n;
		}
	      else if (*fmt == '-' || *fmt == ' ' || *fmt == '.' || *fmt == '+')
		;
	      else if (*fmt == 'l')
		{
		  long_flag = 1 + (fmt + 1 < format_end && fmt[1] == 'l');
		  fmt += long_flag;
		  break;
		}
	      else
		break;
	      fmt++;
	    }
	  if (fmt > format_end)
	    fmt = format_end;
	  *string = 0;

	  /* Make the size bound large enough to handle floating point formats
	     with large numbers.  */
	  if (size_bound > SIZE_MAX - DBL_MAX_10_EXP - 50)
	    error ("Format width or precision too large");
	  size_bound += DBL_MAX_10_EXP + 50;

	  /* Make sure we have that much.  */
	  if (size_bound > size_allocated)
	    {
	      if (big_buffer)
		xfree (big_buffer);
	      big_buffer = (char *) xmalloc (size_bound);
	      sprintf_buffer = big_buffer;
	      size_allocated = size_bound;
	    }
	  minlen = 0;
	  switch (*fmt++)
	    {
	    default:
	      error ("Invalid format operation %%%s%c",
		     "ll" + 2 - long_flag, fmt[-1]);

/*	    case 'b': */
	    case 'l':
	    case 'd':
	      {
		int i;
		long l;

		if (1 < long_flag)
		  {
#ifdef HAVE_LONG_LONG_INT
		    long long ll = va_arg (ap, long long);
		    sprintf (sprintf_buffer, fmtcpy, ll);
#else
		    abort ();
#endif
		  }
		else if (long_flag)
		  {
		    l = va_arg(ap, long);
		    sprintf (sprintf_buffer, fmtcpy, l);
		  }
		else
		  {
		    i = va_arg(ap, int);
		    sprintf (sprintf_buffer, fmtcpy, i);
		  }
		/* Now copy into final output, truncating as necessary.  */
		string = sprintf_buffer;
		goto doit;
	      }

	    case 'o':
	    case 'x':
	      {
		unsigned u;
		unsigned long ul;

		if (1 < long_flag)
		  {
#ifdef HAVE_UNSIGNED_LONG_LONG_INT
		    unsigned long long ull = va_arg (ap, unsigned long long);
		    sprintf (sprintf_buffer, fmtcpy, ull);
#else
		    abort ();
#endif
		  }
		else if (long_flag)
		  {
		    ul = va_arg(ap, unsigned long);
		    sprintf (sprintf_buffer, fmtcpy, ul);
		  }
		else
		  {
		    u = va_arg(ap, unsigned);
		    sprintf (sprintf_buffer, fmtcpy, u);
		  }
		/* Now copy into final output, truncating as necessary.  */
		string = sprintf_buffer;
		goto doit;
	      }

	    case 'f':
	    case 'e':
	    case 'g':
	      {
		double d = va_arg(ap, double);
		sprintf (sprintf_buffer, fmtcpy, d);
		/* Now copy into final output, truncating as necessary.  */
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
	      if (tem > MOST_POSITIVE_FIXNUM)
		error ("String for %%s or %%S format is too long");
	      width = strwidth (string, tem);
	      goto doit1;

	      /* Copy string into final output, truncating if no room.  */
	    doit:
	      /* Coming here means STRING contains ASCII only.  */
	      tem = strlen (string);
	      if (tem > MOST_POSITIVE_FIXNUM)
		error ("Format width or precision too large");
	      width = tem;
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
		int chr = va_arg(ap, int);
		tem = CHAR_STRING (chr, (unsigned char *) charbuf);
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
	while (fmt < format_end && --bufsize > 0 && !CHAR_HEAD_P (*fmt));
	if (!CHAR_HEAD_P (*fmt))
	  {
	    bufptr = save_bufptr;
	    break;
	  }
      }
    };

  /* If we had to malloc something, free it.  */
  xfree (big_buffer);

  *bufptr = 0;		/* Make sure our string ends with a '\0' */

  SAFE_FREE ();
  return bufptr - buffer;
}
