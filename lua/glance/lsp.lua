local utils = require('glance.utils')

local M = {}

local function create_handler(method)
  return function(bufnr, params, cb)
    local _client_request_ids, cancel_all_requests, client_request_ids

    _client_request_ids, cancel_all_requests = vim.lsp.buf_request(
      bufnr,
      method.lsp_method,
      params,
      function(err, result, ctx)
        if not client_request_ids then
          -- do a copy of the table we don't want
          -- to mutate the original table
          client_request_ids =
            vim.tbl_deep_extend('keep', _client_request_ids, {})
        end

        -- Don't log an error when LSP method is non-standard
        if err and not method.non_standard then
          utils.error(
            ('An error happened requesting %s: %s'):format(
              method.label,
              err.message
            )
          )
        end

        if result == nil or vim.tbl_isempty(result) then
          client_request_ids[ctx.client_id] = nil
        else
          cancel_all_requests()
          result = (
            vim.fn.has('nvim-0.10.0') == 1 and vim.islist(result)
            or vim.tbl_islist(result)
          )
              and result
            or { result }

          return cb(result, ctx)
        end

        if vim.tbl_isempty(client_request_ids) then
          cb({})
        end
      end
    )
  end
end

---@alias GlanceMethod
--- | '"type_definitions"'
--- | '"implementations"'
--- | '"definitions"'
--- | '"references"'

M.methods = {
  type_definitions = {
    label = 'type definitions',
    lsp_method = 'textDocument/typeDefinition',
  },
  implementations = {
    label = 'implementations',
    lsp_method = 'textDocument/implementation',
  },
  definitions = {
    label = 'definitions',
    lsp_method = 'textDocument/definition',
  },
  references = {
    label = 'references',
    lsp_method = 'textDocument/references',
  },
}

function M.setup()
  for key, method in pairs(M.methods) do
    M.methods[key].handler = create_handler(method)
  end
end

local function client_position_params(params)
  local win = vim.api.nvim_get_current_win()

  return function(client)
    local ret = vim.lsp.util.make_position_params(win, client.offset_encoding)
    return vim.tbl_extend('force', ret, params or {})
  end
end

local function make_position_params(params)
  if vim.fn.has('nvim-0.11') ~= 0 then
    return client_position_params(params)
  end

  local ret = vim.lsp.util.make_position_params(0)
  return vim.tbl_extend('force', ret, params or {})
end

function M.request(name, bufnr, cb)
  if M.methods[name] then
    local params =
      make_position_params({ context = { includeDeclaration = true } })
    M.methods[name].handler(bufnr, params, cb)
  else
    utils.error(("No such method '%s'"):format(name))
  end
end

return M
