--[[
    An Actor class that represents the local player's character
    
    Author: Ragnarok.Lorand
--]]

local lor_actor = {}
lor_actor._author = 'Ragnarok.Lorand'
lor_actor._version = '2018.05.27.0'

require('tables')
require('lor/lor_utils')
require('vectors')
packets = require('packets')
_libs.lor.actor = lor_actor
_libs.lor.req('chat', 'position', 'resources')

local res = require('resources')
-- local lists = require ('lists')
-- local sets = require ('sets')
local Pos = _libs.lor.position
local ffxi = _libs.lor.ffxi
local messages_initiating = _libs.lor.packets.messages_initiating
local messages_completing = _libs.lor.packets.messages_completing
local instant_prefixes = S{'/jobability', '/weaponskill' }
local magic_prefixes = S{'/magic', '/ninjutsu', '/song'}
local default_delays = {on_action = 0.6, post_action = 2.75, idle = 0.1}
local lag_timeout = 8

--Single Actor =========================================================================================================

local Actor = {}

function Actor.new(id)
    local now = os.clock()
    local player = windower.ffxi.get_player()
    local self = T{     -- Note: some of these fields are HealBot-specific
        id = id,
        action_start = now,
        action_end = now + 0.1,
        action_delay = default_delays.post_action,
        last_pos = Pos.new(),
        pos_arrival = now,
        last_action = now,
        zone_enter = now - 25,
        last_move_check = now,
        last_ipc_sent = now,
        last_acting_state = true,
		indi = {}, geo = {}, ipc_delay = 4, zone_wait = false
    }
    if (not id) or (player.id == id) then
        self:update({
            id = player.id, name = player.name, main_job = player.main_job, sub_job = player.sub_job
        })
    end
--    return setmetatable(self, {__index = Actor})
    return setmetatable(self, {__tostring = Actor.toString, __index = function(t, key)
        for _,cls in pairs({Actor, T}) do
            local v = cls[key]
            if v ~= nil then
                t[key] = v
                return v
            end
        end
    end})
end


function Actor:toString()
    return ("Actor('%s')"):format(self.name or self.id)
end


function Actor:send_cmd(cmd)
    windower.send_command(cmd)
    self.action_delay = default_delays.on_action
end


function Actor:take_action(action, target)
    if action == nil then
--        atcd(('%s:take_action() called with no action'):format(self))
        return
    end
    local act = action.action
    local msg = action.msg or ''
    target = target or action.name
    atcd(act.en .. string.char(129, 168) .. target .. msg)

    self.last_action = os.clock()
    self:send_cmd(('input %s "%s" %s'):format(act.prefix, act.en, target))
    if instant_prefixes:contains(act.prefix) then
        self.action_delay = 2.75
    end
    --if action:lower():contains('waltz') then
    --self.action_delay = 2.75
    --end
end


function Actor:action_delay_passed()
    return (os.clock() - self.last_action) > self.action_delay
end


function Actor:is_acting()
    local now = os.clock()
    if (now - self.action_start) > lag_timeout then
        --Precaution in case an action completion isn't registered for a long time
        self.action_end = now
    end
    local acting = self.action_end < self.action_start
    if self.last_acting_state ~= acting then                --If the current acting state is different from the last one
        if self.last_acting_state then                      --If an action was being performed
            self.action_delay = default_delays.post_action  --Set a longer delay
            self.last_action = now                          --The delay will be from this time
        else                                                --If no action was being performed
            self.action_delay = default_delays.idle         --Set a short delay
        end
        self.last_acting_state = acting                     --Refresh the last acting state
    end
    return acting
end


function Actor:pos()
    return Pos.current_position()
end


function Actor:time_at_pos()
    local current_pos = Pos.current_position()
    if (current_pos == nil) then
        return nil
    end
    return math.floor((os.clock() - self.pos_arrival)*10)/10
end


function Actor:is_moving()
    local current_pos = Pos.current_position()
    if (current_pos == nil) then
        return true
    end
    
    local moving = true
    if (self.last_pos:equals(current_pos)) then
        moving = (self:time_at_pos() < 0.5)
    else
        self.last_pos = current_pos
        self.pos_arrival = os.clock()
    end
    return moving
end


