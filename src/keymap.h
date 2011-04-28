/* Functions to manipulate keymaps.
   Copyright (C) 2001-2011 Free Software Foundation, Inc.

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

#ifndef KEYMAP_H
#define KEYMAP_H

#define KEYMAPP(m) (!NILP (get_keymap (m, 0, 0)))
extern Lisp_Object Qkeymap, Qmenu_bar;
extern Lisp_Object Qremap;
extern Lisp_Object Qmenu_item;
extern Lisp_Object current_global_map;
EXFUN (Fmake_sparse_keymap, 1);
EXFUN (Fkeymap_prompt, 1);
EXFUN (Fdefine_key, 3);
EXFUN (Fcommand_remapping, 3);
EXFUN (Fkey_binding, 4);
EXFUN (Fkey_description, 2);
EXFUN (Fsingle_key_description, 2);
EXFUN (Fwhere_is_internal, 5);
EXFUN (Fcurrent_active_maps, 2);
extern Lisp_Object access_keymap (Lisp_Object, Lisp_Object, int, int, int);
extern Lisp_Object get_keymap (Lisp_Object, int, int);
EXFUN (Fset_keymap_parent, 2);
extern void describe_map_tree (Lisp_Object, int, Lisp_Object, Lisp_Object,
                               const char *, int, int, int, int);
extern int current_minor_maps (Lisp_Object **, Lisp_Object **);
extern void initial_define_key (Lisp_Object, int, const char *);
extern void initial_define_lispy_key (Lisp_Object, const char *, const char *);
extern void syms_of_keymap (void);
extern void keys_of_keymap (void);

typedef void (*map_keymap_function_t)
     (Lisp_Object key, Lisp_Object val, Lisp_Object args, void* data);
extern void map_keymap (Lisp_Object map, map_keymap_function_t fun, Lisp_Object largs, void* cargs, int autoload);
extern void map_keymap_canonical (Lisp_Object map,
				  map_keymap_function_t fun,
				  Lisp_Object args, void *data);

#endif
