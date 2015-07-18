-- Stealth Build

-- Message on screen
if managers.hud then
   managers.hud:show_hint( { text = "Stealth ON - Breaks Forklifts" } )
end

-- Highlight items in FF Day 1,3
if managers.job:current_level_id() == "framing_frame_1" or managers.job:current_level_id() == "framing_frame_3" then -- APPARTMENT
  for k,v in pairs(managers.mission._scripts.default._elements) do
        if v._values and v._values.trigger_list and v._values.trigger_list[1] and (v._values.trigger_list[1].notify_unit_sequence == "state_outline_enabled" or
        v._values.trigger_list[1].notify_unit_sequence == "enable_outline") then
                v:on_executed()
        end
  end
else
end

-- No cash penalty for killing civilians
function MoneyManager.get_civilian_deduction() return 0 end
function MoneyManager.civilian_killed() return end

-- infinite pager answers
function GroupAIStateBase:on_successful_alarm_pager_bluff()end

-- Infinite stamina
function PlayerMovement:_change_stamina( value ) end
function PlayerMovement:is_stamina_drained() return false end
function PlayerStandard:_can_run_directional() return true end

-- Instant interaction (except for pagers because it doesn't work so well when you are client on multiplayer)
if not _getTimer then _getTimer = BaseInteractionExt._get_timer end
function BaseInteractionExt:_get_timer()
  if self.tweak_data == "corpse_alarm_pager" then
    return 0.1 -- if pagers don't work properly (eg. when you're a client in multiplayer) use 'return _getTimer(self)' instead.
  end
  return 0
end

-- No movement penalty, change to a larger value than 1 for an increase in speed
PlayerManager.body_armor_movement_penalty = function(self) return 1 end

-- Instant equipment deploy
PlayerManager.selected_equipment_deploy_timer = function(self) return 0 end

-- No jamming drill
function TimerGui:_set_jamming_values() return end
function TimerGui:start( timer )
  timer = 0.01
  if self._jammed then
    self:_set_jammed( false )
    return
  end

  if not self._powered then
      self:_set_powered( true )
      return
  end

  if self._started then
    return
  end

  self:_start( timer )
  if managers.network:session() then
  managers.network:session():send_to_peers_synched( "start_timer_gui", self._unit, timer )
  end
end

-- Automark civilians, guards, cameras
function mark_enemies()     
  for u_key,u_data in pairs(managers.enemy:all_enemies()) do
    u_data.unit:contour():add( "mark_enemy" )
  end
  for u_key, unit in pairs( managers.groupai:state()._security_cameras ) do
    --unit:contour():add( "mark_enemy" )
  end
  local units = World:find_units_quick( "all" )
  for i,unit in ipairs( units ) do
    if unit:contour() then 
      unit:contour():add( "mark_unit" )
    end
  end
end
function UnitNetworkHandler:mark_enemy( unit, marking_strength, sender ) 
end
if not _markingToggle then _marktoggle = nil _markingToggle = true
  else _markingToggle = nil 
end
if not _gameUpdate then _gameUpdate = GameSetup.update 
end
do
  local _gameUpdateLastMark
  function GameSetup:update( t, dt )
  _gameUpdate(self, t, dt)
  _gameUpdateLastMark = t 
  if _markingToggle then
    mark_enemies()
  else
    if not _marktoggle then
      _marktoggle = true
      for u_key,u_data in pairs(managers.enemy:all_enemies()) do
        u_data.unit:contour():remove( "mark_enemy" )
      end
    end
  end
  end
end

