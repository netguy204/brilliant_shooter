local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'
local rect = require 'rect'

local Timer = require 'Timer'
local DynO = require 'DynO'
local ATLAS = 'resources/default'
local stash = require 'stash'

local LOAD = 'load'
local game_state -- = LOAD -- load testing

local Stars
local Thruster
local Player
local Gun
local Bullet
local Brain
local SimpletonBrain
local HomingBrain
local SeekBrain
local Pawn
local Enemy
local Boss
local Spawner
local Explosion
local PSManager
local ExplosionManager
local BThruster
local BThrusterManager
local DeathWall

local exploder
local bthruster
local player
local stars
local spawner
local death_wall
local score_display
local center_go

local distance = 0
local wall_accel = 10
local wall_distance = -40
local wall_rate = 7
local player_rate = 40
local enemy_spawn_rate = 1

local sfx = {}

function increase_wall_rate(points)
   local factor = 5
   wall_rate = wall_rate + factor * points
   spawner.rate = spawner.rate + (points * factor) / 100
end

function change_player_rate(rate)
   local increase = rate / 10
   player_rate = player_rate + increase
   Enemy.max_speed = Enemy.max_speed + increase
   stars:set_vel({-player_rate, 0}, {-0.5 * player_rate, 0})
end

function load_sfx(kind, names)
   sfx[kind] = {}
   for ii, name in ipairs(names) do
      table.insert(sfx[kind], world:get_sound(name, 1.0))
   end
end

function play_sfx(kind)
   local snd = util.rand_choice(sfx[kind])
   world:play_sound(snd, 1)
end

Stars = oo.class(oo.Object)
function Stars:init(go)
   local _art = world:atlas_entry(ATLAS, 'star')
   local params =
      {def=
          {n=200,
           layer=constant.BACKDROP,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_art}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0, 0}}},
              {name='PSBoxInitializer',
               params={initial={-_art.w, -_art.h,
                                screen_width + _art.w,
                                screen_height + _art.h},
                       refresh={screen_width + _art.w, - _art.h,
                                screen_width + _art.w, screen_height + _art.h},
                       minv={0, 0},
                       maxv={0, 0}}},
              {name='PSRandColorInitializer',
               params={min_color={0.8, 0.8, 0.8, 0.2},
                       max_color={1.0, 1.0, 1.0, 1.0}}},
              {name='PSRandScaleInitializer',
               params={min_scale=0.1,
                       max_scale=0.3}},
              {name='PSBoxTerminator',
               params={rect={-_art.w*2, -_art.h*2,
                             screen_width + _art.w * 2,
                             screen_height + _art.h * 2}}}}}}
   local system = go:add_component('CParticleSystem', params)
   self.psbox = system:def():find_component('PSBoxInitializer')
end

function Stars:set_vel(mnvel, mxvel)
   self.psbox:minv(mnvel)
   self.psbox:maxv(mxvel)
end

Thruster = oo.class(oo.Object)
function Thruster:init(go, dimx, dimy)
   local _smoke = world:atlas_entry(ATLAS, 'steam')
   local params =
      {def=
          {n=20,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_smoke}},
           activator={name='PSConstantRateActivator',
                      params={rate=10000}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,0}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=0.4,
                       max_scale=1.0}},
              {name='PSFireColorUpdater',
               params={max_life=0.3,
                       start_temperature=9000,
                       end_temperature=500}},
              {name='PSBoxInitializer',
               params={initial={-16,-34,16,-30},
                       refresh={-16,-34,16,-30},
                       minv={0,1000},
                       maxv={0,1000}}},
              {name='PSTimeInitializer',
               params={min_life=0.2,
                       max_life=0.4}},
              {name='PSTimeTerminator'}}}}

   local system = go:add_component('CParticleSystem', params)
   local activator = system:def():find_component('PSConstantRateActivator')
   local psbox = system:def():find_component('PSBoxInitializer')

   self.dimx = dimx
   self.dimy = dimy
   self.activator = activator
   self.psbox = psbox
   self.speed = 100
end

