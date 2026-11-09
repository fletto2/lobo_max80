/*	EFUNC.H:	MicroEMACS function declarations and names

		This file list all the C code functions used by MicroEMACS
	and the names to use to bind keys to them. To add functions,
	declare it here in both the extern function list and the name
	binding table.

	Update History:

	Daniel Lawrence
		29-jan-86
		- separeted out external declarations to a separate .h file
		- built original name to function binding table
		30-jan-86
		- added command declarations for Fill Paragraph command
		11-feb-86
		- added declaration for help and describe key commands
		13-feb-86
		- added declarations for view-file command
		15-feb-86
		- added declataitons for insert file command
		17-feb-86
		- added declarations for scroll next window up/down
		20-feb-86
		- expanded binding table to make room for new bindings
		24-feb-86
		- added declarations for bind-to-key and unbind-key
		  execute named command and describe bindings
		26-feb-86
		- added declarations for execute command
		- changed name of "visit-file" to "find-file"
		- added declaration for execute-buffer command
		27-feb-86
		- added declarations for execute-file command
		3-apr-86
		- added declarations for next-buffer command
		5-apr-86
		- added declarations for kill-paragraph command
		8-apr-86
		- added declarations for add/delete global mode
		8-apr-86
		- added declarations for insert space command
*/

/*	External function declarations		*/


#if	V7 & BSD
#endif

/*	Name to function binding table

		This table gives the names of all the bindable functions
	end their C function address. These are used for the bind-to-key
	function.
*/

#if	NAMES
NBIND	names[] = {
	{"add-mode",			setmode},
	{"add-global-mode",		setgmode},
	{"backward-character",		backchar},
	{"begin-macro",			ctlxlp},
	{"begining-of-file",		gotobob},
	{"begining-of-line",		gotobol},
	{"bind-to-key",			bindtokey},
	{"buffer-position",		showcpos},
	{"case-region-lower",		lowerregion},
	{"case-region-upper",		upperregion},
	{"case-word-capitalize",	capword},
	{"case-word-lower",		lowerword},
	{"case-word-upper",		upperword},
	{"change-file-name",		filename},
	{"clear-and-redraw",		refresh},
	{"copy-region",			copyregion},
	{"delete-blank-lines",		deblank},
	{"delete-buffer",		killbuffer},
	{"delete-mode",			delmode},
	{"delete-global-mode",		delgmode},
	{"delete-next-character",	forwdel},
	{"delete-next-word",		delfword},
	{"delete-other-windows",	onlywind},
	{"delete-previous-character",	backdel},
	{"delete-previous-word",	delbword},
	{"describe-bindings",		desbind},
	{"describe-key",		deskey},
	{"end-macro",			ctlxrp},
	{"end-of-file",			gotoeob},
	{"end-of-line",			gotoeol},
	{"exchange-point-and-mark",	swapmark},
	{"execute-buffer",		execbuf},
	{"execute-command-line",	execcmd},
	{"execute-file",		execfile},
	{"execute-macro",		ctlxe},
	{"execute-named-command",	namedcmd},
	{"exit-emacs",			quit},
	{"fill-paragraph",		fillpara},
	{"find-file",			filefind},
	{"forward-character",		forwchar},
	{"goto-line",			gotoline},
	{"grow-window",			enlargewind},
	{"handle-tab",			tab},
	{"hunt-forward",		forwhunt},
	{"hunt-backward",		backhunt},
	{"help",			help},
	{"i-shell",			spawncli},
	{"insert-file",			insfile},
	{"insert-space",		insspace},
	{"kill-paragraph",		killpara},
	{"kill-region",			killregion},
	{"kill-to-end-of-line",		killtext},
	{"list-buffers",		listbuffers},
	{"move-window-down",		mvdnwind},
	{"move-window-up",		mvupwind},
	{"name-buffer",			namebuffer},
	{"newline",			newline},
	{"newline-and-indent",		indent},
	{"next-buffer",			nextbuffer},
	{"next-line",			forwline},
	{"next-page",			forwpage},
	{"next-paragraph",		gotoeop},
	{"next-window",			nextwind},
	{"next-word",			forwword},
	{"open-line",			openline},
	{"previous-line",		backline},
	{"previous-page",		backpage},
	{"previous-paragraph",		gotobop},
	{"previous-window",		prevwind},
	{"previous-word",		backword},
	{"query-replace-string",	qreplace},
	{"quick-exit",			quickexit},
	{"quote-character",		quote},
	{"read-file",			fileread},
	{"redraw-display",		reposition},
	{"replace-string",		sreplace},
	{"save-file",			filesave},
	{"scroll-next-up",		scrnextup},
	{"scroll-next-down",		scrnextdw},
	{"search-forward",		forwsearch},
	{"search-reverse",		backsearch},
	{"select-buffer",		usebuffer},
	{"set-fill-column",		setfillcol},
	{"set-mark",			setmark},
	{"shell-command",		spawn},
	{"shrink-window",		shrinkwind},
	{"split-current-window",	splitwind},
#if	V7 & BSD
	{"suspend-emacs",		bktoshell},
#endif
	{"transpose-characters",	twiddle},
	{"unbind-key",			unbindkey},
	{"view-file",			viewfile},
	{"write-file",			filewrite},
	{"yank",			yank},

	{"",			NULL}
};
#endif
