local logger = require("plenary.log").new({ plugin = "scratch", level = "info", use_console = "sync" })
local scandir = require("plenary.scandir")
local Job = require("plenary.job")
local Path = require("plenary.path")

local M = {}

local fn = vim.fn

local default_dirname = "default"

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

function M.input(opts, on_confirm, on_confirm_tbl, win_config)
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
    on_confirm(input_fname, on_confirm_tbl)
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
  if not M.file_exists(path) then
    local result = fn.mkdir(path, "p")
    logger.info("mkdir result: ", result)
  else
    logger.info("Already exists:", path)
    -- TODO: Check if it is a dir or a file. If a file OH NO! error! and let user know.
  end
end

M.setup = function(partial_config)
  M.config = vim.tbl_deep_extend("force", Default_config, partial_config or {})
  -- Make scratch dir if it doesn't exist
  if M.config.scratch_files_root_dir == nil or M.config.scratch_files_root_dir == "" then
    error("Must set 'scratch_files_root_dir' in config passed to setup function")
  end
  logger.info("scratch root: ", M.config.scratch_files_root_dir)

  M.config.default_dir = vim.fs.joinpath(M.config.scratch_files_root_dir, default_dirname)
  logger.info("Creating default dir: ", M.config.default_dir)
  M.create_dir(M.config.default_dir)
  M.get_scratch_files()
  local buff_dir = M.current_buffer_dirpath()
  M.is_git_dir(buff_dir)
  M.get_git_repo_path(buff_dir)
end

M.get_scratch_files = function()
  local scratch_files = scandir.scan_dir(M.config.scratch_files_root_dir, { hidden = true })
  --  for i, file_path in ipairs(scratch_files) do
  --  logger.info(i, file_path)
  -- end
  return scratch_files
end

M.current_buffer_dirpath = function()
  local current_buffer_path = vim.api.nvim_buf_get_name(0)
  local current_buff_dir = Path:new(current_buffer_path):parent()
  return tostring(current_buff_dir)
end

M.is_git_dir = function(path)
  local is_git = nil
  local git_command = "git"
  local rev_parse = "rev-parse"
  local is_git_work_tree_command = { rev_parse, "--is-inside-work-tree" }

  Job:new({
    command = git_command,
    args = is_git_work_tree_command,
    cwd = path,
    on_exit = function(j, return_val)
      local res = j:result()
      is_git = res[1] == "true"
    end,
  }):sync() -- or start()

  return is_git
end

M.get_git_repo_path = function(dirpath)
  local git_command = "git"
  local rev_parse = "rev-parse"
  local repo_path = nil
  local args = { rev_parse, "--show-toplevel" }

  Job:new({
    command = git_command,
    args = args,
    cwd = dirpath,
    on_exit = function(j, return_val)
      local res = j:result()
      repo_path = res[1]
    end,
  }):sync() -- or start()

  return repo_path
end

M.get_dirname = function(path_str)
  local path = Path:new(path_str)
  local _path_str = tostring(path)
  -- TODO: Ensure it is a dir!!  In use it is but check as well.
  -- TODO: Don't use hardcoded path sep
  local path_parts = vim.split(_path_str, "/")
  -- TODO: Handle no pathparts e.g. just root "/" passed in
  return path_parts[#path_parts]
end

-- Create scratch dir from scratch root if it doesn't exist.
-- Can be either default on setup or a new repo scratch dir.
M.create_scratch_dir = function(dirname)
  local scratch_dirpath = vim.fs.joinpath(M.config.scratch_files_root_dir, dirname)
  logger.info("creating scratch dir:", scratch_dirpath)
  M.create_dir(scratch_dirpath)
  return scratch_dirpath
end

M.create_file = function(fname)
  logger.info("creating ", fname)
end

M.get_new_scratch_file_dirname = function()
  local cur_buff_dirpath = M.current_buffer_dirpath()
  local dirname = nil
  if M.is_git_dir(cur_buff_dirpath) then
    local repo_name = M.get_dirname(M.get_git_repo_path(tostring(cur_buff_dirpath)))
    dirname = repo_name
  else
    dirname = default_dirname
  end
  return dirname
end

M.open_new_file = function(fname, data)
  if fname == nil then
    return
  end

  local dirname = data.dirname

  -- make dir if does not exist
  local new_scratch_file_dirpath = M.create_scratch_dir(dirname)

  if fname == "" then
    local default_fname = os.date("%Y_%m_%d__%H_%M_%S")
    fname = default_fname
  end

  local fpath = vim.fs.joinpath(new_scratch_file_dirpath, fname)

  local command = {
    M.config.open_method,
    fpath,
  }

  vim.cmd(vim.fn.join(command, " "))

  logger.info("New scratch file created at: " .. fpath)
end

M.new_scratch_file = function()
  local dirname = M.get_new_scratch_file_dirname()
  M.input({ prompt = "Create new in " .. dirname .. " scraches" }, M.open_new_file, { dirname = dirname }, {})
end

return M
