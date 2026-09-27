-- Implementação determinística da porta Clock, para testes de app/core
-- (orçamentos de tempo do IndexBuilder fatiado, F2+).
local FakeClock = {}
FakeClock.__index = FakeClock

function FakeClock.new(startSec)
    return setmetatable({ t = startSec or 0 }, FakeClock)
end

function FakeClock:now()
    return self.t
end

function FakeClock:advance(deltaSec)
    self.t = self.t + deltaSec
end

return FakeClock
