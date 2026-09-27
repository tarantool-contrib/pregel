--- Value copying.
--
-- @module pregel.utils.copy

local msgpack = require('msgpack')

local strict = require('pregel.utils.strict')

--- Recursively copy a value.
--
-- Non-table values are returned as they are. Metatables are not copied and
-- cycles are not detected: the values this is used for (aggregator defaults)
-- are plain trees, and a cyclic one recurses until the stack runs out.
--
-- @param orig any value
-- @return a copy sharing no table with `orig`
-- @function deep
local function deep(orig)
    if type(orig) ~= 'table' then
        return orig
    end
    local copy = {}
    for key, value in pairs(orig) do
        copy[key] = deep(value)
    end
    return copy
end

--- A copy of `value` that shares no table with it, as the wire would carry it.
--
-- The vertex API hands tables to the runtime, which used to hold them by
-- reference until something serialised them: the flush at the end of the
-- superstep, or -- with the table queue engine and a receiver on this worker --
-- nothing at all, so the receiver's queue held the sender's own table.
-- Capturing when the call is made is what lets the caller reuse or change the
-- table as soon as the call returns, and what gives a receiver a table of its
-- own (docs/api-design.md section 0, D8).
--
-- A msgpack round trip rather than a deep copy: the value then comes out as the
-- space engine and net.box would make it, whichever engine carries it. Tables
-- are not the only values that can be changed in place -- cdata can too, and a
-- datetime's set() rewrites the very object -- so cdata takes the round trip
-- as well: a datetime, decimal or uuid comes back as a new object of its kind.
-- Strings, numbers and booleans cannot be changed through a reference and are
-- returned as they are.
--
-- @param value the payload
-- @return the payload, or a copy of it when it is a table or cdata
-- @function capture
local function capture(value)
    local kind = type(value)
    if kind ~= 'table' and kind ~= 'cdata' then
        return value
    end
    local copy = msgpack.decode(msgpack.encode(value))
    return copy
end

return strict.strictify({
    deep    = deep,
    capture = capture,
})
