local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Diagnostics = {}

local counters = {
    purchases_success = 0,
    purchases_rejected = 0,
    drops_success = 0,
    drops_rejected = 0,
    sales_success = 0,
    sales_rejected = 0,
    sell_reject_dest = 0,
    sell_reject_stolen = 0,
    sell_reject_sold = 0,
    active_cargo_count = 0,
    restore_drop_ship_attach = 0,
    restore_drop_path_attach = 0,
    restore_drop_surface_attach = 0,
    restore_drop_world_attach = 0,
    restore_drop_near_player = 0,
    restore_owned_near_player = 0,
    errors = 0,
}

function Diagnostics.increment(counterName: string, amount: number?)
    local delta = amount or 1
    if counters[counterName] == nil then
        counters[counterName] = 0
    end
    counters[counterName] += delta
end

function Diagnostics.set(counterName: string, value: number)
    counters[counterName] = value
end

function Diagnostics.get(counterName: string): number
    return counters[counterName] or 0
end

function Diagnostics.snapshot(): {[string]: number}
    local copy = {}
    for key, value in pairs(counters) do
        copy[key] = value
    end
    return copy
end

function Diagnostics.log(reasonCode: string, fields: {[string]: any}?)
    if not Config.DiagnosticsEnabled then
        return
    end

    local parts = {"[CARGO]", "reason=" .. reasonCode}
    if fields then
        for key, value in pairs(fields) do
            table.insert(parts, tostring(key) .. "=" .. tostring(value))
        end
    end

    print(table.concat(parts, " "))
end

function Diagnostics.printP1Summary(step: string, fields: {[string]: any}?)
    local parts = {
        "[P1_SUMMARY]",
        "step=" .. step,
    }

    if fields then
        for key, value in pairs(fields) do
            table.insert(parts, tostring(key) .. "=" .. tostring(value))
        end
    end

    local snap = Diagnostics.snapshot()
    if step == "purchase" then
        table.insert(parts, "buys_ok=" .. tostring(snap.purchases_success or 0))
        table.insert(parts, "buys_reject=" .. tostring(snap.purchases_rejected or 0))
    elseif step == "drop" then
        table.insert(parts, "drops_ok=" .. tostring(snap.drops_success or 0))
        table.insert(parts, "drops_reject=" .. tostring(snap.drops_rejected or 0))
    elseif step == "sell" then
        table.insert(parts, "sell_ok=" .. tostring(snap.sales_success or 0))
        table.insert(parts, "sell_reject=" .. tostring(snap.sales_rejected or 0))
        table.insert(parts, "sell_reject_dest=" .. tostring(snap.sell_reject_dest or 0))
        table.insert(parts, "sell_reject_stolen=" .. tostring(snap.sell_reject_stolen or 0))
        table.insert(parts, "sell_reject_sold=" .. tostring(snap.sell_reject_sold or 0))
    end

    table.insert(parts, "errors=" .. tostring(snap.errors or 0))
    print(table.concat(parts, " "))
end

return Diagnostics
