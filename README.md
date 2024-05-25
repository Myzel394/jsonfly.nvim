# jsonfly.nvim

Fly through your JSON, XML and YAML files with ease. 
Search ✨ blazingly fast ✨ for keys via [Telescope](https://github.com/nvim-telescope/telescope.nvim), navigate through your JSON structure with ease, and insert deeply nested keys without fear.

json(fly) is a Telescope extension that will show you all keys (including nested ones) in your JSON (or XML or YAML) files and allow you to search and jump to them quickly.
It's completely customizable and even supports highlighting of the values.

<img src="docs/horizontal_layout.png">

## Features

* 🔍 Search for deeply nested keys - `expo.android.imageAsset.0.uri`
* 👀 Insert nested keys quickly into your buffer
* 🎨 See values with their correct syntax highlighting (numbers, strings, booleans, null; configurable)
* 💻 Use your LSP or the built-in JSON parser
* 🗑 Values automatically cached for faster navigation
* 🫣 Automatic concealment based on your configuration
* 📐 Everything completely customizable!

## Installation

Install with your favorite plugin manager, for example with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "nvim-telescope/telescope.nvim",
    dependencies = {
        -- "Myzel394/easytables.nvim",
        -- "Myzel394/telescope-last-positions",
        -- Other dependencies
        -- ..
        "Myzel394/jsonfly.nvim",
    }
}
```

Here's how I load it with lazy.nvim with lazy-loading and `<leader>j` as the keymap :)

```lua
{
    "nvim-telescope/telescope.nvim",
    dependencies = {
        "Myzel394/jsonfly.nvim",
    },
    keys = {
        {
            "<leader>j",
            "<cmd>Telescope jsonfly<cr>",
            desc = "Open json(fly)",
            ft = { "json", "xml", "yaml" },
            mode = "n"
        }
    }
}
```

Load the extension with:

```lua
require("telescope").load_extension("jsonfly")
```

## Usage

Go to a JSON file and run:

```lua
:Telescope jsonfly


Now you can search for keys, subkeys, part of keys etc.

### Inserting Keys

JSON(fly) supports inserting your current search prompt into your buffer.

If you search for a key that doesn't exist you can add it to your buffer by pressing `<C-a>` (CTRL + a).

You can enter nested keys, arrays, indices, subkeys etc. JSON(fly) will automatically manage everything for you.

The following schemas are valid:

* Nested keys: `expo.android.imageAssets.`
* Array indices: `expo.android.imageAssets.0.uri`, `expo.android.imageAssets.3.uri`, `expo.android.imageAssets.[3].uri`
* Escaping: `expo.android.tests.\0.name` -> Will not create an array but a key with the name `0`

Please note: JSON(fly) is intended to be used with **human-readable** JSON files. Inserting keys won't work with minified JSON files.

## See also

* [jsonpath.nvim](https://github.com/phelipetls/jsonpath.nvim) - Copy JSON paths to your clipboard
```

## Configuration

Edit jsonfly like any other Telescope extension:

```lua
require"telescope".setup {
    extensions = {
        jsonfly = {
            -- Your configuration here
        }
    }
}
```

Please see [jsonfly.lua](https://github.com/Myzel394/jsonfly/blob/main/lua/telescope/_extensions/jsonfly.lua) for the default configuration.
The first comment in the file contains a list of all available options.

### Example: Vertical layout

<img src="docs/vertical_layout.png">

```lua
require"telescope".setup {
    extensions = {
        jsonfly = {
            mirror = true,
            layout_strategy = "vertical",
            layout_config = {
                mirror = true,
                preview_height = 0.65,
                prompt_position = "top",
            },
            key_exact_length = true
        }
    }
}
```

### Example: Horizontal layout

<img src="docs/horizontal_layout.png">

```lua
require"telescope".setup {
    extensions = {
        jsonfly = {
            layout_strategy = "horizontal",
            prompt_position = "top",
            layout_config = {
                mirror = false,
                prompt_position = "top",
                preview_width = 0.45
            }
        }
    }
}
```

### Example: Waterfall keys

<img src="docs/waterfall_keys.png">

```lua
require"telescope".setup {
    extensions = {
        jsonfly = {
            subkeys_display = "waterfall"
        }
    }
}
```

## Acknowledgements

- JSON parsing is done with [Jeffrey Friedl's JSON library](http://regex.info/blog/lua/json)

