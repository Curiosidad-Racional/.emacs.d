;;; thing-cmds-autoloads.el --- automatically extracted autoloads
;;
;;; Code:


;;;### (autoloads nil "thing-cmds" "thing-cmds.el" (0 0 0 0))
;;; Generated autoloads from thing-cmds.el

(defalias 'thing-region 'select-thing)

(autoload 'select-thing "thing-cmds" "\
Set the region around a THING at or near the cursor.
You are prompted for the type of thing.  Completion is available (lax).
The cursor is placed at the end of the region.  You can return it to
the original location by using `C-u C-SPC' twice.
Non-interactively, THING is a string naming a thing type.

If option `thgcmd-use-nearest-thing-flag' and non-nil then use a thing
that is near, not necessarily at, point.

\(fn THING)" t nil)

(defalias 'cycle-thing-region 'cycle-select-something)

(autoload 'cycle-select-something "thing-cmds" "\
Select something at or near point.  Successively select different things.
The default thing type is the first element of option `thing-types'.
In Transient Mark mode, you can follow this with `\\[select-things]' to select
successive things of the same type, but to do that you must first use
`C-x C-x': `\\[cycle-select-something] C-x C-x \\[select-things]'.

If option `thgcmd-use-nearest-thing-flag' and non-nil then use a thing
that is near, not necessarily at, point.

\(fn)" t nil)

(defalias 'mark-things 'select-things)

(autoload 'select-things "thing-cmds" "\
Set point at one end of THING and set mark ARG THINGs from point.
THING is a symbol that names a type of thing.  Interactively, you are
prompted for it.  Completion is available (lax).

\(If THING doesn't have an associated `forward-'THING operation then
do nothing.)

Put mark at the same place command `forward-'THING would move point
with the same prefix argument.

Put point at the beginning of THING, unless the prefix argument (ARG)
is negative, in which case put it at the end of THING.

If `select-things' is repeated or if the mark is active (in Transient
Mark mode), then it marks the next ARG THINGs, after the ones already
marked.  In this case the type of THING used is whatever was used the
last time `select-things' was called - you are not prompted for it.

This region extension reusing the last type of THING happens even if
the active region is empty.  This means that you can, for instance,
just use `C-SPC' to activate an empty region and then use
`select-things' to select more THINGS of the last kind selected.

If there is no THING at point, and `thgcmd-use-nearest-thing-flag' is
non-nil, then select a THING near point.

\(fn THING &optional ARG ALLOW-EXTEND)" t nil)

(defalias 'mark-enclosing-list 'select-enclosing-list)

(autoload 'select-enclosing-list "thing-cmds" "\
Select a list surrounding the current cursor position.
If the mark is active (e.g. when the command is repeated), widen the
region to a list that encloses it.

The starting position is added to the mark ring before doing anything
else, so you can return to it (e.g. using `C-u C-SPC').

A prefix argument determines which enclosing list is selected: 1 means
the immediately enclosing list, 2 means the list immediately enclosing
that one, etc.

A negative prefix argument puts point at the beginning of the region
instead of the end.

\"List\" here really means a balanced-parenthesis expression.  The
syntax table determines which characters are such balanced delimiters.
See (emacs) `Moving by Parens' and (elisp) `List Motion'.

This command might not work as expected if point is in a string or a
comment.

\(fn &optional ARG ALLOW-EXTEND)" t nil)

(defalias 'mark-enclosing-list-forward 'select-enclosing-list-forward)

(autoload 'select-enclosing-list-forward "thing-cmds" "\
`select-enclosing-list' leaving point at region end.

\(fn &optional ARG)" t nil)

(defalias 'mark-enclosing-list-backward 'select-enclosing-list-backward)

(autoload 'select-enclosing-list-backward "thing-cmds" "\
`select-enclosing-list' leaving point at region start.

\(fn &optional ARG)" t nil)

(autoload 'next-visible-thing-repeat "thing-cmds" "\
Go to and get the next visible THING.
This is a repeatable version of `next-visible-thing'.

\(fn)" t nil)

(autoload 'previous-visible-thing-repeat "thing-cmds" "\
Go to and get the previous visible THING.
This is a repeatable version of `previous-visible-thing'.

\(fn)" t nil)

(autoload 'thgcmd-bind-keys "thing-cmds" "\
Bind some keys to commands defined in `thing-cmds.el'.
NOTE concerning the visible-thing navigation keys:

`C-x down' and `C-x up' are bound here (for Emacs 21 and later) to
`next-visible-thing-repeat' and `previous-visible-thing-repeat',
respectively.  This means you can use `C-x down down down...' etc. to
move forward to successive things, and similarly for `C-x up...' and
backward.  You are asked for the thing type only the first time you
hit `down' or `up' after `C-x'.

However, you cannot mix the directions forward/backward without
inputting the thing type again.  For example, If you do `C-x down up',
the `up' does not perform thing navigation (it probably does
`previous-line', the default `up' binding) .

To change direction without getting prompted for the thing type, you
need to bind, not commands `next-visible-thing-repeat' and
`previous-visible-thing-repeat', but commands `next-visible-thing' and
`previous-visible-thing' (no `-repeat' suffix).  Bind these to simple,
repeatable keys, such as `f8' and `f9'.  Because such keys are rare
\(mostly taken already), the only bindings made here for thing
navigation are `C-x down' and `C-x up'.

\(fn &optional MSGP)" t nil)

(if (fboundp 'register-definition-prefixes) (register-definition-prefixes "thing-cmds" '(#("thing-types" 0 2 (fontified nil) 2 11 (fontified nil)) #("thgcmd-" 0 2 (fontified nil) 2 7 (fontified nil)) #("with-comments-hidden" 0 20 (fontified nil)))))

;;;***

(provide 'thing-cmds-autoloads)
;; Local Variables:
;; version-control: never
;; no-byte-compile: t
;; no-update-autoloads: t
;; coding: utf-8
;; End:
;;; thing-cmds-autoloads.el ends here