function Thruster:set_flame(dir, rate)
   local rect = nil
   local vel = nil
   local s = 4
   local dx2 = self.dimx / 2
   local dy2 = self.dimy / 2

   if dir[1] > 0 then
      rect = {dx2 - s, -dy2, dx2 + s, dy2}
   elseif dir[1] < 0 then
      rect = {-dx2 - s, -dy2, -dx2 + s, dy2}
   elseif dir[2] > 0 then
      rect = {-dx2, dy2 - s, dx2, dy2 + s}
   elseif dir[2] < 0 then
      rect = {-dx2, -dy2 - s, dx2, -dy2 + s}
   end

   if rect then
      local vel = vector.new(dir):norm() * self.speed
      self.psbox:initial(rect)
      self.psbox:refresh(rect)
      self.psbox:minv(vel)
      self.psbox:maxv(vel)
   end
   self.activator:rate(rate)
end

PSManager = oo.class(oo.Object)
function PSManager:init(n, ctor)
   self.n = n
   self.systems = {}
   for i = 1,n do
      table.insert(self.systems, ctor())
   end
end

function PSManager:activate(...)
   local psys = table.remove(self.systems, 1)
   psys:activate(...)
   table.insert(self.systems, psys)
   return psys
end

Explosion = oo.class(oo.Object)
function Explosion:init(lifetime)
   self.lifetime = lifetime

   local _smoke = world:atlas_entry(ATLAS, 'steam')
   local params =
      {def=
          {n=50,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_smoke}},
           activator={name='PSConstantRateActivator',
                      params={rate=0}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,0}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=0.4,
                       max_scale=1.0}},
              {name='PSFireColorUpdater',
               params={max_life=0.3,
                       start_temperature=9000,
                       end_temperature=500}},
              {name='PSBoxInitializer',
               params={initial={-16,-34,16,-30},
                       refresh={-16,-34,16,-30},
                       minv={0,0},
                       maxv={0,0}}},
              {name='PSTimeInitializer',
               params={min_life=0.2,
                       max_life=0.4}},
              {name='PSTimeTerminator'}}}}

   local system = stage:add_component('CParticleSystem', params)
   local activator = system:def():find_component('PSConstantRateActivator')
   local psbox = system:def():find_component('PSBoxInitializer')

   self.activator = activator
   self.psbox = psbox
   self.timer = Timer()
end

function Explosion:activate(center, w, h, speed)
   local rect = {center[1] - w/2, center[2] - h/2, center[1] + w/2, center[2] + h/2}
   self.psbox:initial(rect)
   self.psbox:refresh(rect)
   self.psbox:minv({-speed, -speed})
   self.psbox:maxv({speed, speed})
   self.activator:rate(1000)
   local term = function()
      self.activator:rate(0)
   end
   self.timer:reset(self.lifetime, term)
end

ExplosionManager = oo.class(PSManager)
function ExplosionManager:init(n)
   local ctor = function()
      return Explosion(0.2)
   end

   PSManager.init(self, n, ctor)
end

BThruster = oo.class(oo.Object)
function BThruster:init()
   local _smoke = world:atlas_entry(ATLAS, 'steam')
   local params =
      {def=
          {n=10,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_smoke}},
           activator={name='PSConstantRateActivator',
                      params={rate=0}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,0}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=0.4,
                       max_scale=0.7}},
              {name='PSRandColorInitializer',
               params={min_color={0.4, 0.4, 0.8, 0.8},
                       max_color={0.4, 0.4, 1.0, 1.0}}},
              {name='PSBoxInitializer',
               params={initial={-16,-34,16,-30},
                       refresh={-16,-34,16,-30},
                       minv={0,1000},
                       maxv={0,1000}}},
              {name='PSTimeInitializer',
               params={min_life=0.2,
                       max_life=0.3}},
              {name='PSTimeTerminator'}}}}

   local system = stage:add_component('CParticleSystem', params)
   local activator = system:def():find_component('PSConstantRateActivator')
   local psbox = system:def():find_component('PSBoxInitializer')

   self.activator = activator
   self.psbox = psbox
end

function BThruster:activate(owner, center, rate, dimx, dimy, vel)
   -- this is just a claiming call
   if not center then
      self.owner = owner
      return
   end

   if self.owner ~= owner then
      return -- we've been claimed by someone else
   end

   self.activator:rate(rate)

   if rate > 0 then
      local rect = rect.centered(center, dimx, dimy)
      self.psbox:initial(rect)
      self.psbox:refresh(rect)
      self.psbox:minv(vel)
      self.psbox:maxv(vel)
   end
end

BThrusterManager = oo.class(PSManager)
function BThrusterManager:init(n)
   local ctor = function()
      return BThruster()
   end
   return PSManager.init(self, n, ctor)