-- Classic Stealth
if not StealthFixer then
    if not IntimitateInteractionExt or not GroupAIStateBase or not ElementSpawnEnemyDummy or not CopLogicIntimidated then
        return
    end
    StealthFixer = { firstCall = true }
    if not managers.interaction or not managers.groupai then
        return
    end

    --Unlimited bodybags
    old_interact_blocked = old_interact_blocked or IntimitateInteractionExt._interact_blocked
    function IntimitateInteractionExt:_interact_blocked( ... )
        if self.tweak_data == "hostage_convert" then
            return not (managers.player:has_category_upgrade( "player", "convert_enemies" ) and not managers.player:chk_minion_limit_reached() )
        elseif self.tweak_data == "corpse_dispose" and not managers.player.carry_stack then
            if not managers.player:has_category_upgrade( "player", "corpse_dispose" ) or managers.player:is_carrying() then
                return true
            end
            return not managers.player:can_carry( "person" )
        else
            return old_interact_blocked(self, ...)
        end
    end

    managers.interaction._interact_blocked = IntimitateInteractionExt._interact_blocked
    
    --Joker enabled in stealth
    function GroupAIStateBase:convert_hostage_to_criminal( unit, peer_unit )
        local player_unit = peer_unit or managers.player:player_unit()
        if not alive( player_unit ) or not self._criminals[ player_unit:key() ] then
            return
        end
        if not alive( unit ) then
            return
        end
        
        local u_key = unit:key()
        local u_data = self._police[ u_key ]
        
        if not u_data then
            return
        end
        
        local minions = self._criminals[ player_unit:key() ].minions or {}
        self._criminals[ player_unit:key() ].minions = minions
        
        
        local max_minions = 0
        if peer_unit then        -- client
            max_minions = peer_unit:base():upgrade_value( "player", "convert_enemies_max_minions" ) or 0
        else                                                    -- server
            max_minions = managers.player:upgrade_value( "player", "convert_enemies_max_minions", 0 )
        end
        
        
        Application:debug( "GroupAIStateBase:convert_hostage_to_criminal", "Player", player_unit, "Minions: ", table.size( minions ).."/"..max_minions )
        
        if alive(self._converted_police[ u_key ]) or table.size( minions ) >= max_minions then
            local member = managers.network:game():member_from_unit( player_unit )
            if member then
                if member == Global.local_member then
                    managers.hint:show_hint( "convert_enemy_failed" )
                else
                    managers.network:session():send_to_peer( member:peer(), "sync_show_hint", "convert_enemy_failed" )
                end
            end
            
            return
        end
        
        local group = u_data.group
        if group then
            self:_remove_group_member( group, u_key, nil )
        end
        
        -- un-assign from group AI
        self:set_enemy_assigned( nil, u_key )
        
        -- remember the fact that he is converted
        u_data.is_converted = true
        -- switch AI to criminal
        unit:brain():convert_to_criminal( peer_unit )
        -- unit:character_damage():convert_to_criminal()    -- unit:brain():convert_to_criminal already do this
        unit:character_damage():add_listener( "Converted"..tostring(player_unit:key()), {"death"}, callback( self, self, "clbk_minion_dies", player_unit:key() ) )
        -- managers.game_play_central:add_friendly_contour( unit )
        if not unit:contour() then
            debug_pause_unit( unit, "[GroupAIStateBase:convert_hostage_to_criminal]: Unit doesn't have Contour Extension" )
        end
        unit:contour():add( "friendly" )

        u_data.so_access = unit:brain():SO_access()
        
        self._converted_police[ u_key ] = unit
        minions[ u_key ] = unit
        
        
        local convert_enemies_health_multiplier_level = 0
        local passive_convert_enemies_health_multiplier_level = 0
        if alive( peer_unit ) then        -- client
            convert_enemies_health_multiplier_level = peer_unit:base():upgrade_level( "player", "convert_enemies_health_multiplier" ) or 0
            passive_convert_enemies_health_multiplier_level = peer_unit:base():upgrade_level( "player", "passive_convert_enemies_health_multiplier" ) or 0
        else                                                    -- server
            convert_enemies_health_multiplier_level = managers.player:upgrade_level( "player", "convert_enemies_health_multiplier" )
            passive_convert_enemies_health_multiplier_level = managers.player:upgrade_level( "player", "passive_convert_enemies_health_multiplier" )
        end
        
        local owner_peer_id = managers.network:game():member_from_unit( player_unit ):peer():id()
        managers.network:session():send_to_peers( "mark_minion", unit, owner_peer_id, convert_enemies_health_multiplier_level, passive_convert_enemies_health_multiplier_level )
        
        if not peer_unit then    -- server did it!, iam the server
            managers.player:count_up_player_minions()
        end
    end

    managers.groupai:state().convert_hostage_to_criminal = GroupAIStateBase.convert_hostage_to_criminal
    
    --don't count jokered guards
    function GroupAIStateBase:has_room_for_police_hostage()
        local global_limit = 1

        for u_key, u_data in pairs( self._player_criminals ) do
            local limit
            if u_data.unit:base().is_local_player then
                limit = managers.player:upgrade_value( "player", "ene_hostage_lim_1", 1 )
            else
                limit = u_data.unit:base():upgrade_value( "player", "ene_hostage_lim_1" )
            end
            global_limit = limit and math.max( global_limit, limit ) or global_limit
        end

        return ( self._police_hostage_headcount < global_limit )
    end
    
    managers.groupai:state().has_room_for_police_hostage = GroupAIStateBase.has_room_for_police_hostage
    
    --No pager for dominated guards
    function CopLogicIntimidated._do_tied( data, aggressor_unit )
        local my_data = data.internal_data

        if my_data.surrender_clbk_registered then
            managers.groupai:state():remove_from_surrendered( data.unit )
            my_data.surrender_clbk_registered = nil
        end
        my_data.tied = true
        data.unit:inventory():destroy_all_items()
        data.unit:brain():set_update_enabled_state( false )
        
        if my_data.update_task_key then
            managers.enemy:unqueue_task( my_data.update_task_key )
            my_data.update_task_key = nil
        end
        
        local rsrv_pos = my_data.rsrv_pos
        if rsrv_pos and rsrv_pos.stand then
            managers.navigation:unreserve_pos( rsrv_pos.stand )
            rsrv_pos.stand = nil
        end
        managers.groupai:state():on_enemy_tied( data.unit:key() )
        data.unit:base():set_slot( data.unit, 22 )    --22. Bound Hostages ( civilian and police ) handcuffed players are in slot 4
        
        data.unit:interaction():set_tweak_data( "hostage_convert" )
        data.unit:interaction():set_active( true, true, false )
        
        my_data.is_hostage = true
        managers.groupai:state():on_hostage_state( true, data.key, true )
        
        if aggressor_unit then
            data.unit:character_damage():drop_pickup() -- Steal his things
            data.unit:character_damage():set_pickup( nil )
                
            if aggressor_unit == managers.player:player_unit() then -- Its me, the server
                managers.statistics:tied( { name = data.unit:base()._tweak_table } )
            else -- It was one of the clients
                aggressor_unit:network():send_to_unit( { "statistics_tied", data.unit:base()._tweak_table } )
            end
        end
    end
    
    origCopDamageDie = origCopDamageDie or CopDamage.die
    function CopDamage:die(...)
        origCopDamageDie(self, ...)
        io.stderr:write(self._unit:interaction().tweak_data .."\n")
        if self._unit:interaction().tweak_data == "hostage_convert" then
            self._unit:interaction():set_active(false, true, false)
        end
    end
    
    function IsDifficultyHarder(thisDifficulty, otherDifficulty)
        local diffVal = { normal = 1, hard = 2, overkill = 3, overkill_145 = 4, overkill_290 = 5 }
        return diffVal[thisDifficulty] > diffVal[otherDifficulty] and true or false
    end
    
    function fixStealthElementDifficulty(element, target, script)
        local current = Global.game_settings.difficulty
        if current == target or IsDifficultyHarder(target, current) then
            return
        end
        for _,item in ipairs(element:values().on_executed) do
            local elem = script:elements()[item.id]
            if elem:values()["difficulty_"..target] then
                elem:values()["difficulty_"..current] = true
            elseif elem:values()["difficulty_"..target] == false then
                elem:values()["difficulty_"..current] = false
            end
        end
    end
    
    for _, script in pairs(managers.mission:scripts()) do
        for id, element in pairs(script:elements()) do
            local name = element:editor_name()
            if name == "spawnCopPatrol" or name == "spawn_guard" or name == "respawn_guard" or name:find("extra_spawn") then
                element:set_enabled(false)
            end
            local diff = Global.game_settings.difficulty
            local multiplayer = not Global.game_settings.single_player
            local lvl = Global.game_settings.level_id
            if multiplayer and diff ~= "overkill_290" then --changes only needed for multiplayer and not Deathwish
                --FF = spawnGuards, BO = logic_link_069, ED1 = setup_spawns, ED2 = delay
                if name == "spawnGuards" or name == "logic_link_069" or name == "guard_setup" or name == "setup_spawns" or name == "delay" then
                    if lvl:find("framing_frame") or lvl:find("jungle") then
                        fixStealthElementDifficulty(element, "normal", script)
                    elseif lvl == "election_day_1" then
                        fixStealthElementDifficulty(element, "hard", script)
                    elseif lvl == "election_day_2" then
                        fixStealthElementDifficulty(element, "overkill", script)
                    end
                end
            end
        end
    end
end
