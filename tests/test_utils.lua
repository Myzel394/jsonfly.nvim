local lu = require"luaunit.luaunit"
local utils = require"lua.jsonfly.utils"

function testBasicKey()
    local key = "foo.bar"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "bar",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end

function testArrayKey()
    local key = "foo.0.bar"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        },
        {
            type = "array_wrapper",
        },
        {
            type = "array_index",
            key = 0,
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "bar",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end

function testNestedArrayKey()
    local key = "foo.0.bar.1.baz"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        },
        {
            type = "array_wrapper",
        },
        {
            type = "array_index",
            key = 0,
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "bar",
        },
        {
            type = "array_wrapper",
        },
        {
            type = "array_index",
            key = 1,
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "baz",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end

function testEscapedArrayDoesNotCreateArray()
    local key = "foo.\\0.bar"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "0",
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "bar",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end

function testBracketArrayKey()
    local key = "foo.[0].bar"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        },
        {
            type = "array_wrapper",
        },
        {
            type = "array_index",
            key = 0,
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "bar",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end

function testRootArrayKey()
    local key = "0.foo"
    ---@type KeyDescription[]
    local EXPECTED = {
        {
            type = "array_wrapper",
        },
        {
            type = "array_index",
            key = 0,
        },
        {
            type = "object_wrapper",
        },
        {
            type = "key",
            key = "foo",
        }
    }

    local descriptor = utils:extract_key_description(key)

    lu.assertEquals(descriptor, EXPECTED)
end


os.exit( lu.LuaUnit.run() )

