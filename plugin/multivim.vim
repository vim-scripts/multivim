" Integrating multiple vim sessions.
" Author: Kartik Agaram
" Requirements: *NIX
"
" This script makes multiple vim sessions (windows) aware of each other and
" seem like a single application. For the most part, we modify existing
" commands, and they should work pretty intuitively. The following is a
" complete list of new and modified commands and mappings.
"
"   I: Enable yanking and putting text between sessions.
"
"   II: Enable sessions to 'steal' files from each other. The
"   'files/buffers/ls' command now shows a global list of open buffers.
"   Files in other sessions can be stolen either by name, or by session and
"   buffer number. Thus, the command "e 3:2" will steal buffer #2 in session
"   #3. The numbering of sessions is different in each session, and sessions
"   drop off this list if they are suspended, so numbering can change even
"   in the course of a single session.
"       Modified: edit, files/buffers/ls, split, vsplit.
"           [For handling suspended sessions] stop, ^Z.
"           New functionality: buffers can be specified as
"               <session id>:buffer number
"           session id's are shown in files/buffers/ls.
"
"       New: nf (new frame)
"
"   III: Integrate command histories. I've chosen to keep the histories
"   distinct, but provided the push and pop commands to allow easy transfer
"   of commands.
"       New: push, pop
"
" Problems:
"   FileStealing:
"   Tag navigation (^W^]) can't steal files from remote sessions.
"   Trying to steal a remote file that's the only file in its
"       session won't work.
"
"   History:
"   Commandline history register cannot be overwritten.

let s:serverFile = "~/.vim_serverlist"
let s:histTempFile = expand ("~") . "/.vim_temphist"

" I: Enable yank and put between sessions.
set clipboard=unnamed

" II: Editing files from a remote buffer list.
"
" Files can be referred to either by name or in the form
" sessionNumber:bufferNumber. SessionNumbers are as given in the 'files'
" command, and can change if you change any sessions.
let s:serverListCmd = "let serverlist = system (\"cat " . s:serverFile . "\")"
let s:servernamere = "[^\n]\\+"

" From bcbuf.vim on http://vim.sf.net
function! StealFile (...)
    " Are we opening a file by number?
    let usingBufNum = 0

    if (a:0 == 0)
        edit
        return
    elseif (a:0 == 1)
        let name = expand (a:1)
        if (name == "")
            if (match (a:1, "^[0-9]\\+:[0-9]\\+$") >= 0)
                let usingBufNum = 1
                let serverNum = substitute (a:1, "\:.*", "", "")
                let bufferNum = substitute (a:1, "\.*:", "", "")
            else
                exec "edit " . a:1
                return
            endif
        endif
    else
        print "Incorrect number of args"
        return
    endif

    exec s:serverListCmd
    let pos = 0
    if (usingBufNum == 0)
        let file = tempname ()
        let name = fnamemodify (name, ":p")

        if match (name, '/\.\./') >= 0
            echo name . "contains /../, cannot handle this."
            return
        endif

        if bufexists (name) && bufloaded (name)
                \ && getbufvar (bufnr (name), "&modifiable")
            exec "edit " . name
            return
        endif

        while match (serverlist, s:servernamere, pos) >= 0
            let server = matchstr (serverlist, s:servernamere, pos)
            let pos = matchend (serverlist, s:servernamere, pos)
            let rExistsCmd = "bufexists (\"" . name . "\") && bufloaded (\"" . name . "\") && getbufvar (bufnr (\"" . name . "\"), \"&modifiable\")"
            if remote_expr (server, rExistsCmd)
                let rGetBufCmd = "getbufvar (bufnr (\"" . name . "\"), \"&modified\")"
                if remote_expr (server, rGetBufCmd)
                    echo "Server " . server . " has modified it."
                    return
                endif
                let expr = "UnloadBufReturnView (\"" . name . "\")"
                let viewname = remote_expr (server, expr)
                exec "silent source " . viewname . "| silent echo delete (\"" . viewname . "\")"
                return
            endif
        endwhile
    else
        let i = 1
        while match (serverlist, s:servernamere, pos) >= 0
            let server = matchstr(serverlist,s:servernamere,pos)
            let pos = matchend(serverlist,s:servernamere,pos)
            
            if server != v:servername
                if i == serverNum
                    if remote_expr (server, "getbufvar (" . bufferNum . ", \"&modified\")")
                        echo "Server " . server . " has modified it."
                        return
                    endif
                    let viewname = remote_expr (server, "UnloadBufReturnView (bufname (" . bufferNum . "))")
                    exec "silent source " . viewname . "| silent echo delete (\"" . viewname . "\")"
                    return
                endif
                let i = i + 1
            endif
        endwhile
    endif

    exec "edit " . name
endfunction

