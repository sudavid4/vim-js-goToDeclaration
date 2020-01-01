if !exists("g:fzf_defaultPreview")
    let g:fzf_defaultPreview = '$HOME/.dotfiles/config/nvim/plugged/fzf.vim/bin/preview.rb'
endif
if exists('$IGNORE_TESTS')
    let s:ignoreTests = $IGNORE_TESTS
else
    let s:ignoreTests = " --ignore '*.spec.js' --ignore '*.unit.js' --ignore '*.it.js' --ignore '*.*.spec.js' --ignore '*.*.*unit.js' --ignore '*.*.*it.js'"
endif
function! s:defaultPreview()
    " return fzf#vim#with_preview({'down': '100%'}, 'up:70%', 'ctrl-g')
    " return fzf#vim#with_preview({'down': '100%'}, 'up:50%', 'ctrl-e:execute:$DOTFILES/fzf/fhelp.sh {} > /dev/tty,ctrl-g')
    return {'options': ' --preview-window up:50% '.
                \'--preview "'''.g:fzf_defaultPreview.'''"\ -v\ {} '.
                \'--header ''CTRL-o - open without abort :: CTRL-s - toggle sort :: CTRL-g - toggle preview window'' '. 
                \'--bind ''ctrl-g:toggle-preview,'.
                \'ctrl-o:execute:$DOTFILES/fzf/fhelp.sh {} > /dev/tty''', 
                \'down': '100%'}

endfunction

let s:disablePing = 0
if !exists("*CursorPing")
    function! CursorPing(...)
        if s:disablePing
            return
        endif
        let _cursorline = &cursorline
        let _cursorcolumn = &cursorcolumn
        set cursorline 
        if !a:0
            set cursorcolumn
        endif
        redraw
        sleep 350m
        let &cursorline = _cursorline
        let &cursorcolumn = _cursorcolumn
    endfunction
endif

function! s:get_git_root()
    if exists('*fugitive#repo')
        try
            return fugitive#repo().tree()
        catch
        endtry
    endif
    let root = split(system('git rev-parse --show-toplevel'), '\n')[0]
    return v:shell_error ? '' : root
endfunction

if !exists("*FindFunction")
    function! FindFunction(functionName, ...)
        let gitRepo = s:get_git_root()
        let additionalParams = ( a:0 > 0 ) ? a:1 : ''
        " (?<=...) positive lookbehind: must constain
        " (?=...) positive lookahead: must contain
        let agcmd = '''(?<=function\s)'.a:functionName.'(?=\()|'.
                    \'\b'.a:functionName.'\s*:|'.
                    \'^\s*'.a:functionName.'\([^)]*\)\s*\{\s*$|'.
                    \'(?<=prototype\.)'.a:functionName.'(?=\s*=\s*function)|'.
                    \'(var|let|const|this\.)\s*'.a:functionName.'(?=\s*=\s*(function|\([^)]*\)\s*=>)\s*)'.
                    \''' -p '''.gitRepo.'/.gitignore'' '.
                    \additionalParams
        call fzf#vim#ag_raw(agcmd, s:defaultPreview(), 1)
    endfunction
endif

if !exists(":FindNoTestFunction")
    command! -nargs=+ FindNoTestFunction call FindFunction(<args>, s:ignoreTests)
endif

function! s:jsxStayedInSameLine(pos, wordUnderCursor)
    return expand('%') =~ '.jsx$' && a:pos[1] == getpos('.')[1] && a:wordUnderCursor != expand('<cword>')
endfunction

function! s:handleJsxStayedInSameLine(wordUnderCursor)
    let @/=a:wordUnderCursor
    execute '?'.a:wordUnderCursor
    set hlsearch
    call CursorPing(1)
endfunction

function! s:stayedInSamePosition(pos)
    return join(a:pos) == join(getpos('.'))
endfunction

function! s:goToCoreUtilsLib()
    if getcwd() !~ '\<santa\>'
        return 0
    endif
    let l:WordUnderCursor = expand('<cWORD>')
    if l:WordUnderCursor !~ '\<coreUtilsLib\>'
        return 0
    endif
    let l:santaCoreUtilsEntry = getcwd().'/node_modules/santa-core-utils/src/coreUtils/src/coreUtils.js'
    if !filereadable(l:santaCoreUtilsEntry)
        return 0
    endif
    let l:functionName = substitute(l:WordUnderCursor, '.*coreUtilsLib.\(\w\+\)\>.*', '\1', '')
    execute 'edit '.l:santaCoreUtilsEntry
    " normal! G
    let l:found = search('const \<'.l:functionName.'\>.*require(''.*\ze''') || search(':\s*\zs\<'.l:functionName.'\>')
    if l:found
        let s:disablePing = 1
        normal! $h
        call GoToDeclaration()
        let l:subFunctionName = substitute(l:WordUnderCursor, '.*coreUtilsLib.'.l:functionName.'.\(\w\+\)\>.*', '\1', '')
        if l:subFunctionName != l:WordUnderCursor
            call search(l:subFunctionName)
        endif
        let s:disablePing = 0
        call CursorPing()
        return 1
    endif
    return 1

