--- What code running inside an RPC may do on the caller's behalf.
--
-- Tarantool's behaviour rather than pregel's, pinned because the v2 design
-- rests on it (docs/api-design.md section 0, D3): an app creates the spaces it
-- owns from job-side code, through a setuid function that pregel registers in
-- _func, and each space belongs to the job user, so nothing is ever granted.
-- Every assertion is made as the job user, inside a call it was granted, over
-- a real net.box connection -- which is where compute functions and loaders
-- run.
--
-- It is also what retired the two-phase prepare/open of the earlier drafts
-- (section 3.19 of the same document): in-process code can switch its
-- effective user, so the job user's missing DDL privilege is not a wall.

local t = require('luatest')
local net_box = require('net.box')

local box_helper = require('test.helpers.box')

local g = t.group('rpc_privileges')

local USER     = 'rpc_privileges_peer'
local PASSWORD = 'secret'
local ENTRY    = 'rpc_privileges_entry'
local DOOR     = 'rpc_privileges_door'
local PREFIX   = 'rpc_privileges_app_'

--- The door: creates a space in the namespace, owned by whoever called it.
--
-- box.session.uid() is the session's user even inside a setuid function, whose
-- effective user is the function's owner -- which is what makes the caller the
-- owner of a space the owner of the function creates.
local function door(name)
    if name:sub(1, #PREFIX) ~= PREFIX then
        error('outside the namespace: ' .. name, 0)
    end
    local space = box.schema.space.create(name, {user = box.session.uid()})
    space:create_index('primary')
    return box.session.effective_user()
end

--- What the RPC can be asked to do, each with the space name to do it on.
local scenarios = {
    direct = function(name)
        box.schema.space.create(name)
    end,
    door = function(name)
        return box.func[DOOR]:call({name})
    end,
    -- The door's own Lua function, reached without going through _func.
    door_bypassed = function(name)
        return door(name)
    end,
    su = function(name)
        box.session.su('admin', box.schema.space.create, name)
    end,
    insert = function(name)
        box.space[name]:insert{1, 'a'}
    end,
    get = function(name)
        return box.space[name]:get{1} ~= nil
    end,
    truncate = function(name)
        box.space[name]:truncate()
        return box.space[name]:len()
    end,
    create_index = function(name)
        box.space[name]:create_index('secondary', {
            parts = {{2, 'string'}}, unique = false,
        })
    end,
    drop = function(name)
        box.space[name]:drop()
    end,
}

local conn

g.before_all(function()
    local uri = box_helper.listen_uri()
    box.schema.user.create(USER, {password = PASSWORD, if_not_exists = true})
    rawset(_G, DOOR, door)
    box.schema.func.create(DOOR, {setuid = true, if_not_exists = true})
    rawset(_G, ENTRY, function(what, name)
        local ok, rv = pcall(scenarios[what], name)
        return {ok = ok, result = ok and rv or tostring(rv),
                user = box.session.effective_user()}
    end)
    box.schema.user.grant(USER, 'execute', 'lua_call', ENTRY,
                          {if_not_exists = true})
    box.schema.user.grant(USER, 'execute', 'function', DOOR,
                          {if_not_exists = true})
    conn = net_box.connect(uri, {user = USER, password = PASSWORD})
    t.assert(conn:is_connected(), 'the job user could not connect')
end)

g.after_all(function()
    if conn ~= nil then
        conn:close()
    end
    box.schema.func.drop(DOOR, {if_exists = true})
    -- Also drops whatever the user still owns.
    box.schema.user.drop(USER, {if_exists = true})
    rawset(_G, DOOR, nil)
    rawset(_G, ENTRY, nil)
end)

g.after_each(function()
    for _, tuple in box.space._space:pairs() do
        if tuple[3]:sub(1, #PREFIX) == PREFIX then
            box.space[tuple[3]]:drop()
        end
    end
end)

--- Ask the RPC, running as the job user, to do `what` on space `name`.
local function as_job_user(what, name)
    return conn:call(ENTRY, {what, name})
end

local function owner_of(name)
    return box.space._space:get(box.space[name].id)[2]
end

g.test_the_job_user_cannot_create_a_space_directly = function()
    local rv = as_job_user('direct', PREFIX .. 'direct')
    t.assert_equals(rv.ok, false)
    t.assert_str_contains(rv.result, "Write access to space '_space' is denied")
    t.assert_equals(rv.user, USER)
end

g.test_the_door_creates_a_space_the_caller_owns = function()
    local name = PREFIX .. 'owned'
    local rv = as_job_user('door', name)
    t.assert_equals(rv.ok, true, rv.result)
    t.assert_equals(rv.result, 'admin', 'the door did not run as its owner')
    t.assert_equals(rv.user, USER, 'the caller came back elevated')
    t.assert_equals(owner_of(name), box.space._user.index.name:get(USER)[1])
end

g.test_the_owner_uses_its_space_with_no_grant = function()
    local name = PREFIX .. 'used'
    t.assert_equals(as_job_user('door', name).ok, true)
    for _, what in ipairs({'insert', 'get'}) do
        local rv = as_job_user(what, name)
        t.assert_equals(rv.ok, true, what .. ': ' .. tostring(rv.result))
    end
    local rv = as_job_user('truncate', name)
    t.assert_equals(rv.ok, true, rv.result)
    t.assert_equals(rv.result, 0)
end

-- The control for the test above: the same write on a space the job user
-- neither owns nor was granted is refused, so what lets the owner in is the
-- ownership and nothing the job user holds anyway.
g.test_without_ownership_the_job_user_is_refused = function()
    local name = PREFIX .. 'admins'
    box.schema.space.create(name):create_index('primary')
    local rv = as_job_user('insert', name)
    t.assert_equals(rv.ok, false)
    t.assert_str_contains(rv.result, "Write access to space '" .. name ..
                                     "' is denied")
end

-- Which is why the door has to cover these two as well.
g.test_the_owner_cannot_index_or_drop_its_space = function()
    local name = PREFIX .. 'ddl'
    t.assert_equals(as_job_user('door', name).ok, true)
    for _, what in ipairs({'create_index', 'drop'}) do
        local rv = as_job_user(what, name)
        t.assert_equals(rv.ok, false, what .. ' was allowed')
        t.assert_str_contains(rv.result, 'is denied')
    end
end

g.test_the_door_refuses_a_name_outside_the_namespace = function()
    local rv = as_job_user('door', 'rpc_privileges_elsewhere')
    t.assert_equals(rv.ok, false)
    t.assert_str_contains(rv.result, 'outside the namespace')
    t.assert_equals(box.space.rpc_privileges_elsewhere, nil)
end

-- setuid applies only to a call through _func: the same Lua function reached
-- directly runs as the job user and is refused.
g.test_the_door_is_setuid_only_through_func = function()
    local rv = as_job_user('door_bypassed', PREFIX .. 'bypassed')
    t.assert_equals(rv.ok, false)
    t.assert_str_contains(rv.result, "Write access to space '_space' is denied")
end

-- The reason the privilege wall of section 3.19 was never one.
g.test_session_su_elevates_in_process_code = function()
    local name = PREFIX .. 'su'
    local rv = as_job_user('su', name)
    t.assert_equals(rv.ok, true, rv.result)
    t.assert_equals(rv.user, USER, 'su leaked past its function')
    t.assert_not_equals(box.space[name], nil)
end
