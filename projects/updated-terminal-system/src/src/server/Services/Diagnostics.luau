local Diagnostics = {}

local counters: { [string]: number } = {
	terminals_loaded = 0,
	ticks_processed = 0,
	contender_changes = 0,
	neutralizations = 0,
	captures = 0,
	tie_freeze_ok = 1,
	errors = 0,
}

function Diagnostics.Log(tag: string, fields: { [string]: any }?)
	return
end

function Diagnostics.Increment(counterName: string, amount: number?)
	local delta = amount or 1
	counters[counterName] = (counters[counterName] or 0) + delta
end

function Diagnostics.GetCounter(counterName: string): number
	return counters[counterName] or 0
end

function Diagnostics.SetCounter(counterName: string, value: number)
	counters[counterName] = value
end

function Diagnostics.ResetPassCounters()
	for key, _ in pairs(counters) do
		counters[key] = 0
	end
	counters.tie_freeze_ok = 1
end

function Diagnostics.EmitPass1Summary(stepName: string)
	return
end

return Diagnostics
