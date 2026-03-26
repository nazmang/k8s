function cast_nginx_fields(tag, timestamp, record)
    if record["status"] ~= nil then
        record["status"] = tonumber(record["status"])
    end
    if record["body_bytes_sent"] ~= nil then
        record["body_bytes_sent"] = tonumber(record["body_bytes_sent"])
    end
    if record["request_time"] ~= nil then
        record["request_time"] = tonumber(record["request_time"])
    end
    return 1, timestamp, record
end
