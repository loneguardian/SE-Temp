local SpaceshipClone = {}

SpaceshipClone.names_excluded = {
  Spectator.name_seat,
  Capsule.name_space_capsule_vehicle_light,
  Capsule.name_space_capsule_vehicle_light_launch,
  Capsule.name_space_capsule_vehicle_shadow
}

SpaceshipClone.types_excluded = {
  "rocket-silo-rocket", "cliff", "tile-ghost"
}

SpaceshipClone.types_vehicles = { -- move players inside these vehicles when ships teleport
  "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"
}

SpaceshipClone.types_passengers = { -- move players that are passengers of these vehicles when ships teleport
  "car", "spider-vehicle"
}

SpaceshipClone.mineable_tile_prototypes = nil -- cache of minable tiles to check against hidden tiles
SpaceshipClone.spaced_names = nil -- lists of entities allowed on various surface types
SpaceshipClone.unspaced_names = nil
SpaceshipClone.grounded_names = nil
SpaceshipClone.ungrounded_names = nil

--Checks if a tile isn't minable, so we should clear it as a hidden tile
function SpaceshipClone.check_tile_non_deconstruct(tile)
  if not SpaceshipClone.mineable_tile_prototypes then
    SpaceshipClone.mineable_tile_prototypes = game.get_filtered_tile_prototypes{{filter = "minable"}}
  end
  return not SpaceshipClone.mineable_tile_prototypes[tile]
end

---Builds the arrays of entities that are cared about for the purposes of grounding/spacing.
function SpaceshipClone.build_spaced_grounded_table()
  if SpaceshipClone.spaced_names then return end

  SpaceshipClone.spaced_names = {}
  SpaceshipClone.unspaced_names = {}
  SpaceshipClone.grounded_names = {}
  SpaceshipClone.ungrounded_names = {}
  for name, _ in pairs(game.entity_prototypes) do
    if string.find(name, name_suffix_spaced, 1, true) then
      table.insert(SpaceshipClone.spaced_names, name)
      table.insert(SpaceshipClone.unspaced_names, util.replace(name, name_suffix_spaced, ""))
    elseif string.find(name, name_suffix_grounded, 1, true) then
      table.insert(SpaceshipClone.grounded_names, name)
      table.insert(SpaceshipClone.ungrounded_names, util.replace(name, name_suffix_grounded, ""))
    end
  end
end

--- Grounds or ungrounds entities
--- Used to ensure that entities space buildings can't have space recipes on the ground
--- and similar things. Swaps entities betweened normal, spaced, and grounded versions
---@param from_surface any surface the clone is coming from
---@param to_surface any surface the clone is going to
---@param from_zone any zone the clone is coming from
---@param to_zone any zone the clone is going to
---@param from_area any area on the from_surface the clone is coming from
---@param to_area any area on the to_surface the clone is going to
function SpaceshipClone.ground_unground_entities(from_surface, to_surface, from_zone, to_zone, from_area, to_area)
  SpaceshipClone.build_spaced_grounded_table()
  if Zone.is_space(from_zone) ~= Zone.is_space(to_zone) then
    if Zone.is_space(to_zone) then
      local entities_for_unspaced = to_surface.find_entities_filtered{name = SpaceshipClone.unspaced_names, area = to_area}
      for _, entity in pairs(entities_for_unspaced) do
        swap_structure(entity, entity.name..name_suffix_spaced)
      end
      local entities_for_grounded = to_surface.find_entities_filtered{name = SpaceshipClone.grounded_names, area = to_area}
      for _, entity in pairs(entities_for_grounded) do
        swap_structure(entity, util.replace(entity.name, name_suffix_grounded, ""))
      end
    else
      local entities_for_ungrounded = to_surface.find_entities_filtered{name = SpaceshipClone.ungrounded_names, area = to_area}
      for _, entity in pairs(entities_for_ungrounded) do
        swap_structure(entity, entity.name..name_suffix_grounded)
      end
      local entities_for_spaced = to_surface.find_entities_filtered{name = SpaceshipClone.spaced_names, area = to_area}
      for _, entity in pairs(entities_for_spaced) do
        swap_structure(entity, util.replace(entity.name, name_suffix_spaced, ""))
      end
    end
  end
end

