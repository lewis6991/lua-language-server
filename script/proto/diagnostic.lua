local util = require('utility')

--- @class proto.diagnostic
local M = {}

--- @alias DiagnosticSeverity
---| 'Hint'
---| 'Information'
---| 'Warning'
---| 'Error'

--- @alias DiagnosticNeededFileStatus
---| 'Any'
---| 'Opened'
---| 'None'

--- @class proto.diagnostic.info
--- @field severity DiagnosticSeverity
--- @field status   DiagnosticNeededFileStatus
--- @field group    string

M.diagnosticDatas = {}
M.diagnosticGroups = {}

function M.register(names)
    ---@param info proto.diagnostic.info
    return function(info)
        for _, name in ipairs(names) do
            M.diagnosticDatas[name] = {
                severity = info.severity,
                status = info.status,
            }
            if not M.diagnosticGroups[info.group] then
                M.diagnosticGroups[info.group] = {}
            end
            M.diagnosticGroups[info.group][name] = true
        end
    end
end

M.register({
    'unused-local',
    'unused-function',
    'unused-label',
    'unused-vararg',
    'trailing-space',
    'redundant-return',
    'empty-block',
    'code-after-break',
    'unreachable-code',
})({
    group = 'unused',
    severity = 'Hint',
    status = 'Opened',
})

M.register({
    'redundant-value',
    'unbalanced-assignments',
    'redundant-parameter',
    'missing-parameter',
    'missing-return-value',
    'redundant-return-value',
    'missing-return',
    'missing-fields',
})({
    group = 'unbalanced',
    severity = 'Warning',
    status = 'Any',
})

M.register({
    'need-check-nil',
    'undefined-field',
    'cast-local-type',
    'assign-type-mismatch',
    'param-type-mismatch',
    'cast-type-mismatch',
    'return-type-mismatch',
    'inject-field',
})({
    group = 'type-check',
    severity = 'Warning',
    status = 'Opened',
})

M.register({
    'duplicate-doc-alias',
    'undefined-doc-class',
    'undefined-doc-name',
    'circle-doc-class',
    'undefined-doc-param',
    'duplicate-doc-param',
    'doc-field-no-class',
    'duplicate-doc-field',
    'unknown-diag-code',
    'unknown-cast-variable',
    'unknown-operator',
})({
    group = 'luadoc',
    severity = 'Warning',
    status = 'Any',
})

M.register({
    'incomplete-signature-doc',
    'missing-global-doc',
    'missing-local-export-doc',
})({
    group = 'luadoc',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'codestyle-check',
})({
    group = 'codestyle',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'spell-check',
})({
    group = 'codestyle',
    severity = 'Information',
    status = 'None',
})

M.register({
    'name-style-check',
})({
    group = 'codestyle',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'newline-call',
    'newfield-call',
    'ambiguity-1',
    'count-down-loop',
    'different-requires',
})({
    group = 'ambiguity',
    severity = 'Warning',
    status = 'Any',
})

M.register({
    'await-in-sync',
    'not-yieldable',
})({
    group = 'await',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'no-unknown',
})({
    group = 'strong',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'redefined-local',
})({
    group = 'redefined',
    severity = 'Hint',
    status = 'Opened',
})

M.register({
    'undefined-global',
    'global-in-nil-env',
})({
    group = 'global',
    severity = 'Warning',
    status = 'Any',
})

M.register({
    'lowercase-global',
    'undefined-env-child',
})({
    group = 'global',
    severity = 'Information',
    status = 'Any',
})

M.register({
    'global-element',
})({
    group = 'conventions',
    severity = 'Warning',
    status = 'None',
})

M.register({
    'duplicate-index',
})({
    group = 'duplicate',
    severity = 'Warning',
    status = 'Any',
})

M.register({
    'duplicate-set-field',
})({
    group = 'duplicate',
    severity = 'Warning',
    status = 'Opened',
})

M.register({
    'close-non-object',
    'deprecated',
    'discard-returns',
    'invisible',
})({
    group = 'strict',
    severity = 'Warning',
    status = 'Any',
})

--- @return table<string, DiagnosticSeverity>
function M.getDefaultSeverity()
    local severity = {}
    for name, info in pairs(M.diagnosticDatas) do
        severity[name] = info.severity
    end
    return severity
end

--- @return table<string, DiagnosticNeededFileStatus>
function M.getDefaultStatus()
    local status = {}
    for name, info in pairs(M.diagnosticDatas) do
        status[name] = info.status
    end
    return status
end

function M.getGroupSeverity()
    local group = {}
    for name in pairs(M.diagnosticGroups) do
        group[name] = 'Fallback'
    end
    return group
end

function M.getGroupStatus()
    local group = {}
    for name in pairs(M.diagnosticGroups) do
        group[name] = 'Fallback'
    end
    return group
end

--- @param name string
--- @return string[]
M.getGroups = util.cacheReturn(function(name)
    local groups = {}
    for groupName, nameMap in pairs(M.diagnosticGroups) do
        if nameMap[name] then
            groups[#groups + 1] = groupName
        end
    end
    table.sort(groups)
    return groups
end)

--- @return table<string, true>
function M.getDiagAndErrNameMap()
    if not M._diagAndErrNames then
        local names = {}
        for name in pairs(M.getDefaultSeverity()) do
            names[name] = true
        end
        for _, fileName in ipairs({ 'parser.compile', 'parser.luadoc' }) do
            local path = package.searchpath(fileName, package.path)
            if path then
                local f = io.open(path)
                if f then
                    for line in f:lines() do
                        local name = line:match([=[type%s*=%s*['"](%u[%u_]+%u)['"]]=])
                        if name then
                            local id = name:lower():gsub('_', '-')
                            names[id] = true
                        end
                    end
                    f:close()
                end
            end
        end
        table.sort(names)
        M._diagAndErrNames = names
    end
    return M._diagAndErrNames
end

return M
