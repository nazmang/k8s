-- Application log allowlist (2026-11-25).
--
-- A pod opts in with two annotations:
--   logging.homelab/ship:  "true"
--   logging.homelab/allow: "<logger>=<Lua pattern>;<logger>=<Lua pattern>;..."
-- The list lives with the application chart, not here.
--
-- A container line must be a Python logging record:
--   "YYYY-MM-DD HH:MM:SS,mmm LEVEL <logger>: <message>"
-- Lines without that head (continuations, tracebacks) are dropped.
--
-- <logger> in the annotation is the logger name without its first segment:
--   "a.b"    matches the tail "a.b" only;
--   "a.b.*"  matches the tail "a.b" and any "a.b.<...>".
-- <Lua pattern> is matched against the whole message with string.find;
-- "*" passes any message. The split is at the first "=", so a pattern may
-- contain "=" but not ";". A line passes when one rule matches both the
-- logger and the message. Nothing else is sent.
--
-- The output record keeps only the fields below: the pod annotations (the
-- allowlist itself) and labels never leave the node.

local HEAD = "^(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d,%d%d%d) (%u+) ([^ :]+): (.*)$"

local cache = {}
local cache_size = 0

local function parse_rules(allow)
    local rules = {}
    for item in string.gmatch(allow, "[^;]+") do
        local eq = string.find(item, "=", 1, true)
        if eq then
            local logger = string.match(string.sub(item, 1, eq - 1), "^%s*(.-)%s*$")
            local pattern = string.sub(item, eq + 1)
            local ok = pattern == "*" or pcall(string.find, "", pattern)
            if ok and logger ~= "" and pattern ~= "" then
                local rule = { pattern = pattern }
                if string.sub(logger, -2) == ".*" then
                    rule.prefix = string.sub(logger, 1, -3)
                else
                    rule.exact = logger
                end
                rules[#rules + 1] = rule
            end
        end
    end
    return rules
end

local function rules_for(allow)
    local rules = cache[allow]
    if rules == nil then
        if cache_size >= 16 then
            cache = {}
            cache_size = 0
        end
        rules = parse_rules(allow)
        cache[allow] = rules
        cache_size = cache_size + 1
    end
    return rules
end

local function logger_matches(rule, tail)
    if rule.exact then
        return tail == rule.exact
    end
    local p = rule.prefix
    return tail == p or string.sub(tail, 1, #p + 1) == p .. "."
end

local function message_matches(rule, message)
    if rule.pattern == "*" then
        return true
    end
    local ok, found = pcall(string.find, message, rule.pattern)
    return ok and found ~= nil
end

function app_allow(tag, timestamp, record)
    local k8s = record["kubernetes"]
    if type(k8s) ~= "table" then
        return -1, timestamp, record
    end
    local ann = k8s["annotations"]
    if type(ann) ~= "table" or ann["logging.homelab/ship"] ~= "true" then
        return -1, timestamp, record
    end
    local allow = ann["logging.homelab/allow"]
    if type(allow) ~= "string" or allow == "" then
        return -1, timestamp, record
    end
    local line = record["log"]
    if type(line) ~= "string" then
        return -1, timestamp, record
    end
    line = string.gsub(line, "[\r\n]+$", "")

    local log_time, level, logger, message = string.match(line, HEAD)
    if logger == nil then
        return -1, timestamp, record
    end
    local dot = string.find(logger, ".", 1, true)
    if dot == nil then
        return -1, timestamp, record
    end
    local tail = string.sub(logger, dot + 1)

    for _, rule in ipairs(rules_for(allow)) do
        if logger_matches(rule, tail) and message_matches(rule, message) then
            return 2, timestamp, {
                log_time = log_time,
                level = level,
                logger = logger,
                message = message,
                stream = record["stream"],
                namespace = k8s["namespace_name"],
                pod = k8s["pod_name"],
                container = k8s["container_name"],
            }
        end
    end
    return -1, timestamp, record
end
