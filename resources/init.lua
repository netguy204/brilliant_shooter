local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'
local rect = require 'rect'

local Timer = require 'Timer'
local DynO = require 'DynO'
local ATLAS = 'resources/default'

local LOAD_TEST = false

local Stars
local Thruster
local Player
local Gun
local Bullet
local Brain
local SimpletonBrain
local HomingBrain
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

local distance = 0
local wall_accel = 10
local wall_distance = -40
local wall_rate = 7
local player_rate = 5
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
   self.test_rect = stage:add_component('CTestDisplay', {w=0, h=0,
                                                         layer=constant.BACKGROUND})
   self.sensor = nil
   self.message = constant.NEXT_EPHEMERAL_MESSAGE()

   local thread = util.fthread(self:bind('on_message'))
   stage:add_component('CScripted', {message_thread=thread})
end

function DeathWall:enable(distance)
   local r = {0, 0, distance, screen_height}
   local w = rect.width(r)
   local h = rect.height(r)
   local c = rect.center(r)

   self.test_rect:w(w)
   self.test_rect:h(h)
   self.test_rect:offset(c)

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
   self.test_rect:w(0)
   self.test_rect:h(0)
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
function Brain:init()
end

function Brain:steering_params(obj)
   local frame_skip = (obj.script and obj.script:frame_skip()) or 1
   local params = {
      force_max = (self.max_force or 0) * frame_skip,
      speed_max = self.max_speed or 0,
      old_angle = 0,
      application_time = world:dt()
   }
   return params
end

HomingBrain = oo.class(Brain)
function HomingBrain:init(opts)
   Brain.init(self)

   opts = opts or {}
   self.max_force = opts.max_force or 300
   self.max_speed = opts.max_speed or 1000
end

function HomingBrain:update(obj)
   local go = obj:go()
   if not go then
      return
   end

   local goal = self.tgt and self.tgt:go()

   -- bit of a hack, select a new enemy
   if not goal then
      self.tgt = util.rand_choice(Enemy.active) or self.tgt
      goal = self.tgt and self.tgt:go()
   end

   local steering = Brain.steering
   steering:begin(self:steering_params(obj))

   if goal then
      steering:pursuit(goal:pos(), goal:vel(), go:pos(), go:vel())
   else
      local center = {screen_width/2, screen_height/2}
      steering:arrival(center, go:pos(), go:vel(), 100)
   end
   steering:complete()
   go:apply_force(steering:force())
end

SimpletonBrain = oo.class(Brain)
function SimpletonBrain:init(tgt_vel, max_force)
   Brain.init(self)

   self.tgt_vel = vector.new(tgt_vel)
   self.max_force = max_force or 10
   self.max_speed = self.tgt_vel:length()
end

function SimpletonBrain:update(obj)
   local steering = Brain.steering
   local go = obj:go()

   steering:begin(self:steering_params(obj))
   steering:apply_desired_velocity(self.tgt_vel, go:vel())
   steering:complete()
   go:apply_force(steering:force())
end

Bullet = oo.class(DynO)
function Bullet:init(pos, opts)
   DynO.init(self, pos)

   -- no need to update ai on every frame
   self.script:frame_skip(1)

   local _art = world:atlas_entry(ATLAS, 'bullet')
   self.dimx = _art.w
   self.dimy = _art.h

   local go = self:go()
   self.sprite = go:add_component('CStaticSprite', {entry=_art,
                                                    angle_offset=math.pi/2})
   self.brain = opts.brain

   self:add_sensor({fixture={type='rect',
                             w=self.dimx, h=self.dimy,
                             sensor=true}})
   self.timer = Timer(go)
   self.timer:reset(opts.lifetime or 20, self:bind('terminate'))
   self.psys = bthruster:activate(self)
end

function Bullet:update()
   local go = self:go()
   if not go then
      return
   end

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
   self.make_bullet_brain = function()
      return HomingBrain()
   end
end

function Gun:fire(owner, offset)
   local shoot = function()
      local go = owner:go()
      if go then
         offset = offset or {0,0}
         local pos = vector.new(go:pos()) + offset
         self.bullet_kind(pos, {brain=self.make_bullet_brain()})
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
   self.sprite = go:add_component('CStaticSprite', {entry=_art})
   self.brain = SimpletonBrain({-200, 0}, 10)
   self:add_collider({fixture={type='rect', w=self.dimx, h=self.dimy}})
end

function Enemy:terminate()
   DynO.terminate(self)
   util.table_remove(Enemy.active, self)
end

function Enemy:update()
   local go = self:go()
   self.brain.max_speed = Enemy.max_speed
   self.brain:update(self)
   terminate_if_offscreen(self)
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

   if input.action1 or LOAD_TEST then
      self.gun:fire(self, {self.dimy/2, 0})
   end

   -- the wall is always speeding up
   wall_rate = wall_rate + wall_accel * dt

   wall_distance = wall_distance + (wall_rate - player_rate) * dt
   if wall_distance > 0 then
      death_wall:enable(wall_distance)
   else
      death_wall:disable()
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

function level_init()
   util.install_basic_keymap()
   world:gravity({0,0})

   local cam = stage:find_component('Camera', nil)
   cam:pre_render(util.fthread(background))

   player = Player({screen_width/3, screen_height/2})
   spawner = Spawner(1, {Pawn, Pawn, Boss})
   stars = Stars(stage)
   stars:set_vel({-player_rate, 0}, {-0.5 * player_rate, 0})

   exploder = ExplosionManager(5)
   bthruster = BThrusterManager(40)
   death_wall = DeathWall()

   if not LOAD_TEST then
      local songs = {'resources/DST-1990.ogg', 'resources/DST-AlphaTron.ogg',
                     'resources/DST-AngryMod.ogg'}
      util.loop_music(util.rand_shuffle(songs))
   end

   local expl = {'resources/expl1.ogg', 'resources/expl3.ogg'}
   load_sfx('expl', expl)
end
