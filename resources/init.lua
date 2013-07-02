local oo = require 'oo'
local util = require 'util'
local vector = require 'vector'
local constant = require 'constant'

local Timer = require 'Timer'
local DynO = require 'DynO'
local ATLAS = 'resources/default'

local Player = oo.class(DynO)
function Player:init(pos)
   DynO.init(self, pos)
   self.dim = 64
   self.gfx = self.go:add_component('CTestDisplay',
                                    {w=self.dim,
                                     h=self.dim})
   self.speed = 100
   self.max_impulse = 90
   self.steering = world:create_object('Steering')

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

   local system = self.go:add_component('CParticleSystem', params)
   local activator = system:def():find_component('PSConstantRateActivator')
   local psbox = system:def():find_component('PSBoxInitializer')
   self.activator = activator
   self.psbox = psbox
end

function Player:set_flame(dir, rate)
   local rect = nil
   local vel = nil
   local s = 4
   local v = 1000
   local dim2 = self.dim / 2
   if dir[1] > 0 then
      rect = {dim2 - s, -dim2, dim2 + s, dim2}
      vel = {v, 0}
   elseif dir[1] < 0 then
      rect = {-dim2 - s, -dim2, -dim2 + s, dim2}
      vel = {-v, 0}
   elseif dir[2] > 0 then
      rect = {-dim2, dim2 - s, dim2, dim2 + s}
      vel = {0, v}
   elseif dir[2] < 0 then
      rect = {-dim2, -dim2 - s, dim2, -dim2 + s}
      vel = {0, -v}
   end

   if rate > 0 then
      self.psbox:initial(rect)
      self.psbox:refresh(rect)
      self.psbox:minv(vel)
      self.psbox:maxv(vel)
   end
   self.activator:rate(rate)
end

function Player:update()
   local input = util.input_state()
   local leftright = self.speed * input.leftright
   local updown = self.speed * input.updown

   local go = self.go
   local steering = self.steering

   local params = {
      force_max = 1000,
      speed_max = 100,
      old_angle = 0,
      application_time = world:dt()
   }

   steering:begin(params)
   local desired_vel = vector.new({leftright, updown})
   steering:apply_desired_velocity(desired_vel, go:vel())
   steering:complete()

   if desired_vel:length() > 0 then
      local zero = vector.new({0,0})
      self:set_flame(zero-desired_vel, 10000)
   else
      self:set_flame({0,0}, 0)
   end

   go:apply_force(steering:force())
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

   Player({screen_width/2, screen_height/2})
end