-- function Actor:dist_from(targ)
    -- -- Returns the distance from the target in in-game units, or -1 if the target could not be determined
    -- local target = ffxi.get_target(targ)
    -- if target ~= nil then
        -- return math.sqrt(target.distance)
    -- end
    -- return -1
-- end

function Actor:dist_from(targ)
	local p = ffxi.get_target('me')
	local p_2 = ffxi.get_target(targ)
	if p_2 ~= nil and p ~= nil then
		return ((V{p_2.x, p_2.y, (p_2.z*-1)} - V{p.x, p.y, (p.z*-1)}):length())
	end
	return -1
end


function Actor:in_casting_range(targ)
    -- Returns true if the given target is within spell casting range
	local target = ffxi.get_target(targ)
    local dist = self:dist_from(targ)
    if dist == -1 then
        return False
    else
        return dist < (20.9 + target.model_size)
    end
end


function Actor:move_towards(targ)
    local target = ffxi.get_target(targ)
    if target ~= nil then
        local my_pos = Pos.current_position()
        if my_pos ~= nil then
            windower.ffxi.run(my_pos:getDirRadian(Pos.of(target)))
        end
    end
end


function Actor:update_status(id, parsed_action)
    --[[
        Update this actor's status based on the received parsed packet
    --]]
    if parsed_action.actor_id == self.id then
        if id == 0x28 then
            for _,targ in pairs(parsed_action.targets) do
                for _,tact in pairs(targ.actions) do
                    if messages_initiating:contains(tact.message_id) then
                        self.action_start = os.clock()
                        return
                    elseif messages_completing:contains(tact.message_id) then
                        self.action_end = os.clock()
                        return
                    end
                end
            end
        elseif id == 0x29 then
            if messages_initiating:contains(parsed_action.message_id) then
                self.action_start = os.clock()
            elseif messages_completing:contains(parsed_action.message_id) then
                self.action_end = os.clock()
            end
        end
    end
end


function Actor:update_job()
    local player = windower.ffxi.get_player()
    self.main_job = player.main_job
    self.sub_job = player.sub_job
end


function Actor:buff_active(...)
    --[[
        Returns true if one of the given buffs are currently active.
    --]]
    local args = S{...}:map(string.lower)
    local player = windower.ffxi.get_player()
    if (player ~= nil) and (player.buffs ~= nil) then
        for _,bid in pairs(player.buffs) do
            local buff = res.buffs[bid]
            if args:contains(buff.en:lower()) then
                return true
            end
        end
    end
    return false
end


function Actor:can_use(action)
    --[[
        Returns true if the given spell/ability has been learned and is available on the current job.
    --]]
    local player = windower.ffxi.get_player()
	local abil_recast = windower.ffxi.get_ability_recasts()
    if (player == nil) or (action == nil) then return false end
    if magic_prefixes:contains(action.prefix) then
		local learned
		
		if action.id == 363 then
			action.id = 273 -- Sleepga
		elseif action.id == 364 then
			action.id = 274 -- Sleepga II
		end
		
		if action.id == 503 then -- impact
			-- Credits to Rubenator
			local equippable_bags = res.bags:equippable(true):map(windower.ffxi.get_items..table.get-{'id'}):filter(table.get-{'enabled'}):map(L..table.key_filter-{functions.equals('number')..type})
			for bag_id, bag in pairs(equippable_bags) do 
				bag:map(table.set-{'bag',bag_id}) 
			end
			local equippable_items = L{equippable_bags:extract()}:flatten(false)
			local impact_cloaks = S{11363,23799}
			for _,item in ipairs(equippable_items) do
				if item.id > 0 then
					if impact_cloaks:contains(item.id) then
						learned = true
					end
				end
			end
		elseif action.type == 'BlueMagic' then
			local unbridled_spells = S{736,737,738,739,740,741,742,743,744,745,746,747,748,749,750,751,752,753}
			if ((player.main_job_id == 16 and table.contains(windower.ffxi.get_mjob_data().spells,action.id))
			or (player.sub_job_id == 16 and table.contains(windower.ffxi.get_sjob_data().spells,action.id))) or (unbridled_spells:contains(action.id)) then
				if unbridled_spells:contains(action.id) and abil_recast[81] == 0 then
					learned = windower.ffxi.get_spells()[action.id]
				else
					learned = windower.ffxi.get_spells()[action.id]
				end
			end
		else
			learned = windower.ffxi.get_spells()[action.id]
		end
        if learned then
            local mj_id, sj_id = player.main_job_id, player.sub_job_id
            local jp_spent = player.job_points[player.main_job:lower()].jp_spent
            local mj_req = action.levels[mj_id]
            local sj_req = action.levels[sj_id]
			
            local main_can_cast, sub_can_cast = false, false
            if mj_req ~= nil then
                main_can_cast = (mj_req <= player.main_job_level) or (mj_req <= jp_spent)
            end
            if sj_req ~= nil and not Actor.buff_active('SJ Restriction') then
                sub_can_cast = (sj_req <= player.sub_job_level)
            end
			return main_can_cast or sub_can_cast
        else
            atcd(('%s has not learned %s'):format(player.name, action.en))
        end
    elseif S{'/jobability', '/pet'}:contains(action.prefix) then
        local available_jas = S(windower.ffxi.get_abilities().job_abilities)
        return available_jas:contains(action.id)
    elseif action.prefix == '/weaponskill' then
        local available_wss = S(windower.ffxi.get_abilities().weapon_skills)
        return available_wss:contains(action.id)
    else
        atc(123, 'Error: Unknown action prefix ('..tostring(action.prefix)..') for '..tostring(action.en))
    end
    return false