---Enqueues chunk generation requests for the area being cloned to.
---@param spaceship SpaceshipType Spaceship data
---@param clone_from LuaSurface surface to clone from
---@param clone_to LuaSurface surface to clone to
---@param clone_delta any the delta between the spaceship's position on clone_from and the target spaceship position on clone_to
function SpaceshipClone.enqueue_generate_clone_to_area(spaceship, clone_from, clone_to, clone_delta)
  local clone_to_area = {
    left_top = {x = spaceship.known_bounds.left_top.x + clone_delta.dx, y = spaceship.known_bounds.left_top.y + clone_delta.dy},
    right_bottom = {x = spaceship.known_bounds.right_bottom.x + clone_delta.dx, y = spaceship.known_bounds.right_bottom.y + clone_delta.dy},
  }

  local clone_from_zone = Zone.from_surface(clone_from)
  local clone_to_zone = Zone.from_surface(clone_to)

  -- force generate chunks in the area being cloned to
  local x_force_gen_modifier = 0
  if clone_to_zone and clone_to_zone.type == "spaceship" then
    x_force_gen_modifier = SpaceshipObstacles.particle_spawn_range
  end
  local y_force_gen_modifier_sub = 0
  local y_force_gen_modifier_add = 0
  if clone_to_zone and clone_to_zone.type == "spaceship" then
    y_force_gen_modifier_sub = SpaceshipObstacles.particle_spawn_range + 20
    y_force_gen_modifier_add = SpaceshipObstacles.particle_spawn_range + 32
  end
  local requests_made = 0
  for x=clone_to_area.left_top.x-32-x_force_gen_modifier,clone_to_area.right_bottom.x+32+x_force_gen_modifier,32 do
    for y=clone_to_area.left_top.y-32-y_force_gen_modifier_sub,clone_to_area.right_bottom.y+32+y_force_gen_modifier_add,32 do
      clone_to.request_to_generate_chunks({x=x,y=y},1)
      requests_made = requests_made + 1
    end
  end
  return requests_made
end

