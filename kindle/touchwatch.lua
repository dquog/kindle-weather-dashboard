-- touchwatch.lua — grab the Kindle touchscreen and report taps (runs on KOReader's LuaJIT).
--
--   luajit touchwatch.lua DEVICE --check          exit 0 if DEVICE can be grabbed
--   luajit touchwatch.lua DEVICE X1 Y1 X2 Y2      print "TOUCH x y" for taps (at most one
--                                                 line a second) and "HOME x y", then exit,
--                                                 when a tap lands inside the box
--
-- Grabbing (EVIOCGRAB) makes the touchscreen ours alone, so the frozen Kindle UI
-- underneath never sees these taps. The grab ends when this process exits.
local ffi = require("ffi")
ffi.cdef[[
int open(const char *pathname, int flags);
int close(int fd);
int ioctl(int fd, unsigned long request, int arg);
long read(int fd, void *buf, unsigned long count);
char *strerror(int errnum);
struct dash_input_event { long tv_sec; long tv_usec; uint16_t type; uint16_t code; int32_t value; };
]]
local C = ffi.C
local EVIOCGRAB = 0x40044590 -- _IOW('E', 0x90, int)
local O_RDONLY = 0

local function fail(what)
  io.write("ERROR ", what, ": ", ffi.string(C.strerror(ffi.errno())), "\n")
  io.flush()
  os.exit(1)
end

local dev = arg[1]
local fd = C.open(dev, O_RDONLY)
if fd < 0 then fail("open " .. tostring(dev)) end
if C.ioctl(fd, EVIOCGRAB, 1) ~= 0 then fail("grab " .. dev) end

if arg[2] == "--check" then
  C.ioctl(fd, EVIOCGRAB, 0)
  C.close(fd)
  os.exit(0)
end

local x1, y1, x2, y2 = tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
io.stdout:setvbuf("line")

local EVSIZE = ffi.sizeof("struct dash_input_event")
local buf = ffi.new("struct dash_input_event[64]")
local x, y, last_logged

while true do
  local n = tonumber(C.read(fd, buf, ffi.sizeof(buf)))
  if n <= 0 then fail("read " .. dev) end
  for i = 0, n / EVSIZE - 1 do
    local e = buf[i]
    if e.type == 3 and (e.code == 53 or e.code == 0) then      -- ABS_MT_POSITION_X / ABS_X
      x = e.value
    elseif e.type == 3 and (e.code == 54 or e.code == 1) then  -- ABS_MT_POSITION_Y / ABS_Y
      y = e.value
    elseif e.type == 0 and e.code == 0 and x and y then        -- SYN_REPORT: one complete sample
      if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
        io.write("HOME ", x, " ", y, "\n")
        C.close(fd)
        os.exit(0)
      end
      local sec = tonumber(e.tv_sec)
      if sec ~= last_logged then
        io.write("TOUCH ", x, " ", y, "\n")
        last_logged = sec
      end
    end
  end
end
