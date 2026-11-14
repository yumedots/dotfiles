local options = YUDAE_PLUGIN.options

hl.config({
    plugin = {
        template_hypr = {
            enabled = options.enabled ~= false,
        },
    },
})