end


function Actor:ready_to_use(action)
    --[[
        Returns true if the given spell/ability can be used, and is not on cooldown.
    --]]
    if (action ~= nil) and self:can_use(action) then
        local player = windower.ffxi.get_player()
        if (player == nil) then return false end
        if magic_prefixes:contains(action.prefix) then
            local rc = windower.ffxi.get_spell_recasts()[action.recast_id]
			local mp_cost = (player.vitals.mp >= action.mp_cost)
            return (rc == 0 and mp_cost == true)
		elseif (player.main_job == 'DNC' or player.sub_job == 'DNC') and action.prefix == '/jobability' then
			local rc = windower.ffxi.get_ability_recasts()[action.recast_id]
			local tp_cost = (player.vitals.tp >= action.tp_cost)
			return (rc == 0 and tp_cost == true)
        elseif S{'/jobability', '/pet'}:contains(action.prefix) then
            local rc = windower.ffxi.get_ability_recasts()[action.recast_id]
            return rc == 0
        elseif action.prefix == '/weaponskill' then
            return (player.status == 1) and (player.vitals.tp > 999)
        end
    end
    return false
end

--Credits to SetTarget
function Actor:set_target(id)
    id = tonumber(id)
    if id == nil then
        return
    end

    local target = windower.ffxi.get_mob_by_id(id)
    if not target then
        return
    end

    local player = windower.ffxi.get_player()

    packets.inject(packets.new('incoming', 0x058, {
        ['Player'] = player.id,
        ['Target'] = target.id,
        ['Player Index'] = player.index,
    }))
end

function Actor:attack_target(id)
    id = tonumber(id)
    if id == nil then
        return
    end

    local target = windower.ffxi.get_mob_by_id(id)
    if not target then
        return
    end

    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = target.id,
        ['Target Index'] = target.index,
        ['Category'] = 2,
    }))
end

function Actor:switch_target(id)
    id = tonumber(id)
    if id == nil then
        return
    end

    local target = windower.ffxi.get_mob_by_id(id)
    if not target then
        return
    end

    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = target.id,
        ['Target Index'] = target.index,
        ['Category'] = 15,
    }))
end

--Actor Group ==========================================================================================================

local ActorGroup = {}

function ActorGroup.new()
    local self = {actors = {}}
    return setmetatable(self, {__index = ActorGroup})
end

function ActorGroup:add(actor)
    self.actors[actor.id] = actor
end

function ActorGroup:remove(id)
    self.actors[id] = nil
end

function ActorGroup:update(id, parsed_action)
    local actor = self.actors[parsed_action.actor_id]
    if actor ~= nil then
        actor:update(id, parsed_action)
    end
end


lor_actor.Actor = Actor
lor_actor.ActorGroup = ActorGroup

return lor_actor

-----------------------------------------------------------------------------------------------------------
--[[
Copyright © 2018, Ragnarok.Lorand
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of libs/lor nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Lorand BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]
-----------------------------------------------------------------------------------------------------------
