-- local lfs = require("lfs")

local scandir = require("plenary.scandir")

local M = {}

local fn = vim.fn

---@param path string path to file or directory
---@return boolean
function M.file_exists(path)
  local _, error = vim.uv.fs_stat(path)
  return error == nil
end

Default_config = {
  scratch_files_root_dir = nil,
  -- open_method = "edit", -- for full screen
  open_method = "vsplit", -- for vertical split
  -- open_method = "split", -- for horizontal split
}

function M.window_center(input_width)
  return {
    relative = "win",
    row = vim.api.nvim_win_get_height(0) / 2 - 1,
    col = vim.api.nvim_win_get_width(0) / 2 - input_width / 2,
  }
end

function M.input(opts, on_confirm, win_config)
  local prompt = opts.prompt or "Input: "
  local default = opts.default or ""
  on_confirm = on_confirm or function() end

  -- Calculate a minimal width with a bit buffer
  local default_width = vim.str_utfindex(default) + 10
  local prompt_width = vim.str_utfindex(prompt) + 10
  local input_width = default_width > prompt_width and default_width or prompt_width

  local default_win_config = {
    focusable = true,
    style = "minimal",
    border = "rounded",
    width = input_width,
    height = 1,
    title = prompt,
  }

  -- Apply user's window config.
  win_config = vim.tbl_deep_extend("force", default_win_config, win_config)

  win_config = vim.tbl_deep_extend("force", win_config, M.window_center(win_config.width))

  -- Create floating window.
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, win_config)
  vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { default })

  -- Put cursor at the end of the default value
  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(window, { 1, vim.str_utfindex(default) + 1 })

  -- Enter to confirm
  vim.keymap.set({ "n", "i", "v" }, "<cr>", function()
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)
    vim.cmd("stopinsert")
    -- need to return "" instead of nil as is done with esc or q to close so we know to use default filename
    local input_fname = lines[1] or ""
    on_confirm(input_fname)
    vim.api.nvim_win_close(window, true)
  end, { buffer = buffer })

  -- Esc or q to close
  vim.keymap.set("n", "<esc>", function()
    on_confirm(nil)
    vim.cmd("stopinsert")
    vim.api.nvim_win_close(window, true)
  end, { buffer = buffer })
  vim.keymap.set("n", "q", function()
    on_confirm(nil)
    vim.cmd("stopinsert")
    vim.api.nvim_win_close(window, true)
  end, { buffer = buffer })
end

M.create_dir = function(path)
  print("creating dir: " .. path, "...")
  if not M.file_exists(path) then
    print("does not exist, making dir: ", path)
    local result = fn.mkdir(path, "p")
    print("mkdir result: ", result)
  else
    print("Already exists:", path)
    -- TODO: Check if it is a dir or a file. If a file OH NO! error! and let user know.
  end
end

M.setup = function(partial_config)
  M.config = vim.tbl_deep_extend("force", Default_config, partial_config or {})
  -- Make scratch dir if it doesn't exist
  if M.config.scratch_files_root_dir == nil or M.config.scratch_files_root_dir == "" then
    error("Must set 'scratch_files_root_dir' in config passed to setup function")
  end
  print("scratch root: ", M.config.scratch_files_root_dir)

  M.config.default_dir = vim.fs.joinpath(M.config.scratch_files_root_dir, "default")
  print("Creating default dir: ", M.config.default_dir)
  M.create_dir(M.config.default_dir)
  M.get_scratch_files()
end

M.get_scratch_files = function()
  print("get scratch files")
  local scratch_files = scandir.scan_dir(M.config.scratch_files_root_dir, { hidden = true })
  for i, file_path in ipairs(scratch_files) do
    print(i, file_path)
  end
  return scratch_files
end

M.cwd = function()
  local cwd = ""
  print("cwd: ", cwd)
  return cwd
end

M.is_git_dir = function(path)
  local is_git = false
  print("is git_dir", path, is_git)
end

M.get_repo = function() end

M.create_git_dir = function()
  print("create_git_dir")
end

M.create_file = function(fname)
  print("creating ", fname)
end

M.open_new_file = function(fname)
  if fname == nil then
    return
  end

  -- TODO: get git repo if we are in one

  if fname == "" then
    local default_fname = os.date("%Y_%m_%d__%H_%M_%S")
    fname = default_fname
  end

  local fpath = vim.fs.joinpath(M.config.default_dir, fname)

  local command = {
    M.config.open_method,
    fpath,
  }

  print("command: ", command)
  vim.cmd(vim.fn.join(command, " "))

  print("New scratch file created at: " .. fpath)
end

M.new_scratch_file = function()
  --vim.ui.input({}, print)

  local dirname = vim.fs.dirname(M.config.default_dir)
  M.input({ prompt = "New scratch file in " .. dirname }, M.open_new_file, {})

  --  if not fname then
  -- if not M.file_exists(path) then
  --print("does not exist, making dir: ", fpath)
  --local result = fn.
  --print("result: ", result)
  --else
  --  print("Already exists:", fpath)
  -- end

  -- end
end

return M
