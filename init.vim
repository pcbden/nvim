let g:loaded_matchparen=1
let g:termdebugger = "gdb-multiarch"
let g:termdebug_use_prompt = 0
let g:termdebug_wide = 1
if !exists('g:loaded_termdebug')
  packadd termdebug
endif
call plug#begin('~/.local/share/nvim/plugged')
    Plug 'neoclide/coc.nvim', {'branch': 'release'}
    Plug 'nvim-lua/plenary.nvim'
    Plug 'nvim-telescope/telescope.nvim'
    Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
  call plug#end()
  tnoremap <Esc> <C-\><C-n>
  nnoremap ZZ <Nop>
  nnoremap ZQ <Nop>

  " create folds (method), but don't close them by default
  
  
  " --- FOLDS (Tree-sitter) ---
  "set foldmethod=indent
  set foldmethod=expr
  "set foldexpr=nvim_treesitter#foldexpr()
  set foldexpr=v:lua.vim.treesitter.foldexpr()
  set foldenable
  set foldlevel=99
  set foldlevelstart=99

  set tabstop=2
  set shiftwidth=2
  set expandtab
  set guicursor=
  
  le :o_onfig_home = '~/.config/nvim'

syntax on
  colorscheme slate
  set encoding=utf-8
  set nu
  set rnu
  filetype plugin indent on

  " Set C++ file type
  autocmd BufNewFile,BufRead *.cpp set filetype=cpp

  " Compile and run C++ program in subshell
  " Coc.nvim default keybindings for C++ specific features
  " Go to definition
  nmap <silent> gd <Plug>(coc-definition)
  " Go to declaration
  nmap <silent> gy <Plug>(coc-declaration)
  " Go to implementation
  nmap <silent> gi <Plug>(coc-implementation)
  " Go to type definition
  nmap <silent> gt <Plug>(coc-type-definition)
  " Find references
  nmap <silent> gr <Plug>(coc-references)



  function! CompileAndRun()
    let fileName = expand('%')
    if fileName =~ '\.cpp$'
      let exeName = substitute(fileName, '\.cpp$', '', '')
      execute 'w | !g++ -std=c++11 -Wall -Wextra -Wpedantic -O2 -o ' . exeName . ' ' . fileName
      if v:shell_error == 0
        let cmd = "x-terminal-emulator -e bash -c './" . exeName . "; read -p \"Press enter to exit...\"'"
        call system(cmd)
        redraw!
      endif
    else
      echo 'Not a C++ file'
    endif
  endfunction

  inoremap <silent><expr> <CR> pumvisible() ? coc#_select_confirm() : "\<C-g>u\<CR>"
  inoremap <silent><expr> <Tab> coc#pum#visible() ? "\<C-n>" :
      \ coc#expandableOrJumpable() ? "\<C-r>=coc#rpc#request('doKeymap', ['snippets-expand-jump',''])\<CR>" :
      \ "\<Tab>"

" Custom keybindings in Lua
lua << EOF

vim.opt.splitright = true

vim.g.mapleader = " "

local function pfn()
  local cwd = vim.fn.getcwd()
  return vim.fn.fnamemodify(cwd, ":t")
end

vim.keymap.set("n", "<leader>m", function()
  vim.cmd("!cmake .")
end)

vim.keymap.set("n", "<leader>r", function()
  vim.cmd("CocRestart")
end)

vim.keymap.set("n", "<leader>rr", function()
  vim.fn.system("st-info --probe")
  print("st-info --probe")
end)

vim.keymap.set("n", "<leader>y", function()
  vim.cmd("bufdo bdelete")
end)

vim.keymap.set("n", "<leader>bw", function()
  vim.cmd("!bear -- make -j16 1>/dev/null")
  print(vim.v.shell_error)
end)

vim.keymap.set("n", "<leader>b", function()
  vim.fn.system("bear -- make -j16 1>/dev/null 2>/dev/null")
  print(vim.v.shell_error)
end)

vim.keymap.set("n", "<leader>e", function()
  vim.cmd("Ex")
end)

vim.keymap.set("n", "<leader>l", function()
  vim.cmd("Telescope buffers")
end)

vim.keymap.set("n", "<leader>i", function()
  vim.cmd("!bash ~/.config/nvim/mem_info.sh build/" .. pfn() .. ".elf" .. " build/" .. pfn() .. ".map")
end)

vim.keymap.set("n", "<leader>w", function()
  vim.cmd("wa")
end)

vim.keymap.set("n", "<leader>c", function()
  vim.cmd("!make clean")
end)

vim.keymap.set("n", "<leader>t", function()
  vim.cmd("call CocActionAsync('format')")
end)

vim.keymap.set("n", "<leader>s", function()
  vim.fn.system("echo 1 | sudo tee /sys/module/hid_apple/parameters/swap_fn_leftctrl")
end)

vim.keymap.set("n", "<leader>a", function()
  vim.fn.system("echo 0 | sudo tee /sys/module/hid_apple/parameters/swap_fn_leftctrl")
end)

-- Start debug session: OpenOCD + GDB

require('telescope').setup{
  defaults = {
    layout_config = {
      prompt_position = "top",
    },
    sorting_strategy = "ascending",
    file_ignore_patterns = {"^build/"},
  },
  pickers = {
    live_grep = {
      additional_args = function()
        return {"--glob=!build/**"}
      end,
    },
  }
}

-- Example keybindings
vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files)
vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep)
vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers)
vim.keymap.set('n', '<leader>fh', require('telescope.builtin').help_tags)


vim.keymap.set("n", "<leader>x", function()
local brk = 'b ' .. vim.fn.expand('%:t') .. ':' .. vim.fn.line('.')
print(brk)
vim.fn.setreg('"',brk)
vim.fn.setreg('+',brk)
end)

vim.keymap.set("n", "<leader>u", function()
  local name = "build/" .. pfn()
  --local name = pfn()
  vim.cmd("!arm-none-eabi-objcopy -O binary " .. name .. ".elf " .. name .. ".bin")
  vim.cmd("!st-info --probe")
  vim.cmd("!st-flash write " .. name .. ".bin 0x08000000 && st-flash reset")
end)

vim.keymap.set("n", "<leader>da", function()
  vim.cmd("Break")
end)

local pre_debug_buffers = {}

vim.keymap.set("n", "<leader>d", function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    pre_debug_buffers[buf] = true
  end

  local elf = "build/" .. pfn() .. ".elf"
  vim.cmd("Termdebug " .. elf)
  vim.defer_fn(function()
    vim.cmd("wincmd w")
    vim.cmd("close")
    vim.cmd("call TermDebugSendCommand('target extended-remote :3333')")
    vim.cmd("call TermDebugSendCommand('monitor reset halt')")
    vim.cmd("call TermDebugSendCommand('shell clear')")
    vim.cmd("vertical resize 60")
  end, 1000)
end)

vim.keymap.set("n", "<leader>q", function()
  vim.fn.jobstart("pkill gdb-multiarch")
  vim.defer_fn(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not pre_debug_buffers[buf] then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    pre_debug_buffers = {}
  end, 200)
end)


EOF

