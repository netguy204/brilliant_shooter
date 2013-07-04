local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

local Timer = require 'Timer'
local DynO = require 'DynO'
local ATLAS = 'resources/default'

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
local Spawner
local Explosion
local ExplosionManager
local exploder

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
                       refresh={-_art.w, screen_height + _art.h,
                                screen_width + _art.w, screen_height + _art.h},
                       minv={0, 0},
                       maxv={0, 0}}},
              {name='PSRandColorInitializer',
               params={min_color={0.8, 0.8, 0.8, 0.2},
                       max_color={1.0, 1.0, 1.0, 1.0}}},
              {name='PSRandScaleInitializer',
               params={min_scale=0.2,
                       max_scale=0.6}},
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
          {n=100,
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
end

function Thruster:set_flame(dir, rate)
   local rect = nil
   local vel = nil
   local s = 4
   local v = 1000
   local dx2 = self.dimx / 2
   local dy2 = self.dimy / 2

   if dir[1] > 0 then
      rect = {dx2 - s, -dy2, dx2 + s, dy2}
      vel = {v, 0}
   elseif dir[1] < 0 then
      rect = {-dx2 - s, -dy2, -dx2 + s, dy2}
      vel = {-v, 0}
   elseif dir[2] > 0 then
      rect = {-dx2, dy2 - s, dx2, dy2 + s}
      vel = {0, v}
   elseif dir[2] < 0 then
      rect = {-dx2, -dy2 - s, dx2, -dy2 + s}
      vel = {0, -v}
   end

   if rect and vel then
      self.psbox:initial(rect)
      self.psbox:refresh(rect)
      self.psbox:minv(vel)
      self.psbox:maxv(vel)
   end
   self.activator:rate(rate)
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

ExplosionManager = oo.class(oo.Object)
function ExplosionManager:init(n, dim, speed)
   self.systems = {}
   self.dim = dim
   self.speed = speed

   for i = 1,n do
      table.insert(self.systems, Explosion(0.2))
   end
end

function ExplosionManager:explode(pos)
   local expl = table.remove(self.systems, 1)
   expl:activate(pos, self.dim, self.dim, self.speed)
   table.insert(self.systems, expl)
end

local function terminate_if_offscreen(self)
   local fuzz = 128
   local pos = self:go():pos()

   -- kill on screen exit
   if pos[1] > screen_width + fuzz or pos[1] < -fuzz or pos[2] > screen_height + fuzz or pos[2] < -fuzz then
      self:terminate()
   end
end

Brain = oo.class(oo.Object)
Brain.steering = world:create_object('Steering')
function Brain:init()
end

HomingBrain = oo.class(Brain)
function HomingBrain:init(tgt)
   self.tgt = tgt
end

function HomingBrain:update(obj)
   local goal = nil

end

SimpletonBrain = oo.class(oo.Object)
function SimpletonBrain:init(tgt_vel, max_force)
   Brain.init(self)

   self.tgt_vel = vector.new(tgt_vel)
   self.max_force = max_force or 10
end

function SimpletonBrain:update(obj)
   local steering = Brain.steering
   local go = obj:go()
   local params = {
      force_max = self.max_force,
      speed_max = self.tgt_vel:length(),
      old_angle = 0,
      application_time = world:dt()
   }
   steering:begin(params)
   steering:apply_desired_velocity(self.tgt_vel, go:vel())
   steering:complete()
   go:apply_force(steering:force())
end



Bullet = oo.class(DynO)
function Bullet:init(pos, opts)
   DynO.init(self, pos)

   local go = self:go()
   go:add_component('CTestDisplay', {w=8,h=8})
   self.brain = opts.brain
   self:add_sensor({fixture={type='rect',
                             w=8, h=8,
                             sensor=true}})
   self.timer = Timer(go)
   self.timer:reset(opts.lifetime or 20, self:bind('terminate'))
end

function Bullet:update()
   self.brain:update(self)
   terminate_if_offscreen(self)
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
      return SimpletonBrain({0, 500}, 1000)
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
function Enemy:init(pos)
   DynO.init(self, pos)
   table.insert(Enemy.active, self)
end

function Enemy:terminate()
   DynO.terminate(self)
   util.table_remove(Enemy.active, self)
end

Pawn = oo.class(Enemy)
function Pawn:init(pos)
   Enemy.init(self, pos)

   self:go():add_component('CTestDisplay', {w=16,h=16})
   self.brain = SimpletonBrain({0, -200}, 10)
   self:add_collider({fixture={type='rect', w=16, h=16}})
end

function Pawn:update()
   self.brain:update(self)
   terminate_if_offscreen(self)
end

function Pawn:colliding_with(other)
   if other:is_a(Bullet) then
      exploder:explode(self:go():pos())
      self:terminate()
      other:terminate()
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
   -- for now, just spawn at the top of the screen
   local e = util.rand_choice(self.mix)
   e({util.rand_between(0,screen_width), screen_height})

   self:reset()
end

Player = oo.class(DynO)
function Player:init(pos)
   DynO.init(self, pos)

   local go = self:go()
   self.dim = 64
   self.gfx = go:add_component('CTestDisplay',
                                    {w=self.dim,
                                     h=self.dim})
   self.speed = 300
   self.steering = world:create_object('Steering')
   self.lr_thruster = Thruster(go, self.dim, 16)
   self.ud_thruster = Thruster(go, 16, self.dim)
   self.gun = Gun()
end

function Player:update()
   local input = util.input_state()
   local leftright = self.speed * input.leftright
   local updown = self.speed * input.updown

   local go = self:go()
   local steering = self.steering

   local params = {
      force_max = 10000,
      speed_max = self.speed,
      old_angle = 0,
      application_time = world:dt()
   }

   steering:begin(params)
   local desired_vel = vector.new({leftright, updown})
   steering:apply_desired_velocity(desired_vel, go:vel())
   steering:complete()
   go:apply_force(steering:force())

   local zero = vector.new({0,0})
   if math.abs(desired_vel[1]) > 0 then
      self.lr_thruster:set_flame({-desired_vel[1],0}, 10000)
   else
      self.lr_thruster:set_flame({0,0}, 0)
   end

   if math.abs(desired_vel[2]) > 0 then
      self.ud_thruster:set_flame({0,-desired_vel[2]}, 10000)
   else
      self.ud_thruster:set_flame({0,0}, 0)
   end

   if input.action1 then
      self.gun:fire(self, {0, self.dim/2})
   end
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

   local player = Player({screen_width/2, screen_height/2})
   local spawner = Spawner(1, {Pawn})

   local stars = Stars(stage)
   stars:set_vel({0, -20}, {0, -10})

   exploder = ExplosionManager(5, 16, 100)
end
