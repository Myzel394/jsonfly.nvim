# jsonfly.nvim

Fly through your JSON files with ease. 
Search ✨ blazingly fast ✨ for keys via [Telescope](https://github.com/nvim-telescope/telescope.nvim), and navigate through your JSON structure with ease.

json(fly) is a Telescope extension that will show you all keys (including nested ones) in your JSON files and allow you to search and jump to them quickly.

## Installation

Install with your favorite plugin manager, for example with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "nvim-telescope/telescope.nvim",
    dependencies = {
        -- "Myzel394/telescope-last-positions",
        -- Other dependencies
        -- ..
        "Myzel394/jsonfly.nvim",
    },
},
```

Load the extension with:

```lua
require("telescope").load_extension("jsonfly")
```

## Usage

Go to a JSON file and run:

```lua
:Telescope jsonfly
```