end

DeathWall = oo.class(oo.Object)
function DeathWall:init()
   local _smoke = world:atlas_entry(ATLAS, 'smoke')
   local params =
      {def=
          {layer=constant.BACKGROUND,
           n=800,
           renderer={name='PSC_E2SystemRenderer',
                     params={entry=_smoke}},
           activator={name='PSConstantRateActivator',
                      params={rate=0}},
           components={
              {name='PSConstantAccelerationUpdater',
               params={acc={0,0}}},
              {name='PSTimeAlphaUpdater',
               params={time_constant=1.0,
                       max_scale=3.0}},
              {name='PSRandColorInitializer',
               params={min_color={0.4, 0.8, 0.4, 0.8},
                       max_color={0.4, 1.0, 0.4, 1.0}}},
              {name='PSBoxInitializer',
               params={initial={-16,-34,16,-30},
                       refresh={-16,-34,16,-30},
                       minv={200,-30},
                       maxv={300,30}}},
              {name='PSBoxTerminator',
               params={rect={-16,34,16,-30}}},
              {name='PSTimeInitializer',
               params={min_life=0.6,
                       max_life=1.2}},
              {name='PSTimeTerminator'}}}}

   local system = stage:add_component('CParticleSystem', params)
   self.activator = system:def():find_component('PSConstantRateActivator')
   self.psbox = system:def():find_component('PSBoxInitializer')
   self.psterm = system:def():find_component('PSBoxTerminator')

   self.sensor = nil
   self.message = constant.NEXT_EPHEMERAL_MESSAGE()

   local thread = util.fthread(self:bind('on_message'))
   stage:add_component('CScripted', {message_thread=thread})
end

function DeathWall:enable(distance)
   local r = {-200, -100, distance-100, screen_height+100}
   local r2 = {-200, -100, distance-10, screen_height+100}

   local w = rect.width(r)
   local h = rect.height(r)
   local c = rect.center(r)

   self.psbox:initial(r)
   self.psbox:refresh(r)
   self.psterm:rect(r2)
   self.activator:rate(10000)

   if self.sensor then
      self.sensor:delete_me(1)
   end

   self.sensor = stage:add_component('CSensor', {kind=self.message,
                                                 fixture={type='rect',
                                                          sensor=true,
                                                          center=c,
                                                          w=w,
                                                          h=h}})
end

function DeathWall:on_message()
   local collisions = stage:has_message(self.message)

   if collisions then
      for ii, msg in ipairs(collisions) do
         local obj = DynO.find(msg.source)

         if obj then
            if obj:is_a(Enemy) then
               obj:explode()
               increase_wall_rate(obj.hp)
            elseif obj:is_a(Bullet) then
               obj:explode()
            elseif obj:is_a(Player) then
               obj:explode()
            end
         end
      end
   end
end

function DeathWall:disable()
   self.activator:rate(0)

   if self.sensor then
      self.sensor:delete_me(1)
      self.sensor = nil
   end
end

local function terminate_if_offscreen(self)
   local fuzz = 128
   local pos = self:go():pos()

   -- kill on screen exit
   if pos[1] > screen_width + fuzz or pos[1] < -fuzz or pos[2] > screen_height + fuzz or pos[2] < -fuzz then
      self:terminate()
      return true
   end
   return false
end

Brain = oo.class(oo.Object)
Brain.steering = world:create_object('Steering')
function Brain:init(dyno)
   self.dyno = dyno
end

function Brain:go()
   return self.dyno:go()
end

function Brain:update()
end

function Brain:steering_params()
   local params = {
      force_max = self.force_max or 0,
      speed_max = self.speed_max or 0,
      old_angle = 0,
      application_time = world:dt()
   }
   return params
end

function Brain:params(updates)
   for k, v in pairs(updates) do
      self[k] = v
   end
   self.brain:params(self:steering_params())
end

HomingBrain = oo.class(Brain)
function HomingBrain:init(dyno)
   Brain.init(self, dyno)
   self.force_max = 300
   self.speed_max = 1000

   local params = self:steering_params()
   self.brain = world:create_object('PursuitBrain')
   self:go():add_component('CBrain', {brain=self.brain})
   self:target(nil)
end

function HomingBrain:target(obj)
   self.brain:tgt((obj and obj:go()) or center_go)
   self.brain:params(self:steering_params())
end

