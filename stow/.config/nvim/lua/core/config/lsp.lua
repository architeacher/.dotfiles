local M = {}

M.setup = function()
    local lsp = require("lsp-zero")

    lsp.set_sign_icons()

    -- LSP settings.
    --  This function gets run when an LSP connects to a particular buffer.
    lsp.on_attach = function(_, bufnr)
        -- Use telescope for lsp navigation
        local builtin = require("telescope.builtin")

        -- Easily define mappings specific for LSP related items.
        -- It sets the mode, buffer and description for us each time.
        local nmap = function(keys, func, desc)
            if desc then
                desc = "LSP: " .. desc
            end

            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc, remap = false })
        end

        nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
        nmap("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
        nmap("gI", vim.lsp.buf.implementation, "[G]oto [I]mplementation")
        nmap("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
        nmap("<leader>D", vim.lsp.buf.type_definition, "Type [D]efinition")
        nmap("<leader>ds", builtin.lsp_document_symbols, "[D]ocument [S]ymbols")
        nmap("<leader>ws", builtin.lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")
        nmap("gr", builtin.lsp_references, "[G]oto [R]eferences")

        -- See `:help K` for why this keymap
        nmap("K", vim.lsp.buf.hover, "Hover Documentation")
        nmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

        -- Lesser used LSP functionality
        nmap("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
        nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
        nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
        nmap("<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, "[W]orkspace [L]ist Folders")

        -- Create a command `:Format` local to the LSP buffer
        vim.api.nvim_buf_create_user_command(bufnr, "Format", function(_)
            if vim.lsp.buf.format then
                vim.lsp.buf.format()
            elseif vim.lsp.buf.formatting then
                vim.lsp.buf.formatting()
            end
        end, { desc = "Format current buffer with LSP" })
    end

    -- Enable the following language servers
    -- Feel free to add/remove any LSPs that you want here. They will automatically be installed
    local servers = {
        bashls = true,

        clangd = true,

        gopls = {
            settings = {
                gopls = {
                    hints = {
                        assignVariableTypes = true,
                        compositeLiteralFields = true,
                        compositeLiteralTypes = true,
                        constantValues = true,
                        functionTypeParameters = true,
                        parameterNames = true,
                        rangeVariableTypes = true,
                    },
                },
            },
        },

        pyright = true,

        rust_analyzer = true,

        lua_ls = true,

        cssls = true,
        svelte = true,
        templ = true,

        jsonls = {
            settings = {
                json = {
                    schemas = require("schemastore").json.schemas(),
                    validate = { enable = true },
                },
            },
        },

        yamlls = {
            settings = {
                yaml = {
                    schemaStore = {
                        enable = false,
                        url = "",
                    },
                    schemas = require("schemastore").yaml.schemas(),
                },
            },
        },
    }

    local servers_to_install = vim.tbl_filter(function(key)
        local t = servers[key]
        if type(t) == "table" then
            return not t.manual_install
        else
            return t
        end
    end, vim.tbl_keys(servers))

    local ensure_installed = {
        -- Replace these with the servers you want to install
        "eslint",
        "dockerls",
        "html",
        "marksman",
        -- "tailwind-language-server",
        "tsserver",

    }

    vim.list_extend(ensure_installed, servers_to_install)

    -- Setup mason so it can manage external tooling
    require("mason").setup()
    -- Ensure the servers above are installed.

    local lsp_config = require "lspconfig"
    require("mason-lspconfig").setup {
        ensure_installed = ensure_installed,
        handlers = {
            lsp.default_setup,
            lua_ls = function()
                local lua_opts = lsp.nvim_lua_ls()
                lsp_config.lua_ls.setup(lua_opts)
            end,
        },

    }
    --require("mason-tool-installer").setup { ensure_installed = ensure_installed }

    -- nvim-cmp supports additional completion capabilities
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    if pcall(require, "cmp_nvim_lsp") then
        capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)
    end

    for lsp_name, config in pairs(servers) do
        if config == true then
            config = {}
        end
        config = vim.tbl_deep_extend("force", {}, {
            capabilities = capabilities,
        }, config)

        lsp_config[lsp_name].setup(config)
    end

    require("rust-tools").setup({
        tools = {
            inlay_hints = {
                auto = true,
            },
        },
        server = {
            capabilities = capabilities,
            settings = {
                ["rust-analyzer"] = {
                    assist = {
                        importGranularity = "module",
                        importPrefix = "by_self",
                    },
                    cargo = {
                        loadOutDirsFromCheck = true,
                    },
                    procMacro = {
                        enable = true,
                    },
                    rustfmt = {
                        extraArgs = { "+nightly" },
                    },
                },
            },
        }
    })

    -- Autoformatting Setup
    require("conform").setup {
        formatters_by_ft = {
            lua = { "stylua" },
        },
    }

    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'sh',
        callback = function()
            vim.lsp.start({
                name = 'bash-language-server',
                cmd = { 'bash-language-server', 'start' },
            })
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePre", {
        callback = function(args)
            require("conform").format {
                bufnr = args.buf,
                lsp_fallback = true,
                quiet = true,
            }
        end,
    })
end

M.setup()

return M
