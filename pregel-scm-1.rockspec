package = 'pregel'
version = 'scm-1'
source = {
    url    = 'git+https://github.com/tarantool-contrib/pregel.git',
    branch = 'master',
}
description = {
    summary  = 'Pregel graph processing model for Tarantool',
    homepage = 'https://github.com/tarantool-contrib/pregel',
    license  = 'BSD-2-Clause',
}
-- tarantool-avro is optional and deliberately not listed: only
-- loader.avro_files needs it, and it is required on first use there.
dependencies = {
    'lua ~> 5.1',
}
build = {
    type = 'builtin',
    modules = {
        ['pregel.aggregator']        = 'pregel/aggregator.lua',
        ['pregel.loader']            = 'pregel/loader.lua',
        ['pregel.master']            = 'pregel/master.lua',
        ['pregel.mpool']             = 'pregel/mpool.lua',
        ['pregel.queue']             = 'pregel/queue.lua',
        ['pregel.vertex']            = 'pregel/vertex.lua',
        ['pregel.worker']            = 'pregel/worker.lua',
        ['pregel.roles.common']      = 'pregel/roles/common.lua',
        ['pregel.roles.master']      = 'pregel/roles/master.lua',
        ['pregel.roles.worker']      = 'pregel/roles/worker.lua',
        ['pregel.utils']             = 'pregel/utils/init.lua',
        ['pregel.utils.collections'] = 'pregel/utils/collections.lua',
        ['pregel.utils.copy']        = 'pregel/utils/copy.lua',
        ['pregel.utils.strict']      = 'pregel/utils/strict.lua',
        ['pregel.math.vector']       = 'pregel/math/vector.lua',
        ['pregel.math.gd']           = 'pregel/math/gd.lua',
        ['pregel.math.auc']          = 'pregel/math/auc.lua',
        ['pregel.math.percentile']   = 'pregel/math/percentile.lua',
        ['pregel.math']              = 'pregel/math/init.lua',
        ['pregel.math.mf']           = 'pregel/math/mf.lua',
    },
}