endfunction
function! s:handleFunctionStayedInSamePosition(wordUnderCursor, isFunction)
    if s:goToCoreUtilsLib()
        return
    endif
    if getline('.') =~ '.*\s*require(.*)' && strpart(getline('.'), 0, getpos('.')[2]) =~ '\s*require(''[^'']*$' && strpart(getline('.'), getpos('.')[2]) =~ '[^'']*'')'
        call GoToFile()
        return
    endif
    let @/=a:wordUnderCursor
    "can't jump to definition with tern, do a search with ag + fzf
    if a:isFunction
        FindNoTestFunction(a:wordUnderCursor)
    else
        call fzf#vim#ag(expand('<cword>'), s:defaultPreview() , 1) 
        call IinOneMS()
    endif
    let g:searchedKeyword=a:wordUnderCursor
endfunction

function! s:isCommonJsRequire()
    return getline('.') =~ '^const.*=\s*require(.*)$'
endfunction

function! s:isEsModule()
    return getline('.') =~ '^\s*import'
endfunction
" import {isScreenWide} from '../../utils/utils';
function! s:goToEsModule()
    let l:pos = getpos('.')
    let l:wordUnderCursor = expand('<cword>')
    normal! 0
    call search('import.*[''"]', 'e')
    normal h
    TernDef
    if s:stayedInSamePosition(l:pos)
        call GoToFile()
    endif
    if !s:stayedInSamePosition(l:pos)
        normal! n
        call CursorPing()
    endif
endfunction
function! s:goToCommanJSModule()
    let l:pos = getpos('.')
    if strpart(getline('.'), 0, getpos('.')[2]) =~ '=\s*require('
        TernDef
    else
        call search('require(\(''\|"\).', 'e')
        let l:pos = getpos('.')
        silent TernDef
    endif
    if s:stayedInSamePosition(l:pos)
        call GoToFile()
    endif
    if !s:stayedInSamePosition(l:pos)
        call CursorPing()
    endif
endfunction

function! GoToFile()
    if getline('.') !~ '.*\s*require(.*)'
        echom 'early return'
        return
    endif
    if strpart(getline('.'), 0, getpos('.')[2]) =~ '\s*require('
        normal "fyi'
        let l:file = resolve(expand('%:h').'/'.@f)
        echom l:file
        if !filereadable(l:file) && filereadable(l:file.'.js')
            let l:file = l:file.'.js'
        endif
        if !filereadable(l:file) && filereadable(l:file.'.jsx')
            let l:file = l:file.'.jsx'
        endif
        echom l:file
        if filereadable(l:file)
            execute 'edit '.l:file
        endif
    endif
endfunction

let s:pos = []
function! GoToDeclaration()
    let s:pos = getpos('.')
    TSDef
    let s:callbacks = {
                \ 'on_exit': function('OldGoToDeclaration'),
                \ }
    let pid = jobstart('sleep 0.1', s:callbacks)
    let s:callbacks.pid = pid
endfunction

function! NormalI(...)
    call feedkeys('j')
endfunction
function! IinOneMS(...)
    let s:callbacks = {
                \ 'on_exit': function('NormalI'),
                \ }
    let pid = jobstart('sleep 0.1', s:callbacks)
    let s:callbacks.pid = pid
endfunction

function! OldGoToDeclaration(...)
    let l:pos = getpos('.')
    if s:pos != l:pos
        return
    endif
    let l:currFileName = expand('%')
    let l:lineFromCursorPosition = strpart(getline('.'), getpos('.')[2])
    let l:wordUnderCursor = expand('<cword>')
    let l:isFunction = match(l:lineFromCursorPosition , '^\(\w\|\s\)*(') + 1
    if !s:isEsModule()
        silent TernDef
    endif
    if s:isCommonJsRequire()
        echom 'siCommonjs'
        let @/='\v<'.l:wordUnderCursor.'>'
        call s:goToCommanJSModule()
    elseif s:isEsModule()
        echom 'esModule'
        let @/='\v<'.l:wordUnderCursor.'>'
        call s:goToEsModule()
    elseif s:jsxStayedInSameLine(l:pos, l:wordUnderCursor)
        call s:handleJsxStayedInSameLine(l:wordUnderCursor)
    elseif s:stayedInSamePosition(l:pos)
        call s:handleFunctionStayedInSamePosition(l:wordUnderCursor, l:isFunction)
    else
        let l:newCursorLine = getline('.')
        let l:newCurrFileName = expand('%')
        let l:regex = '^\s*' . l:wordUnderCursor . '\s*\(,\?\|\(:\s*' . l:wordUnderCursor . ',\?\)\)\s*$'
        echom l:regex
        if l:newCurrFileName != l:currFileName && match(l:newCursorLine, '\((\|=\)') < 0 && match(getline('.'), regex ) + 1
            let @/='\v<'.l:wordUnderCursor.'>'
            "we are inside a module.exports, maybe we can get to the line where the function is declared
            echom 'the line: ' . getline('.')
            call search(l:wordUnderCursor . '\s*\((\|=\)')
            " note that i changed this function in python to allow `add_jump_position` argument
            py3 tern_lookupDefinition("edit", add_jump_position=False)
        endif
        normal zz
        call CursorPing()
    endif
endfunction

" nmap <space>gf :call GoToFile()