function! UnloadBufReturnView (name)
    " Get rid of annoying beep, just for this.
    set visualbell t_vb=

	let windownr = bufwinnr (a:name)
	if windownr < 0 
		exec "silent edit " . a:name
	else
		exec windownr . "winc w"
	endif

	let viewname = tempname ()
	exec "mkview " . viewname

	bdelete
    set novisualbell

	redraw
	return viewname
endfunction

command! -nargs=? -complete=file E call StealFile (<f-args>)
cabbrev e E
command! -nargs=? -complete=file Vsplit vsplit |call StealFile (<f-args>)
command! -nargs=? -complete=file Hsplit split |call StealFile (<f-args>)
cabbrev split Hsplit
cabbrev vsplit Vsplit

function! GlobalFileList ()
    exec s:serverListCmd
	let pos = 0
	let file = tempname()
    let i = 1
	while match(serverlist,s:servernamere,pos) >= 0
		let server = matchstr(serverlist,s:servernamere,pos)
		let pos = matchend(serverlist,s:servernamere,pos)
		if server == v:servername
			continue
		endif
		let rc = remote_send(server,'<C-\><C-N>:redir >> ' . file . '| silent exe "echo \"\[' . i . '\]\" | lbuffers" | redir END<CR>')
        let i = i + 1
	endwhile

	exec "echo 'local:' | buffers"
	if has("unix")
		let output = system("cat " . file)
	else
		let output = system("type " . file)
	endif
	let dummy = delete( file )
	echo output
endfunction
command! -nargs=0 Files call GlobalFileList ()
cabbrev files Files
cabbrev buffers Files
cabbrev ls Files
cnoreabbrev lbuffers buffers

" New command: nf
" Opens a new vim window.
" Arguments: list of files to edit in a new window.
function! NewFrame (...)
    if (a:0 == 0)
        silent exec "!Eterm -e bash -c vim_stub &"
    else
        let args = ""
        let i = 1
        while i <= a:0
            exec "let args = args . \" \" . a:" . i
            let i = i + 1
        endwhile
        silent exec "!Eterm -e bash -c vim_stub " . args . " &"
    endif
endfunction
command! -nargs=* -complete=file Nf call NewFrame (<q-args>)
cabbrev nf Nf

" Make sure we don't send remote commands to sessions that are currently
" suspended.
function! StopVim ()
    " Commands to be executed on suspending vim.
    call RemoveVimEntry ()

    stop

    " Commands to be executed on resumption.
    call AddVimEntry ()
endfunction
command! -nargs=0 Stop call StopVim ()
map  :Stop<CR>
cabbrev stop Stop

function! AddVimEntry ()
    exec "call system (\"echo " . v:servername . " >> " . s:serverFile . "\")"
endfunction
autocmd VimEnter * call AddVimEntry ()

function! RemoveVimEntry ()
    exec "call system (\"grep -v " . v:servername . " " . s:serverFile . " > " . s:serverFile . ".new ; mv " . s:serverFile . ".new " . s:serverFile . "\")"
endfunction
autocmd VimLeave * call RemoveVimEntry ()

" III: Transferring history between sessions.
" vim has multiple kinds of histories whose entries can be pushed. :help history.

" New command: push
" Make the most recent entry in the history accessible to other vim sessions.
"
" Arguments:
"   The history table from which we want to push an entry. The default is the
"   command history ':'.
"   The index in the table that we want to push. The default is the most
"   recent entry (-1).
"
" The global space isn't a stack, just a single shared command. Only the
" most recent push is remembered, and popping does not erase it.
function! HistPush (...)
    if (a:0 == 0)
        let cmd = ":"
    else
        let cmd = a:1
    endif

    if (a:0 == 2)
        let num = a:2
    else
        if (cmd == ":" || cmd == "all")
            let num = " -2"
        else
            let num = " -1"
        endif
    endif

    exec "redir! > " . s:histTempFile
    exec "history " . cmd . num
    redir END
endfunction
command -nargs=* Push call HistPush(<f-args>)
cabbrev push Push

" New command: pop
" Applies the globally accessible history command to the given commandline. The
" commandline may be one of ':', '/', '='. :help history.
function! HistPop (...)
    if (a:0 == 0)
        let cmd = ":"
    else
        let cmd = a:1
    endif

    let newCmd = system ("cat " . s:histTempFile)
    let newCmd = substitute (newCmd, "\#\\s*.* history", "", "g")
    let newCmd = substitute (newCmd, "[0-9]\\+", "", "")
    let newCmd = substitute (newCmd, nr2char (10), "", "g")
    let newCmd = substitute (newCmd, ">", "", "")
    let newCmd = substitute (newCmd, "^\\s*", "", "g")

    exec cmd . newCmd
    " Set the appropriate history register if possible.
    exec "silent! let @" . cmd . " = \"" . newCmd . "\""
endfunction
command -nargs=? Pop call HistPop(<f-args>)
cabbrev pop Pop
