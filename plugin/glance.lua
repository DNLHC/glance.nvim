vim.api.nvim_create_user_command('Glance', function(event)
  if event.args == 'resume' then
    require('glance').actions.resume()
  else
    require('glance').open(event.args)
  end
end, {
  nargs = 1,
  complete = function(arg)
    local list = vim.tbl_keys(require('glance.lsp').methods)
    table.insert(list, 'resume')

    return vim.tbl_filter(function(s)
      return string.match(s, '^' .. arg)
    end, list)
  end,
})