function HomingBrain:update()
   if not (self.tgt and self.tgt:go()) then
      self.tgt = util.rand_choice(Enemy.active) or self.tgt
      self:target(self.tgt)
   end
end

SeekBrain = oo.class(Brain)
function SeekBrain:init(dyno, tgt)
   Brain.init(self, dyno)
   self.brain = world:create_object('SeekBrain')
   self.brain:tgt(tgt)
   self.brain:params(self:steering_params())
   self:go():add_component('CBrain', {brain=self.brain})
end

SimpletonBrain = oo.class(Brain)
function SimpletonBrain:init(dyno, tgt_vel, force_max)
   Brain.init(self, dyno)

   tgt_vel = vector.new(tgt_vel)
   self.force_max = force_max or 10
   self.speed_max = tgt_vel:length()
   self.brain = world:create_object('VelocityBrain')
   self.brain:tgt_vel(tgt_vel)
   self.brain:params(self:steering_params())
   self:go():add_component('CBrain', {brain=self.brain})
end

Bullet = oo.class(DynO)
function Bullet:init(pos)
   DynO.init(self, pos)

   -- no need to update ai on every frame
   self.script:frame_skip(5)

   local _art = world:atlas_entry(ATLAS, 'bullet')
   self.dimx = _art.w
   self.dimy = _art.h

   local go = self:go()
   self.sprite = go:add_component('CStaticSprite', {entry=_art,
                                                    angle_offset=math.pi/2})
   self:add_sensor({fixture={type='rect',
                             w=self.dimx, h=self.dimy,
                             sensor=true}})
   self.timer = Timer(go)
   self.timer:reset(20, self:bind('terminate'))
   self.psys = bthruster:activate(self)
end

function Bullet:update()
   local go = self:go()

   local vel = vector.new(go:vel())
   local angle = vel:angle()
   go:angle(angle)

   self.brain:update(self)
   local pos = vector.new(go:pos())
   local aft = pos - (vel:norm() * self.dimy)
   self.psys:activate(self, aft, 100, 3, 3,
                      vel:norm() * (-100))

end

function Bullet:terminate()
   local go = self:go()
   if go then
      self.psys:activate(self, go:pos(), 0)
   end
   DynO.terminate(self)
end

function Bullet:explode()
   exploder:activate(self:go():pos(), self.dimx, self.dimy, 20)
   play_sfx('expl')
   self:terminate()
end

function Bullet:colliding_with(other)
   -- we're a sensor so we need to hand off this message
   if not other:is_a(Bullet) then
      other:colliding_with(self)
   end
end

Gun = oo.class(oo.Object)

function Gun:init(bullet_kind)
   self.bullet_kind = bullet_kind or Bullet

   self.hz = 10
   self.timer = Timer(stage)
   self.add_bullet_brain = function(bullet)
      bullet.brain = HomingBrain(bullet)
   end
end

function Gun:fire(owner, offset)
   local shoot = function()
      local go = owner:go()
      if go then
         offset = offset or {0,0}
         local pos = vector.new(go:pos()) + offset
         local bullet = self.bullet_kind(pos)
         self.add_bullet_brain(bullet)
      end
   end
   self.timer:maybe_set(1.0 / self.hz, shoot)
end

Enemy = oo.class(DynO)
Enemy.active = {}
Enemy.max_speed = 100
function Enemy:init(pos, art)
   DynO.init(self, pos)
   table.insert(Enemy.active, self)

   local _art = world:atlas_entry(ATLAS, art)
   self.dimx = _art.w
   self.dimy = _art.h

   local go = self:go()
   go:vel({-Enemy.max_speed, 0})
   go:angle(math.pi/2)
   self.sprite = go:add_component('CStaticSprite', {entry=_art,
                                                    angle_offset=math.pi/2})

   self.brain = SimpletonBrain(self, {-200, 0}, 10)
   self:add_collider({fixture={type='rect', w=self.dimx, h=self.dimy}})
end

function Enemy:terminate()
   DynO.terminate(self)
   util.table_remove(Enemy.active, self)
end

function Enemy:update()
   local go = self:go()
   if self.brain then
      self.brain.max_speed = Enemy.max_speed
      self.brain:update(self)
   end
   if (not self.long_lived) and terminate_if_offscreen(self) and go:pos()[1] < 0 then
      increase_wall_rate(self.hp)
   end

   go:angle(vector.new(go:vel()):angle())
end

