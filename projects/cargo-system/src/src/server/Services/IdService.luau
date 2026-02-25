local HttpService = game:GetService("HttpService")

local IdService = {}

local counter = 0
local jobId = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)

function IdService.nextCargoId(): string
    counter += 1
    local unixMs = DateTime.now().UnixTimestampMillis
    return string.format("cargo_%s_%d_%d", jobId, counter, unixMs)
end

return IdService
