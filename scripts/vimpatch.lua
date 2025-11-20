--  Updates version.c list of applied Vim patches.
--
--  Usage:
--    VIM_SOURCE_DIR=~/neovim/.vim-src/ nvim -l ./scripts/vimpatch.lua

local nvim = vim.api

local function systemlist(...)
  local rv = nvim.nvim_call_function('systemlist', ...)
  local err = nvim.nvim_get_vvar('shell_error')
  local args_str = nvim.nvim_call_function('string', ...)
  if 0 ~= err then
    error('command failed: ' .. args_str)
  end
  return rv
end

local function vimpatch_sh_list_tokens()
  return systemlist({ { 'bash', '-c', 'scripts/vim-patch.sh -M' } })
end

-- Generates the lines to be inserted into the src/nvim/version.c
-- to populate the following:
-- - `Version`
-- - `vim_versions[]`
-- - `num_patches[]`
-- - `included_patchsets[]`
local function gen_version_c_lines()
  -- Sets of merged Vim x.y.zzzz patch numbers.
  local merged_patch_sets = {}
  local vim_version_str
  for _, token in ipairs(vimpatch_sh_list_tokens()) do
    local major_version, minor_version, patch_num = string.match(token, '^(%d+).(%d+).(%d+)$')
    local n = tonumber(patch_num)
    if n then
      local major_minor_version = major_version * 100 + minor_version
      if vim_version_str == nil then
        vim_version_str = major_version .. '.' .. minor_version
      end
      merged_patch_sets[major_minor_version] = merged_patch_sets[major_minor_version] or {}
      table.insert(merged_patch_sets[major_minor_version], n)
    end
  end

  local major_vim_versions = {}
  local num_patches = {}
  local patch_lines = {}
  for major_minor_version, patch_set in vim.spairs(merged_patch_sets) do
    table.insert(major_vim_versions, major_minor_version)
    table.insert(num_patches, #patch_set)
    table.insert(patch_lines, '  (const int[]) {  // ' .. major_minor_version)

    local patchset_set = {}
    for i = #patch_set, 1, -1 do
      local patch = patch_set[i]
      local next_patch = patch_set[i - 1]
      local patch_diff = patch - (next_patch or 0)
      table.insert(patchset_set, patch)

      -- guard against last patch or `make formatc`
      if #patchset_set > 15 or i == 1 or patch_diff > 1 then
        table.insert(patch_lines, '    ' .. table.concat(patchset_set, ', ') .. ',')
        patchset_set = {}
      end
      if i == 1 and patch > 0 then
        local line = '    // 0'
        if patch > 1 then
          line = line .. '-' .. (patch - 1)
        end
        table.insert(patch_lines, line)
      elseif patch_diff > 1 then
        local line = '    // ' .. (next_patch + 1)
        if patch_diff > 2 then
          line = line .. '-' .. (patch - 1)
        end
        table.insert(patch_lines, line)
      end
    end

    table.insert(patch_lines, '  },')
  end

  return vim_version_str, major_vim_versions, num_patches, patch_lines
end

local function patch_version_c()
  local vim_version_str, major_vim_versions, num_patches, patch_lines = gen_version_c_lines()

  nvim.nvim_command('silent noswapfile noautocmd edit src/nvim/version.c')
  nvim.nvim_command([[/^char \*Version =]])
  -- Replace the line.
  nvim.nvim_call_function('setline', {
    nvim.nvim_eval('line(".")'),
    'char *Version = "' .. vim_version_str .. '";',
  })
  nvim.nvim_command([[/^static const int vim_versions]])
  -- Replace the line.
  nvim.nvim_call_function('setline', {
    nvim.nvim_eval('line(".")'),
    'static const int vim_versions[] = { ' .. table.concat(major_vim_versions, ', ') .. ' };',
  })
  nvim.nvim_command([[/^static const int num_patches]])
  -- Replace the line.
  nvim.nvim_call_function('setline', {
    nvim.nvim_eval('line(".")'),
    'static const int num_patches[] = { ' .. table.concat(num_patches, ', ') .. ' };',
  })
  nvim.nvim_command([[/^static const int \*included_patchsets]])
  -- Delete the existing lines.
  nvim.nvim_command('silent normal! j0d/};\rk')
  -- Insert the lines.
  nvim.nvim_call_function('append', {
    nvim.nvim_eval('line(".")'),
    patch_lines,
  })
  nvim.nvim_command('silent write')
end

patch_version_c()
