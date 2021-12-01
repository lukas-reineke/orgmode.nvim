local Files = require('orgmode.parser.files')
local config = require('orgmode.config')
local utils = require('orgmode.utils')
local ts_utils = require('nvim-treesitter.ts_utils')

local cookie_namespace = vim.api.nvim_create_namespace('orgmode-cookies')
local cookie_query = vim.treesitter.parse_query('org', '(cookie) @cookie')
local checkbox_query = vim.treesitter.parse_query('org', '(list (listitem (checkbox) @checkbox))')
local list_in_body_query = vim.treesitter.parse_query('org', '(body (list) @list)')
local headline_cookie_query = vim.treesitter.parse_query('org', '(headline (cookie) @cookie)')

local function load_code_blocks()
  local file = vim.api.nvim_buf_get_name(0)
  if not file or file == '' then
    return
  end

  local orgfile = Files.get(file)
  if not orgfile then
    return
  end

  for _, ft in ipairs(orgfile.source_code_filetypes) do
    vim.cmd(string.format([[silent! syntax include @orgmodeBlockSrc%s syntax/%s.vim]], ft, ft))
    vim.cmd([[unlet! b:current_syntax]])
  end

  for _, ft in ipairs(orgfile.source_code_filetypes) do
    vim.cmd(
      string.format(
        [[syntax region orgmodeBlockSrc%s matchgroup=comment start="^\s*#+BEGIN_SRC\ %s\s*.*$" end="^\s*#+END_SRC\s*$" keepend contains=@orgmodeBlockSrc%s,org_block_delimiter]],
        ft,
        ft,
        ft
      )
    )
  end
end

local function add_todo_keywords_to_spellgood()
  local todo_keywords = config:get_todo_keywords().ALL
  for _, todo_keyword in ipairs(todo_keywords) do
    vim.cmd(string.format('silent! spellgood! %s', todo_keyword))
  end
end

local function _get_cookie_checked_and_total(parent)
  local parent_type = parent:type()
  local start_row, _, end_row, _ = parent:range()
  local checked, total = 0, 0
  for _, checkbox in checkbox_query:iter_captures(parent, 0, start_row, end_row + 1) do
    local closest_parent = utils.get_closest_parent_of_type(checkbox, parent_type)
    if closest_parent and closest_parent == parent then -- only count direct children
      local checkbox_text = vim.treesitter.get_node_text(checkbox, 0)
      if checkbox_text:match('%[[x|X]%]') then
        checked = checked + 1
      end
      total = total + 1
    end
  end

  return checked, total
end

local function _update_checkbox_text(checkbox, checked_children, total_children)
  local checkbox_text
  if total_children == nil then -- if the function is called without child information, we toggle the current value
    checkbox_text = vim.treesitter.get_node_text(checkbox, 0)
    if checkbox_text:match('%[[xX]%]') then
      checkbox_text = '[ ]'
    else
      checkbox_text = '[X]'
    end
  else
    checkbox_text = '[ ]'
    if checked_children == total_children then
      checkbox_text = '[x]'
    elseif checked_children > 0 then
      checkbox_text = '[-]'
    end
  end

  utils.update_node_text(checkbox, { checkbox_text })
end

local function _update_cookie_text(cookie, checked_children, total_children)
  local cookie_text = vim.treesitter.get_node_text(cookie, 0)

  if total_children == nil then
    checked_children, total_children = 0, 0
  end

  local new_cookie
  if cookie_text:find('/') then
    new_cookie = string.format('[%d/%d]', checked_children, total_children)
  else
    if total_children > 0 then
      new_cookie = string.format('[%d%%%%]', (100 * checked_children) / total_children)
    else
      new_cookie = '[0%%%]'
    end
  end
  cookie_text = cookie_text:gsub('%[.*%]', new_cookie)
  utils.update_node_text(cookie, { cookie_text })
end

local function update_checkbox(node, checked_children, total_children)
  if not node then
    node = utils.get_closest_parent_of_type(ts_utils.get_node_at_cursor(0), 'listitem')
    if not node then
      return
    end
  end

  local checkbox
  local cookie
  for child in node:iter_children() do
    if child:type() == 'checkbox' then
      checkbox = child
    elseif child:type() == 'itemtext' then
      local c_child = child:named_child(0)
      if c_child and c_child:type() == 'cookie' then
        cookie = c_child
      end
    end
  end

  if checkbox then
    _update_checkbox_text(checkbox, checked_children, total_children)
  end

  if cookie then
    _update_cookie_text(cookie, checked_children, total_children)
  end

  local listitem_parent = utils.get_closest_parent_of_type(node:parent(), 'listitem')
  if listitem_parent then
    local list_parent = utils.get_closest_parent_of_type(node, 'list')
    local checked, total = _get_cookie_checked_and_total(list_parent)
    return update_checkbox(listitem_parent, checked, total)
  end

  local section = utils.get_closest_parent_of_type(node:parent(), 'section')
  if section then
    local list_parent = utils.get_closest_parent_of_type(node, 'list')
    local checked, total = _get_cookie_checked_and_total(list_parent)
    local start_row, _, end_row, _ = section:range()
    for _, headline_cookie in headline_cookie_query:iter_captures(section, 0, start_row, end_row + 1) do
      _update_cookie_text(headline_cookie, checked, total)
    end
  end
end

return {
  load_code_blocks = load_code_blocks,
  add_todo_keywords_to_spellgood = add_todo_keywords_to_spellgood,
  update_checkbox = update_checkbox,
}
