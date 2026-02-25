local Diagnostics = {}

function Diagnostics.Log(tag: string, fields: { [string]: any }?)
	return
end

function Diagnostics.Increment(counterName: string, amount: number?)
	return
end

function Diagnostics.GetCounter(counterName: string): number
	return 0
end

function Diagnostics.ResetPassCounters()
	return
end

function Diagnostics.EmitPass1Summary()
	return
end

return Diagnostics