function Enemy:explode()
   exploder:activate(self:go():pos(), self.dimx, self.dimy, 100)
   play_sfx('expl')
   self:terminate()
end

Pawn = oo.class(Enemy)
function Pawn:init(pos)
   Enemy.init(self, pos, 'pawn')
   self.hp = 1
end

function Pawn:colliding_with(other)
   if other:is_a(Bullet) then
      self:explode()
      other:terminate()
   end
end

Boss = oo.class(Enemy)
function Boss:init(pos)
   Enemy.init(self, pos, 'boss')
   self.hp = 5
end

function Boss:colliding_with(other)
   if other:go() and other:is_a(Bullet) then
      self.hp = self.hp - 1

      if self.hp == 0 then
         self:explode()
         other:terminate()
      else
         other:explode()
      end
   end
end

Spawner = oo.class(oo.Object)
function Spawner:init(rate, mix)
   self.rate = rate
   self.mix = mix
   self.timer = Timer()
   self:reset()
end

function Spawner:reset()
   local next_time = util.rand_exponential(self.rate)
   self.timer:reset(next_time, self:bind('spawn'))
end

function Spawner:spawn()
   local e = util.rand_choice(self.mix)
   e({screen_width, util.rand_between(0,screen_height)})
   self:reset()
end

Player = oo.class(DynO)
function Player:init(pos)
   DynO.init(self, pos)

   local go = self:go()
   local _art = world:atlas_entry(ATLAS, 'player')

   self.dimx = _art.w
   self.dimy = _art.h

   self.gfx = go:add_component('CStaticSprite', {entry=_art})
   go:angle(math.pi/2)
   self.speed = 700
   self.steering = world:create_object('Steering')
   self.lr_thruster = Thruster(go, self.dimy, 16)
   self.ud_thruster = Thruster(go, 16, self.dimx)
   self.gun = Gun()
   go:add_component('CSensor', {fixture={type='rect',
                                         sensor=true,
                                         w=self.dimx,
                                         h=self.dimy}})
end

function Player:update()
   local input = util.input_state()
   local leftright = self.speed * input.leftright
   local updown = self.speed * input.updown

   local go = self:go()
   local steering = self.steering
   local dt = world:dt()

   local params = {
      force_max = 10000,
      speed_max = self.speed,
      old_angle = 0,
      application_time = dt
   }

   steering:begin(params)
   local desired_vel = vector.new({0, updown})
   steering:apply_desired_velocity(desired_vel, go:vel())
   steering:complete()
   go:apply_force(steering:force())

   local zero = vector.new({0,0})
   if math.abs(leftright) > 0 then
      change_player_rate(leftright * dt)
      self.lr_thruster:set_flame({-leftright,0}, 10000)
   else
      self.lr_thruster:set_flame({0,0}, 0)
   end

   if math.abs(desired_vel[2]) > 0 then
      self.ud_thruster:set_flame({0,-desired_vel[2]}, 10000)
   else
      self.ud_thruster:set_flame({0,0}, 0)
   end

   if input.action1 or game_state == LOAD then
      self.gun:fire(self, {self.dimy/2, 0})
   end

   -- the wall is always speeding up
   wall_rate = wall_rate + wall_accel * dt

   wall_distance = wall_distance + (wall_rate - player_rate) * dt
   if game_state ~= LOAD then
      if wall_distance > -50 then
         death_wall:enable(wall_distance)
      else
         death_wall:disable()
      end
   end
end

function Player:explode()
   for ii = 1,exploder.n do
      exploder:activate(self:go():pos(), self.dimx, self.dimy, 200)
   end
   play_sfx('expl')
   self:terminate()
end

local czor = world:create_object('Compositor')

function background()
   czor:clear_with_color(util.rgba(0,0,0,0))
end

local font = nil
function default_font()
   if not font then
      local characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!?,\'"'
      font = world:create_object('Font')
      font:load(world:atlas(ATLAS), 'visitor', characters)
      font:scale(3)
      font:set_char_width('i', 3)
      font:set_char_lead('i', -2)
      font:set_char_width('.', 3)
      font:set_char_lead('.', -2)
      font:set_char_width(',', 3)
      font:set_char_lead(',', -3)
      font:word_separation(5)
   end
   return font
end

function start_music()
   local songs = {'resources/DST-1990.ogg', 'resources/DST-AlphaTron.ogg',
                  'resources/DST-AngryMod.ogg'}
   util.loop_music(util.rand_shuffle(songs))