---Clones a spaceship from its current location to a new location (deletes the original as part of
---the cloning).
---@param spaceship SpaceshipType Spaceship data
---@param clone_from LuaSurface Surface to clone from
---@param clone_to LuaSurface Surface to clone to
---@param clone_delta any Delta between the spaceship's position on clone_from and the target spaceship position on clone_to
---@param post_clone_cb any Callback function to call once the clone completes
function SpaceshipClone.clone(spaceship, clone_from, clone_to, clone_delta, post_clone_cb)
  local tick = game.tick
  local clone_from_area = {
    left_top = {x = spaceship.known_bounds.left_top.x, y = spaceship.known_bounds.left_top.y},
    right_bottom = {x = spaceship.known_bounds.right_bottom.x, y = spaceship.known_bounds.right_bottom.y},
  }
  local clone_to_area = {
    left_top = {x = spaceship.known_bounds.left_top.x + clone_delta.dx, y = spaceship.known_bounds.left_top.y + clone_delta.dy},
    right_bottom = {x = spaceship.known_bounds.right_bottom.x + clone_delta.dx, y = spaceship.known_bounds.right_bottom.y + clone_delta.dy},
  }
  local clone_from_zone = Zone.from_surface(clone_from)
  local clone_to_zone = Zone.from_surface(clone_to)
  local to_is_solid = Zone.is_solid(clone_to_zone)
  local to_is_spaceship = clone_to_zone.type == "spaceship"

  -- flag for cloning in progress
  spaceship.is_cloning = true

  -- if somehow we didn't generate all of the chunks before this call is made, forcibly create them
  clone_to.force_generate_chunk_requests()

  local conditionally_excluded_vehicles = {}
  local vehicle_drivers = {}
  local vehicle_passengers = {}
  local vehicles = clone_from.find_entities_filtered{
    type = SpaceshipClone.types_vehicles,
    area = clone_from_area
  }

  -- Remove vehicles that should not be moved by spaceship from vehicles table
  for index, vehicle in pairs(vehicles) do
    -- Remove vehicle if position is out of spaceship bounds
    local vehicle_position = vehicle.position
    local vehicle_x = math.floor(vehicle_position.x)
    local vehicle_y = math.floor(vehicle_position.y)
    local value = spaceship.known_tiles[vehicle_x] and spaceship.known_tiles[vehicle_x][vehicle_y]
    if value ~= Spaceship.tile_status.floor_console_connected then vehicles[index] = nil end

    -- Exclude the following vehicles by name, sometimes conditionally
    local vehicle_name = vehicle.name
    if vehicle_name == Spectator.name_seat then
      vehicles[index] = nil
    elseif vehicle_name == Capsule.name_space_capsule_vehicle then
      local capsule = Capsule.from_vehicle(vehicle)
      if capsule and capsule.tick_task then
        table.insert(conditionally_excluded_vehicles, vehicle)
        vehicles[index] = nil
      end
    elseif vehicle_name == Capsule.name_space_capsule_scorched_vehicle then
      if not vehicle.surface.find_entity(Capsule.name_space_capsule_scorched_container, vehicle_position) then
        table.insert(conditionally_excluded_vehicles, vehicle)
        vehicles[index] = nil
      end
    end
  end

  -- Iterate over remaining vehicles and unseat their drivers and passengers
  for _, vehicle in pairs(vehicles) do
    local driver = vehicle.get_driver()
    vehicle.set_driver(nil)
    if driver and driver.is_player() then driver = driver.character end -- sets to nil if required
    if driver and driver.valid then
      table.insert(vehicle_drivers, {
        vehicle_name = vehicle.name,
        vehicle_position = vehicle.position,
        driver_name = driver.name,
        driver_position = driver.position
      })
    end
    if util.table_contains(SpaceshipClone.types_passengers, vehicle.type) then
      local passenger = vehicle.get_passenger()
      vehicle.set_passenger(nil)
      if passenger then
        if passenger.is_player() then passenger = passenger.character end -- sets to nil if required
      end
      if passenger and passenger.valid then
        table.insert(vehicle_passengers, {
          vehicle_name = vehicle.name,
          vehicle_position = vehicle.position,
          passenger_name = passenger.name,
          passenger_position = passenger.position
        })
      end
    end
  end

  -- store locomotive status (automatic vs normal)
  local locomotive_settings = {}
  for _, locomotive in pairs(clone_from.find_entities_filtered{
    type = "locomotive",
    area = clone_from_area
  }) do
    local locomotive_x = math.floor(locomotive.position.x)
    local locomotive_y = math.floor(locomotive.position.y)
    local value = spaceship.known_tiles[locomotive_x] and spaceship.known_tiles[locomotive_x][locomotive_y]
    if value == Spaceship.tile_status.floor_console_connected then
      table.insert(locomotive_settings, {
        name = locomotive.name,
        position = locomotive.position,
        manual_mode = locomotive.train.manual_mode
      })
    end
  end

  -- copy the ship tiles
  local change_tiles_zone = {}
  local clone_positions = {}
  for x=spaceship.known_bounds.left_top.x, spaceship.known_bounds.right_bottom.x do
    for y=spaceship.known_bounds.left_top.y, spaceship.known_bounds.right_bottom.y do
      local value = spaceship.known_tiles[x] and spaceship.known_tiles[x][y]
      if value == Spaceship.tile_status.floor_console_connected
      or value == Spaceship.tile_status.bulkhead_console_connected then
        local tile = clone_from.get_tile(x, y)
        if Spaceship.is_floor(tile.name) then
          local to_position = {x = x + clone_delta.dx, y = y + clone_delta.dy}
          table.insert(change_tiles_zone, {name = tile.name, position = to_position})
          local from_position = {x=x, y=y}
          table.insert(clone_positions, from_position)
        else
          -- the tile was changed somehow, the ship will be invalid but it is too late to stop launch
        end
      end
    end
  end
  clone_to.set_tiles(change_tiles_zone, true)

  -- destroy the shield projections
  local destroy_names = {}
  for _, name in pairs(remote.call("shield-projector", "get_sub_entity_names")) do
    table.insert(destroy_names, name)
  end

  -- destroy and restore entities that got left behind from an old version.
  table.insert(destroy_names, mod_prefix .. 'spaceship-circuit-network-restore')

  -- check nearby the ship since we need to capture all shield projector barriers which don't count towards the known_bounds
  local expanded_clone_from_area = util.area_extend(clone_from_area, 15)
  local destroy_entities = clone_from.find_entities_filtered{
    name = destroy_names,
    area = expanded_clone_from_area -- shield projector barriers can be outside the range of the ship bounding box
  }
  for _, entity in pairs(destroy_entities) do
    entity.destroy()
  end

  clone_from.clone_brush{
    source_offset = {0,0},
    destination_offset = {clone_delta.dx,clone_delta.dy},
    destination_surface = clone_to,
    clone_tiles = false,
    clone_entities = true,
    clone_decoratives = false,
    clear_destination_entities = false,
    clear_destination_decoratives = false,
    expand_map = true,
    source_positions = clone_positions
  }

  -- Pause inserters, workaround for https://forums.factorio.com/viewtopic.php?f=58&t=89035
  local condition_entities = clone_to.find_entities_filtered{
    type = Spaceship.types_to_restore,
    area = clone_to_area
  }
  spaceship.entities_to_restore = spaceship.entities_to_restore or {}
  spaceship.entities_to_restore_tick = tick + Spaceship.time_to_restore
  for _, entity in pairs(condition_entities) do
    table.insert(spaceship.entities_to_restore, {
      entity = entity,
      active=entity.active
    })
    entity.active = false
  end

  -- Save all circuit network states
  -- First gather all the combinators
  local cloned_combinators = {}
  for _, pos in pairs(clone_positions) do
    local original_area = {
      left_top = pos,
      right_bottom = { x = pos.x + 1, y = pos.y + 1 }
    }

    local original_combinator = clone_from.find_entities_filtered({ type={'arithmetic-combinator', 'decider-combinator'}, area = original_area })
    if (#original_combinator == 1) then
      local clone_pos = { x = pos.x + clone_delta.dx, y = pos.y + clone_delta.dy }
      local clone_area = {
        left_top = clone_pos,
        right_bottom = { x = clone_pos.x + 1, y = clone_pos.y + 1}
      }

      local cloned_combinator = clone_to.find_entities_filtered({ type={'arithmetic-combinator', 'decider-combinator'}, area = clone_area })

      if (#cloned_combinator == 1) then
        table.insert(cloned_combinators, { original = original_combinator[1], cloned = cloned_combinator[1] })
      else
        Log.trace('Circuit network restore: No matching combinators.')
      end
    end
  end

  -- Now gather all the circuit networks
  local networks_to_restore = {}

  for _, pair in pairs(cloned_combinators) do

    local behavior = pair.original.get_control_behavior()

    if (behavior ~= nil and
      -- Only care about combinators with input
      (
        behavior.type == defines.control_behavior.type.decider_combinator
        or behavior.type == defines.control_behavior.type.arithmetic_combinator
      )
    ) then
      -- Handle red/green networks separately
      local networkRed = behavior.get_circuit_network(defines.wire_type.red, defines.circuit_connector_id.combinator_input)
      local networkGreen = behavior.get_circuit_network(defines.wire_type.green, defines.circuit_connector_id.combinator_input)

      -- NB Only one record is kept for each unique network_id
      if (networkRed and networks_to_restore[networkRed.network_id] == nil) then
        networks_to_restore[networkRed.network_id] = {
          cloned_entity = pair.cloned,
          signals = networkRed.signals,
          wire = defines.wire_type.red
        }
      end

      if (networkGreen and networks_to_restore[networkGreen.network_id] == nil) then
        networks_to_restore[networkGreen.network_id] = {
          cloned_entity = pair.cloned,
          signals = networkGreen.signals,
          wire = defines.wire_type.green
        }
      end
    end
  end

  -- Make our constant combinator entity on the cloned surface
  spaceship.circuits_to_restore = {}

  for _, network in pairs(networks_to_restore) do
    if network.signals ~= nil then
      local restoreCombinator = clone_to.create_entity({
        name = mod_prefix .. 'spaceship-circuit-network-restore',
        position = network.cloned_entity.position,
        -- Not strictly necessary
        force = game.get_player(1).force
      })

      restoreCombinator.connect_neighbour{
        wire = network.wire,
        target_entity = network.cloned_entity,
        target_circuit_id = defines.circuit_connector_id.combinator_input
      }

      -- Record for later processing (see spaceship.lua)
      table.insert(spaceship.circuits_to_restore, {
        entity = restoreCombinator,
        cloned_entity = network.cloned_entity,
        wire = network.wire,
        signals = network.signals
      })
    end
  end

  spaceship.circuits_restore_phase = 1
  spaceship.circuits_to_restore_tick = tick + Spaceship.time_to_restore

  -- clean out of map tiles in the clone area
  local bad_tiles = clone_to.find_tiles_filtered{
    name = {name_out_of_map_tile},
    area = clone_to_area
  }
  local set_tiles = {}
  for _, tile in pairs(bad_tiles) do
    table.insert(set_tiles, {
      position = tile.position,
      name = name_space_tile
    })
    clone_to.set_hidden_tile(tile.position, name_space_tile)
  end
  clone_to.set_tiles(set_tiles)

  -- transfer the ship console
  local old_console = spaceship.console
  local clone_console_position = {
    x = spaceship.console.position.x + clone_delta.dx,
    y = spaceship.console.position.y + clone_delta.dy
  }
  local console_clone = clone_to.find_entity(Spaceship.name_spaceship_console, clone_console_position)
  spaceship.console = console_clone
  spaceship.console_output = nil
  old_console.destroy()

  -- using safe_destroy (which raises the script_raised_destroy) even causes the destruction part of the code take ~10x longer
  -- but if we don't do this (and silently destroy the entities) we can break mod compatibility
  local change_tiles_from = {}
  local change_tiles_to = {}
  local area_table = {left_top = {}, right_bottom = {}}
  for _, clone_position in pairs(clone_positions) do
    local x = clone_position.x
    local y = clone_position.y
    -- part of the spaceship so remove from clone_from surface
    local under_tile = clone_from.get_hidden_tile({x=x,y=y})
    if under_tile == nil or Spaceship.is_floor(under_tile) then
      if to_is_solid then
        under_tile = "landfill" -- fallback
      else
        under_tile = name_space_tile
      end
    end
    table.insert(change_tiles_from, {name = under_tile, position = {x=x,y=y}})
    if SpaceshipClone.check_tile_non_deconstruct(under_tile) then
      clone_from.set_hidden_tile({x=x,y=y}, nil)
    end

    local left_top = area_table.left_top
    local right_bottom = area_table.right_bottom
    left_top.x = x
    left_top.y = y
    right_bottom.x = x + 1
    right_bottom.y = y + 1
    local entities = clone_from.find_entities_filtered{area = area_table}
    for _, entity in pairs(entities) do
      if entity.valid then
        local entity_name = entity.name
        local entity_type = entity.type
        local entity_position = entity.position

        if entity_type == "character" then
          local position = {
            x = entity_position.x + clone_delta.dx,
            y = entity_position.y + clone_delta.dy
          }
          local clone = clone_to.find_entity(entity_name, position)
          if clone and entity.player then
            entity.player.teleport(clone.position, clone_to)
            util.safe_destroy(clone)
          else
            for _, playerdata in pairs(global.playerdata) do
              if playerdata.character == entity then
                playerdata.character = clone
              end
            end
            util.safe_destroy(entity)
          end
        elseif util.table_contains(SpaceshipClone.types_excluded, entity_type)
          or util.table_contains(SpaceshipClone.names_excluded, entity_name)
          or util.table_contains(conditionally_excluded_vehicles, entity) then
          -- this is a cliff, rocket, tile ghost, or something that should not change surfaces.
          -- remove the copy from the target surface instead of destroying the original
          local position = {
            x = entity_position.x + clone_delta.dx,
            y = entity_position.y + clone_delta.dy
          }
          local clone = clone_to.find_entity(entity_name, position)
          if clone then util.safe_destroy(clone) end
        elseif entity_name == mod_prefix .. "spaceship-wall" then
          -- this does not raise any event!
          -- it will silently destroy the entity
          -- if any mod was tracking the ship walls, it will get borked by this
          -- why do potentially other-mod breaking thing?
          -- we do this for performance reasons because raising events is expensive
          entity.destroy()
        else
          util.safe_destroy(entity)
        end
      end
    end
  end
  clone_from.set_tiles(change_tiles_from, true)
  clone_to.set_tiles(change_tiles_to, true)

  -- non-space vehicles must be deactivated in space, and reactivated on land
  local cars = clone_to.find_entities_filtered{
    type = {"car"},
    area = clone_to_area
  }
  for _, car in pairs(cars) do
    if not string.find(car.name, mod_prefix.."space", 1, true) then
      car.active = to_is_solid
    end
  end

  -- Force re-finding all engines on the next engine activation
  spaceship.engines = nil

  -- fix some composite entities that don't clone nicely
  CondenserTurbine.reset_surface(clone_to, clone_to_area)
  Nexus.reset_surface(clone_to, clone_to_area)
  LinkedContainer.update()

  -- ground and unground entities
  SpaceshipClone.ground_unground_entities(clone_from, clone_to, clone_from_zone, clone_to_zone, clone_from_area, clone_to_area)

  -- put players back in vehicles
  for _, vehicle_driver in pairs(vehicle_drivers) do
    local vehicle_position = {x=vehicle_driver.vehicle_position.x+clone_delta.dx,y=vehicle_driver.vehicle_position.y+clone_delta.dy}
    local driver_position = {x=vehicle_driver.driver_position.x+clone_delta.dx,y=vehicle_driver.driver_position.y+clone_delta.dy}
    local vehicle = clone_to.find_entity(vehicle_driver.vehicle_name, vehicle_position)
    local driver = clone_to.find_entity(vehicle_driver.driver_name, driver_position)
    if vehicle and driver then
      vehicle.set_driver(driver)
    end
  end
  for _, vehicle_passenger in pairs(vehicle_passengers) do
    local vehicle_position = {x=vehicle_passenger.vehicle_position.x+clone_delta.dx,y=vehicle_passenger.vehicle_position.y+clone_delta.dy}
    local passenger_position = {x=vehicle_passenger.passenger_position.x+clone_delta.dx,y=vehicle_passenger.passenger_position.y+clone_delta.dy}
    local vehicle = clone_to.find_entity(vehicle_passenger.vehicle_name, vehicle_position)
    local passenger = clone_to.find_entity(vehicle_passenger.passenger_name, passenger_position)
    if vehicle and passenger then
      vehicle.set_passenger(passenger)
    end
  end

  -- set locomotive status (automatic vs normal)
  for _, locomotive in pairs(locomotive_settings) do
    local locomotive_x = math.floor(locomotive.position.x)
    local locomotive_y = math.floor(locomotive.position.y)
    local value = spaceship.known_tiles[locomotive_x] and spaceship.known_tiles[locomotive_x][locomotive_y]
    if value == Spaceship.tile_status.floor_console_connected then
      local position = {x=locomotive.position.x+clone_delta.dx,y=locomotive.position.y+clone_delta.dy}
      local other = clone_to.find_entity(locomotive.name, position)
      if other and other.valid and other.train then
        other.train.manual_mode = locomotive.manual_mode
      end
    end
  end

  if to_is_spaceship then -- remove and spaceship colliding entities
    local invalids = clone_to.find_entities_filtered{
      collision_mask = {global.named_collision_masks.spaceship_collision_layer},
      area = clone_to_area
    }
    for _, invalid in pairs(invalids) do
      util.safe_destroy(invalid)
    end
  end

  -- turn on the new shield projectors
  remote.call("shield-projector", "find_on_surface", {
    surface = clone_to,
    area = clone_to_area
  })

  -- play ship whooshing sound
  for _, player in pairs(game.connected_players) do
    if player.surface.index == clone_from.index or player.surface.index == clone_to.index then
      player.play_sound{path = "se-spaceship-woosh", volume = 1}
    end
  end

  -- flag for cloning in progress
  spaceship.is_cloning = false
  spaceship.surface_lock_timeout = tick + 60

  Spaceship.start_integrity_check(spaceship)
  Spaceship.update_output_combinator(spaceship, tick)

  if clone_from_zone.type ~= "spaceship" then
    -- spaceship tiles have been removed to any in-progress checks are sus
    Spaceship.restart_integrity_checks_on_surface(clone_from)
  end

  -- clean up for after the clone completes
  if post_clone_cb then post_clone_cb(spaceship, clone_from, clone_to, clone_delta) end
end

return SpaceshipClone