end

function screen_sequence(fns)
   local trigger = util.rising_edge_trigger(false)
   local count = util.count(fns)
   local current = 1

   fns[current]()
   local thread = function(go, comp)
      local input = util.input_state()
      if trigger(input.action1) then
         current = current + 1
         if current == count then
            comp:delete_me(1)
         end
         fns[current]()
      end
   end

   if count > 1 then
      local comp = stage:add_component('CScripted', {update_thread=util.fthread(thread)})
   end
end

function story_main()
   local story = {
      [[In AD 2001, the Glorbaag began discreetly extracting Mertekron from
the rich lower atmospheres of Jupiter. Earth was unaware.]],

      [[The Mertekron market exploded in 2059 when the full cranial media
emersion headgear was introduced. Every Glorbaag needed a visor and
Mertekron was a critical component.

Ambitious and less discrete raw material corporations arrived at
Jupiter and began extraction in earnest.]],

      [[Earth became aware and dealt violently with the territorial breach.
So began the 200 year war.]],

      [[The year is 2260. You are all that is left of Earth System Guard.
You have penetrated the Glorbaag solar system and ignited their sun.
The resulting blow will be decisive.

All you need to do now is escape alive.]]
   }

   local font = default_font()
   local text = stage:add_component('CDrawText', {font=font})

   local press = 'Press Z'
   stage:add_component('CDrawText', {font=font,
                                     color={0.6, 0.6, 1.0, 0.8},
                                     message=press,
                                     offset={(screen_width - font:string_width(press))/2,
                                             font:line_height()}})
   local _jupiter = world:atlas_entry(ATLAS, 'jupiter')
   local planet = stage:add_component('CStaticSprite', {entry=_jupiter,
                                                        offset={screen_width/2,
                                                                screen_height/2},
                                                        layer=constant.BACKGROUND})

   local spawn_harvester = function(pos, kind)
      local ship = kind(pos)
      local center_brain = SeekBrain(ship, {screen_width/2, screen_height/2})
      center_brain:params({speed_max = 100, force_max = 100 })
      ship:go():vel({0,0})
      ship.long_lived = true
      ship.brain = center_brain
   end

   local text_chunk = function(str)
      local fn = function()
         local sw = font:string_width(util.split(str, "\n")[1])
         local offset = (screen_width - sw) / 2
         text:message(str)
         text:offset({offset,screen_height-font:line_height()*2})
      end
      return fn
   end

   local seq = {
      function()
         text_chunk(story[1])()
         spawn_harvester({-100,screen_height/2}, Pawn)
      end,
      function()
         text_chunk(story[2])()
         spawn_harvester({-100,-100}, Boss)
         spawn_harvester({-100,screen_height+100}, Boss)
         spawn_harvester({-100,300}, Boss)
         spawn_harvester({-600,300}, Boss)
      end,
      function()
         text_chunk(story[3])()
         for ii=1,25 do
            local bullet = Bullet({screen_width + 100+ii*100, ii*100})
            bullet.brain = HomingBrain(bullet)
         end
      end,
      text_chunk(story[4]),
      function()
         stash:set('mode', 'game')
         reset_world()
      end
   }

   screen_sequence(seq)
end

function game_main()
   player = Player({screen_width/3, screen_height/2})
   spawner = Spawner(1, {Pawn, Pawn, Pawn, Boss})
   stars:set_vel({-player_rate, 0}, {-0.5 * player_rate, 0})

   if game_state ~= LOAD then
      death_wall = DeathWall()
   end
end

function level_init()
   world:gravity({0,0})
   math.randomseed(os.time())
   util.install_basic_keymap()

   center_go = world:create_go()
   center_go:pos({screen_width/2, screen_height/2})

   local expl = {'resources/expl1.ogg', 'resources/expl3.ogg'}
   load_sfx('expl', expl)
   exploder = ExplosionManager(5)
   bthruster = BThrusterManager(40)

   if game_state ~= LOAD then
      game_state = stash:get('mode', 'story')
      start_music()
   end

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(background))
   stars = Stars(stage)
   stars:set_vel({-40, 0}, {-20, 0})

   local mains = {
      story = story_main,
      game = game_main,
      load = game_main
   }

   local main = mains[game_state]
   main()
end

function test_init()
   real_init()
   local timer = Timer()
   timer:reset(1, reset_world)
end
